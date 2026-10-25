-- ============================================================
-- SWOUF – Espace refuge, étape 2 : tables et règles de sécurité
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- 1. Petites fonctions utiles aux règles de sécurité
-- E-mail confirmé de la personne connectée (lu côté serveur, impossible à falsifier)
create or replace function public.my_email() returns text
language sql stable security definer set search_path = '' as $$
  select lower(email) from auth.users where id = auth.uid() and email_confirmed_at is not null
$$;

-- Seul le compte swouf.app@gmail.com est administratrice
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.my_email() = 'swouf.app@gmail.com', false)
$$;

-- Date de modification mise à jour automatiquement (déjà créée à l'étape 1 de l'app, redéfinie à l'identique)
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

-- 2. Refuges
create table if not exists public.shelters (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null check (char_length(name) between 2 and 120),
  approval_number       text not null check (char_length(approval_number) between 2 and 60),  -- numéro d'agrément
  address               text not null check (char_length(address) <= 200),
  postal_code           text not null check (char_length(postal_code) <= 12),                -- sert au calcul de distance
  city                  text check (char_length(city) <= 80),
  country               text not null default 'BE',
  contact_name          text not null check (char_length(contact_name) <= 120),
  phone                 text not null check (char_length(phone) <= 30),
  website               text check (char_length(website) <= 300),                            -- site ou page Facebook
  logo_path             text,                                                                 -- fichier dans le stockage (étape 3)
  status                text not null default 'en_attente'
                        check (status in ('en_attente','actif','refuse','suspendu')),
  is_test               boolean not null default false,                                       -- mode test : jamais visible dans l'app
  charter_accepted_at   timestamptz not null,                                                 -- charte + confidentialité acceptées
  deletion_requested_at timestamptz,                                                          -- demande de suppression (RGPD)
  created_by            uuid default auth.uid() references auth.users(id) on delete set null,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);

-- 3. Personnes qui gèrent un refuge (responsable + bénévoles), reconnues par leur e-mail Google
create table if not exists public.shelter_members (
  shelter_id uuid not null references public.shelters(id) on delete cascade,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  role       text not null default 'benevole' check (role in ('responsable','benevole')),
  added_at   timestamptz default now(),
  primary key (shelter_id, email)
);
create index if not exists shelter_members_email_idx on public.shelter_members(email);

-- 4. Chiens des refuges
create table if not exists public.shelter_dogs (
  id              uuid primary key default gen_random_uuid(),
  shelter_id      uuid not null references public.shelters(id) on delete cascade,
  name            text not null check (char_length(name) between 1 and 60),
  birth_date      date,                                   -- calculée depuis l'âge saisi, pour que l'âge reste juste
  age_estimated   boolean not null default true,          -- âge exact ou estimé
  sex             text check (sex in ('male','femelle')),
  breed           text check (char_length(breed) <= 80),  -- race ou croisement
  sterilized      boolean,
  chipped         boolean,
  vaccinated      boolean,
  adoption_fee    numeric(7,2) check (adoption_fee >= 0),
  criteria        jsonb not null default '{}'::jsonb check (jsonb_typeof(criteria) = 'object'),  -- critères du quiz Swouf
  special_needs   text check (char_length(special_needs) <= 300),
  story           text check (char_length(story) <= 1000),  -- « Son histoire »
  photo_path      text,                                     -- photo unique (étape 3)
  published       boolean not null default false,           -- bouton « Publier »
  hidden_by_admin boolean not null default false,           -- masqué par l'administration
  is_test         boolean not null default false,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()                 -- sert au rappel des 30 jours
);
create index if not exists shelter_dogs_shelter_idx on public.shelter_dogs(shelter_id);

-- 5. Fonctions qui dépendent des tables
create or replace function public.is_member(sid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.shelter_members m where m.shelter_id = sid and m.email = public.my_email())
$$;

create or replace function public.is_owner(sid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.shelter_members m where m.shelter_id = sid and m.email = public.my_email() and m.role = 'responsable')
$$;

create or replace function public.shelter_is_active(sid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.shelters s where s.id = sid and s.status = 'actif')
$$;

-- 6. Protections automatiques
-- Un refuge ne peut jamais se valider lui-même ni changer son mode test
create or replace function public.shelters_protect() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then
      new.status := 'en_attente';
      new.is_test := false;
      new.created_by := auth.uid();
      new.deletion_requested_at := null;
    else
      new.status := old.status;
      new.is_test := old.is_test;
      new.created_by := old.created_by;
      new.approval_number := old.approval_number;  -- l'agrément vérifié ne change plus sans moi
    end if;
  end if;
  return new;
end $$;
drop trigger if exists shelters_protect on public.shelters;
create trigger shelters_protect before insert or update on public.shelters for each row execute function public.shelters_protect();

-- La personne qui inscrit le refuge en devient automatiquement responsable
create or replace function public.shelters_add_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.my_email() is not null then
    insert into public.shelter_members (shelter_id, email, role)
    values (new.id, public.my_email(), 'responsable') on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists shelters_add_owner on public.shelters;
create trigger shelters_add_owner after insert on public.shelters for each row execute function public.shelters_add_owner();

-- Un refuge ne peut ni démasquer un chien masqué, ni changer son mode test, ni le déplacer vers un autre refuge
create or replace function public.shelter_dogs_protect() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then
    if tg_op = 'UPDATE' then
      new.shelter_id := old.shelter_id;
      new.hidden_by_admin := old.hidden_by_admin;
    else
      new.hidden_by_admin := false;
    end if;
    new.is_test := (select s.is_test from public.shelters s where s.id = new.shelter_id);
  end if;
  return new;
end $$;
drop trigger if exists shelter_dogs_protect on public.shelter_dogs;
create trigger shelter_dogs_protect before insert or update on public.shelter_dogs for each row execute function public.shelter_dogs_protect();

drop trigger if exists shelters_touch on public.shelters;
create trigger shelters_touch before update on public.shelters for each row execute function public.touch_updated_at();
drop trigger if exists shelter_dogs_touch on public.shelter_dogs;
create trigger shelter_dogs_touch before update on public.shelter_dogs for each row execute function public.touch_updated_at();

-- 7. Sécurité ligne par ligne (Row Level Security)
alter table public.shelters        enable row level security;
alter table public.shelter_members enable row level security;
alter table public.shelter_dogs    enable row level security;

-- Refuges : chacun voit et modifie le sien ; l'administratrice voit tout
drop policy if exists "refuges : lire le sien"      on public.shelters;
drop policy if exists "refuges : s'inscrire"        on public.shelters;
drop policy if exists "refuges : modifier le sien"  on public.shelters;
drop policy if exists "refuges : supprimer (admin)" on public.shelters;
create policy "refuges : lire le sien"      on public.shelters for select using (public.is_admin() or public.is_member(id));
create policy "refuges : s'inscrire"        on public.shelters for insert with check (auth.uid() is not null and public.my_email() is not null);
create policy "refuges : modifier le sien"  on public.shelters for update using (public.is_admin() or public.is_member(id)) with check (public.is_admin() or public.is_member(id));
create policy "refuges : supprimer (admin)" on public.shelters for delete using (public.is_admin());

-- Équipe : les membres voient leur équipe ; le responsable ajoute ou retire des bénévoles ; chacun peut se retirer
drop policy if exists "équipe : lire la sienne"   on public.shelter_members;
drop policy if exists "équipe : ajouter"          on public.shelter_members;
drop policy if exists "équipe : modifier (admin)" on public.shelter_members;
drop policy if exists "équipe : retirer"          on public.shelter_members;
create policy "équipe : lire la sienne"   on public.shelter_members for select using (public.is_admin() or public.is_member(shelter_id));
create policy "équipe : ajouter"          on public.shelter_members for insert with check (public.is_admin() or (public.is_owner(shelter_id) and role = 'benevole'));
create policy "équipe : modifier (admin)" on public.shelter_members for update using (public.is_admin()) with check (public.is_admin());
create policy "équipe : retirer"          on public.shelter_members for delete using (public.is_admin() or public.is_owner(shelter_id) or email = public.my_email());

-- Chiens : un refuge ne voit que ses chiens ; il ne peut ajouter ou modifier que s'il est validé (actif)
drop policy if exists "chiens refuge : lire les siens"      on public.shelter_dogs;
drop policy if exists "chiens refuge : ajouter"             on public.shelter_dogs;
drop policy if exists "chiens refuge : modifier"            on public.shelter_dogs;
drop policy if exists "chiens refuge : supprimer (adopté)"  on public.shelter_dogs;
create policy "chiens refuge : lire les siens"     on public.shelter_dogs for select using (public.is_admin() or public.is_member(shelter_id));
create policy "chiens refuge : ajouter"            on public.shelter_dogs for insert with check (public.is_admin() or (public.is_member(shelter_id) and public.shelter_is_active(shelter_id)));
create policy "chiens refuge : modifier"           on public.shelter_dogs for update using (public.is_admin() or (public.is_member(shelter_id) and public.shelter_is_active(shelter_id))) with check (public.is_admin() or (public.is_member(shelter_id) and public.shelter_is_active(shelter_id)));
create policy "chiens refuge : supprimer (adopté)" on public.shelter_dogs for delete using (public.is_admin() or public.is_member(shelter_id));

-- 8. Accès : utilisateurs connectés uniquement (jamais les visiteurs anonymes)
revoke all on public.shelters, public.shelter_members, public.shelter_dogs from anon;
grant select, insert, update, delete on public.shelters, public.shelter_members, public.shelter_dogs to authenticated;

-- 9. Ce que l'app Swouf pourra afficher (étape 6) : uniquement les chiens publiés,
--    de refuges validés, non masqués, jamais les chiens « test » (sauf pour l'administratrice qui le demande).
--    Seules les infos utiles sont données : ni numéro d'agrément, ni personne de contact, ni adresse complète.
create or replace function public.public_shelter_dogs(include_test boolean default false)
returns table (
  dog_id uuid, name text, birth_date date, age_estimated boolean, sex text, breed text,
  sterilized boolean, chipped boolean, vaccinated boolean, adoption_fee numeric,
  criteria jsonb, special_needs text, story text, photo_path text, updated_at timestamptz,
  shelter_id uuid, shelter_name text, shelter_postal_code text, shelter_city text, shelter_country text,
  shelter_phone text, shelter_website text, shelter_logo_path text
)
language sql stable security definer set search_path = '' as $$
  select d.id, d.name, d.birth_date, d.age_estimated, d.sex, d.breed,
         d.sterilized, d.chipped, d.vaccinated, d.adoption_fee,
         d.criteria, d.special_needs, d.story, d.photo_path, d.updated_at,
         s.id, s.name, s.postal_code, s.city, s.country, s.phone, s.website, s.logo_path
  from public.shelter_dogs d
  join public.shelters s on s.id = d.shelter_id
  where s.status = 'actif' and d.published and not d.hidden_by_admin
    and ((not s.is_test and not d.is_test) or (include_test and public.is_admin()))
$$;
revoke all on function public.public_shelter_dogs(boolean) from public;
grant execute on function public.public_shelter_dogs(boolean) to anon, authenticated;
