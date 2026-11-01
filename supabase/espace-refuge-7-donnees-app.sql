-- ============================================================
-- SWOUF – Newsletter, suppressions, inscriptions et tests dans l'administration
-- (ce qui partait jusqu'ici dans Google Sheets)
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : aucune donnée n'est supprimée.
-- ============================================================

-- 1. Abonnés à la newsletter (une seule ligne par adresse e-mail)
create table if not exists public.newsletter_subscribers (
  id              uuid primary key default gen_random_uuid(),
  email           text not null check (char_length(email) <= 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]{2,}$'),
  first_name      text check (char_length(first_name) <= 80),
  lang            text check (char_length(lang) <= 5),
  country         text check (char_length(country) <= 40),
  zip             text check (char_length(zip) <= 12),
  unsubscribed_at timestamptz,                       -- désinscrit (ne part plus dans l'export)
  created_at      timestamptz not null default now()
);
create unique index if not exists newsletter_email_unique on public.newsletter_subscribers (lower(email));

-- 2. Demandes de suppression des utilisateurs (bouton « Effacer mes données ») : délai légal d'un mois
create table if not exists public.user_deletion_requests (
  id         uuid primary key default gen_random_uuid(),
  first_name text check (char_length(first_name) <= 80),
  email      text check (char_length(email) <= 254),
  zip        text check (char_length(zip) <= 12),
  handled    boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3. Inscriptions dans l'app (avec ou sans Google)
create table if not exists public.app_signups (
  id         uuid primary key default gen_random_uuid(),
  first_name text check (char_length(first_name) <= 80),
  email      text check (char_length(email) <= 254),
  lang       text check (char_length(lang) <= 5),
  country    text check (char_length(country) <= 40),
  zip        text check (char_length(zip) <= 12),
  newsletter boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists app_signups_email_unique on public.app_signups (lower(email)) where email is not null;

-- 4. Tests réalisés, même sans compte, sans le prénom
create table if not exists public.app_tests (
  id         uuid primary key default gen_random_uuid(),
  country    text check (char_length(country) <= 40),
  zip        text check (char_length(zip) <= 12),
  lang       text check (char_length(lang) <= 5),
  breeds     text[] check (cardinality(breeds) <= 10),   -- races obtenues
  created_at timestamptz not null default now()
);
create index if not exists app_tests_created_idx on public.app_tests (created_at desc);

-- 5. Sécurité : l'app peut seulement ajouter une ligne ; lire, modifier et supprimer sont réservés à l'administratrice
alter table public.newsletter_subscribers enable row level security;
alter table public.user_deletion_requests enable row level security;
alter table public.app_signups            enable row level security;
alter table public.app_tests              enable row level security;

drop policy if exists "newsletter : s'abonner"          on public.newsletter_subscribers;
drop policy if exists "newsletter : gérer (admin)"      on public.newsletter_subscribers;
drop policy if exists "suppressions : demander"         on public.user_deletion_requests;
drop policy if exists "suppressions : gérer (admin)"    on public.user_deletion_requests;
drop policy if exists "inscriptions : ajouter"          on public.app_signups;
drop policy if exists "inscriptions : gérer (admin)"    on public.app_signups;
drop policy if exists "tests : ajouter"                 on public.app_tests;
drop policy if exists "tests : gérer (admin)"           on public.app_tests;

create policy "newsletter : s'abonner"       on public.newsletter_subscribers for insert to anon, authenticated with check (true);
create policy "newsletter : gérer (admin)"   on public.newsletter_subscribers for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "suppressions : demander"      on public.user_deletion_requests for insert to anon, authenticated with check (true);
create policy "suppressions : gérer (admin)" on public.user_deletion_requests for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "inscriptions : ajouter"       on public.app_signups for insert to anon, authenticated with check (true);
create policy "inscriptions : gérer (admin)" on public.app_signups for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "tests : ajouter"              on public.app_tests for insert to anon, authenticated with check (true);
create policy "tests : gérer (admin)"        on public.app_tests for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.newsletter_subscribers, public.user_deletion_requests, public.app_signups, public.app_tests from anon, authenticated;
-- à l'ajout, seules ces colonnes peuvent être remplies (impossible de falsifier la date ou « traité »)
grant insert (email, first_name, lang, country, zip)                on public.newsletter_subscribers to anon, authenticated;
grant insert (first_name, email, zip)                               on public.user_deletion_requests to anon, authenticated;
grant insert (first_name, email, lang, country, zip, newsletter)    on public.app_signups            to anon, authenticated;
grant insert (country, zip, lang, breeds)                           on public.app_tests              to anon, authenticated;
grant select, update, delete on public.newsletter_subscribers, public.user_deletion_requests, public.app_signups, public.app_tests to authenticated;

-- 6. Les comptes déjà créés avant cette mise à jour apparaissent aussi dans les inscriptions
insert into public.app_signups (first_name, email, lang, country, zip, newsletter, created_at)
select p.name, lower(u.email), p.lang, p.country, p.zip, coalesce(p.notif_promo, false), p.created_at
from public.profiles p
join auth.users u on u.id = p.id
where u.email is not null
on conflict do nothing;

-- 7. Statistiques de l'onglet « Statistiques » (réservées à l'administratrice)
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  return jsonb_build_object(
    'tests_total', (select count(*) from public.app_tests),
    'tests_30d',   (select count(*) from public.app_tests where created_at > now() - interval '30 days'),
    'signups',     (select count(*) from public.app_signups),
    'newsletter',  (select count(*) from public.newsletter_subscribers where unsubscribed_at is null),
    'top_breeds',  (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select b as name, count(*) as n from public.app_tests t cross join lateral unnest(t.breeds) as b
        group by b order by count(*) desc, b limit 15) x),
    'by_region',   (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select r as name, count(*) as n from (
          select case
            when t.country = 'BE' and t.zip ~ '^[0-9]{4}$' then case
              when t.zip::int between 1000 and 1299 then 'BE-BRU'
              when t.zip::int between 1300 and 1499 or t.zip::int between 4000 and 7999 then 'BE-WAL'
              else 'BE-FLA' end
            else coalesce(t.country, '?') end as r
          from public.app_tests t) s
        group by r order by count(*) desc, r) x)
  );
end $$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

-- 8. Traiter une demande de suppression : efface l'abonnement, l'inscription et le compte liés à cette adresse
create or replace function public.admin_erase_user(request_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare mail text;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  select lower(email) into mail from public.user_deletion_requests where id = request_id;
  if mail is not null and mail <> '' then
    if mail = 'swouf.app@gmail.com' then raise exception 'Le compte administrateur ne peut pas être effacé ici'; end if;
    delete from public.newsletter_subscribers where lower(email) = mail;
    delete from public.app_signups where lower(email) = mail;
    delete from auth.users where lower(email) = mail;   -- son profil et ses animaux partent avec le compte
  end if;
  update public.user_deletion_requests set handled = true where id = request_id;
end $$;
revoke all on function public.admin_erase_user(uuid) from public, anon;
grant execute on function public.admin_erase_user(uuid) to authenticated;
