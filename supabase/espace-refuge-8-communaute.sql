-- ============================================================
-- SWOUF – Espace communautaire : tableaux, sécurité et filtres
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : aucune donnée n'est supprimée.
-- ============================================================

-- 1. Outils de recherche sans accents (inclus et gratuits dans Supabase)
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

-- Met un texte en minuscules, sans accents : « Éléonore » et « eleonore » deviennent identiques
create or replace function public.cm_norm(t text) returns text
language sql immutable set search_path = '' as $$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, translate(coalesce(t, ''), '’', '''')))
$$;

-- 2. Catégories et onglets de Voyage (modifiables sans toucher au code de l'app)
create table if not exists public.community_categories (
  slug      text primary key,
  label_fr  text not null, label_en text not null, label_nl text not null,
  desc_fr   text, desc_en text, desc_nl text,
  position  int not null default 0,
  active    boolean not null default true
);
create table if not exists public.community_tabs (
  slug         text primary key,
  label_fr     text not null, label_en text not null, label_nl text not null,
  desc_fr      text, desc_en text, desc_nl text,
  flag         text,
  country_code text,          -- pays de l'onglet : sert au badge « Local » (vide pour Général)
  position     int not null default 0,
  active       boolean not null default true
);

insert into public.community_categories (slug, label_fr, label_en, label_nl, desc_fr, desc_en, desc_nl, position) values
 ('chiot', 'Chiot', 'Puppy', 'Pup', 'L''arrivée d''un chiot : propreté, mordillements, premières sorties, socialisation, nuits…', 'A puppy''s arrival: house-training, nipping, first walks, socialisation, nights…', 'De komst van een pup: zindelijkheid, bijten, eerste uitstapjes, socialisatie, nachten…', 1),
 ('promenade', 'Promenade', 'Walks', 'Wandelen', 'Balades, parcs et forêts, rencontres entre chiens, bons plans près de chez toi.', 'Walks, parks and forests, dogs meeting dogs, good spots near you.', 'Wandelingen, parken en bossen, ontmoetingen tussen honden, leuke plekjes bij jou in de buurt.', 2),
 ('voyage', 'Voyage', 'Travel', 'Reizen', null, null, null, 3),
 ('adoption', 'Adoption', 'Adoption', 'Adoptie', 'Adopter en refuge : préparer son arrivée, les premiers jours, vos belles histoires.', 'Adopting from a shelter: preparing for the arrival, the first days, your lovely stories.', 'Adopteren uit een asiel: de komst voorbereiden, de eerste dagen, jullie mooie verhalen.', 4),
 ('senior', 'Senior', 'Senior', 'Senior', 'Le quotidien avec un chien âgé : confort, rythme, astuces et tendresse.', 'Daily life with an older dog: comfort, pace, tips and tenderness.', 'Het dagelijks leven met een oudere hond: comfort, ritme, tips en tederheid.', 5),
 ('victoires', 'Petites victoires', 'Small victories', 'Kleine overwinningen', 'Les progrès dont tu es fier·e : laisse, rappel, propreté, confiance…', 'The progress you''re proud of: leash, recall, house-training, confidence…', 'De vooruitgang waar je trots op bent: leiband, terugroepen, zindelijkheid, vertrouwen…', 6),
 ('betises', 'Bêtises', 'Mischief', 'Kattenkwaad', 'Les bêtises qui nous font (un peu) rire : vols, objets détruits, regards coupables.', 'The mischief that makes us laugh (a little): thefts, destroyed objects, guilty looks.', 'Het kattenkwaad waar we (een beetje) om lachen: diefstal, vernielde spullen, schuldige blikken.', 7)
on conflict (slug) do nothing;

insert into public.community_tabs (slug, label_fr, label_en, label_nl, desc_fr, desc_en, desc_nl, flag, country_code, position) values
 ('general', 'Général', 'General', 'Algemeen', 'Conseils pour voyager avec ton chien, quelle que soit la destination.', 'Tips for travelling with your dog, whatever the destination.', 'Tips om met je hond te reizen, wat de bestemming ook is.', '🌍', null, 1),
 ('BE', 'Belgique', 'Belgium', 'België', 'Bons plans et questions pour voyager en Belgique avec ton chien.', 'Good tips and questions for travelling in Belgium with your dog.', 'Tips en vragen om met je hond in België te reizen.', '🇧🇪', 'BE', 2),
 ('FR', 'France', 'France', 'Frankrijk', 'Bons plans et questions pour voyager en France avec ton chien.', 'Good tips and questions for travelling in France with your dog.', 'Tips en vragen om met je hond in Frankrijk te reizen.', '🇫🇷', 'FR', 3)
on conflict (slug) do nothing;

-- 3. Membres : ce qui s'affiche sur une publication, et la charte acceptée
create table if not exists public.community_members (
  user_id             uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  display_name        text not null check (char_length(display_name) between 1 and 40),
  dog_label           text check (char_length(dog_label) <= 80),    -- « Filou, beagle »
  country             text not null check (char_length(country) between 2 and 5),
  charter_accepted_at timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

-- Sanctions : séparées, chacun ne voit que les siennes
create table if not exists public.community_sanctions (
  user_id         uuid primary key references public.community_members(user_id) on delete cascade,
  warnings        int not null default 0,
  suspended_until timestamptz,
  banned_at       timestamptz,
  last_reason     text check (char_length(last_reason) <= 300),
  updated_at      timestamptz not null default now()
);

-- 4. Publications (texte uniquement ; photo_path est prévu pour les photos plus tard)
create table if not exists public.community_posts (
  id              uuid primary key default gen_random_uuid(),
  author_id       uuid not null default auth.uid() references public.community_members(user_id) on delete cascade,
  category        text not null references public.community_categories(slug),
  tab             text references public.community_tabs(slug),       -- uniquement pour Voyage
  country         text not null default '',                          -- rempli automatiquement
  body            text not null check (char_length(btrim(body)) between 1 and 2000),   -- texte d'origine, visible seulement par l'auteur et l'administration
  body_display    text not null default '',                          -- texte affiché (noms masqués)
  search_norm     text not null default '',
  status          text not null default 'published' check (status in ('published','pending','removed')),
  pending_reasons text[] not null default '{}',
  photo_path      text,
  like_count      int not null default 0,
  comment_count   int not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists community_posts_feed_idx on public.community_posts (category, country, created_at desc);
create index if not exists community_posts_author_idx on public.community_posts (author_id, created_at desc);
create index if not exists community_posts_search_idx on public.community_posts using gin (search_norm extensions.gin_trgm_ops);

-- 5. Commentaires
create table if not exists public.community_comments (
  id              uuid primary key default gen_random_uuid(),
  post_id         uuid not null references public.community_posts(id) on delete cascade,
  author_id       uuid not null default auth.uid() references public.community_members(user_id) on delete cascade,
  body            text not null check (char_length(btrim(body)) between 1 and 1000),
  body_display    text not null default '',
  search_norm     text not null default '',
  is_local        boolean not null default false,                    -- badge « 🏠 Local »
  status          text not null default 'published' check (status in ('published','pending','removed')),
  pending_reasons text[] not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists community_comments_post_idx on public.community_comments (post_id, created_at);
create index if not exists community_comments_author_idx on public.community_comments (author_id, created_at desc);
create index if not exists community_comments_search_idx on public.community_comments using gin (search_norm extensions.gin_trgm_ops);

-- 6. Likes
create table if not exists public.community_likes (
  post_id    uuid not null references public.community_posts(id) on delete cascade,
  user_id    uuid not null default auth.uid() references public.community_members(user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index if not exists community_likes_user_idx on public.community_likes (user_id);

-- 7. Signalements
create table if not exists public.community_reports (
  id             uuid primary key default gen_random_uuid(),
  reporter_id    uuid default auth.uid() references auth.users(id) on delete set null,
  target_type    text not null check (target_type in ('post','comment','profile')),
  post_id        uuid references public.community_posts(id) on delete cascade,
  comment_id     uuid references public.community_comments(id) on delete cascade,
  target_user_id uuid references public.community_members(user_id) on delete cascade,
  reason         text not null check (reason in ('insulte','harcelement','maltraitance','arnaque','vente','autre')),
  note           text check (char_length(note) <= 500),
  status         text not null default 'open' check (status in ('open','closed')),
  created_at     timestamptz not null default now()
);
create unique index if not exists community_reports_once on public.community_reports
  (reporter_id, target_type, coalesce(post_id::text, ''), coalesce(comment_id::text, ''), coalesce(target_user_id::text, ''));

-- 8. Vos listes : partenaires, noms non partenaires, mots blessants, mots liés à la vente
create table if not exists public.community_names (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('partner','blocked')),
  name       text not null check (char_length(btrim(name)) between 2 and 80),
  norm_name  text not null default '',
  url        text check (char_length(url) <= 300),
  created_at timestamptz not null default now()
);
create unique index if not exists community_names_unique on public.community_names (norm_name);

create table if not exists public.community_filter_terms (
  id         uuid primary key default gen_random_uuid(),
  list       text not null check (list in ('insulte','vente')),
  term       text not null check (char_length(btrim(term)) between 2 and 80),
  norm_term  text not null default '',
  created_at timestamptz not null default now()
);
create unique index if not exists community_filter_terms_unique on public.community_filter_terms (list, norm_term);

create table if not exists public.community_suggestions (
  id           uuid primary key default gen_random_uuid(),
  name_id      uuid references public.community_names(id) on delete cascade,
  note         text check (char_length(note) <= 300),
  suggested_by uuid default auth.uid() references auth.users(id) on delete set null,
  handled      boolean not null default false,
  created_at   timestamptz not null default now()
);

-- 9. Les filtres : ils tournent dans Supabase, l'app ne peut pas les contourner
-- Mots blessants ou liés à la vente présents dans un texte (mots entiers uniquement)
create or replace function public.cm_reasons(src text) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare n text := public.cm_norm(src); out_ text[];
begin
  select coalesce(array_agg(distinct t.list), '{}') into out_
  from public.community_filter_terms t
  where t.norm_term <> ''
    and n ~ ('(^|[^[:alnum:]])' || regexp_replace(t.norm_term, '([^[:alnum:][:space:]])', '\\\1', 'g') || '($|[^[:alnum:]])');
  return out_;
end $$;

-- Remplace les noms de vos listes par une marque : [[p:id]] pour un partenaire, [[x:id]] pour un non-partenaire
create or replace function public.cm_mask(src text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  clean text := replace(coalesce(src, ''), '[[', '[ [');   -- personne ne peut écrire une fausse marque
  n text := ''; idx int[] := '{}'; c text; i int; j int; len int;
  rec record; p int; s int; e int; clash boolean;
  starts int[] := '{}'; ends int[] := '{}'; toks text[] := '{}';
  r record;
begin
  -- position de chaque lettre sans accent dans le texte d'origine
  for i in 1 .. char_length(clean) loop
    c := public.cm_norm(substr(clean, i, 1));
    for j in 1 .. char_length(c) loop idx := idx || i; end loop;
    n := n || c;
  end loop;
  len := char_length(n);
  -- les noms les plus longs d'abord
  for rec in select id, kind, norm_name from public.community_names where norm_name <> '' order by char_length(norm_name) desc loop
    p := 1;
    while p <= len loop
      s := strpos(substr(n, p), rec.norm_name);
      exit when s = 0;
      s := s + p - 1; e := s + char_length(rec.norm_name) - 1;
      if (s = 1 or substr(n, s - 1, 1) !~ '[[:alnum:]]') and (e = len or substr(n, e + 1, 1) !~ '[[:alnum:]]') then
        clash := false;
        for i in 1 .. coalesce(array_length(starts, 1), 0) loop
          if s <= ends[i] and e >= starts[i] then clash := true; end if;
        end loop;
        if not clash then
          starts := starts || s; ends := ends || e;
          toks := toks || ('[[' || case when rec.kind = 'partner' then 'p' else 'x' end || ':' || rec.id::text || ']]');
        end if;
      end if;
      p := e + 1;
    end loop;
  end loop;
  -- on remplace en partant de la fin, pour garder les bonnes positions
  for r in select a, b, t from unnest(starts, ends, toks) as u(a, b, t) order by a desc loop
    clean := substr(clean, 1, idx[r.a] - 1) || r.t || substr(clean, idx[r.b] + 1);
  end loop;
  return clean;
end $$;

-- Texte de recherche : le texte affiché, sans les marques, sans accents
create or replace function public.cm_search(display text) returns text
language sql immutable set search_path = '' as $$
  select public.cm_norm(regexp_replace(coalesce(display, ''), '\[\[[^]]*\]\]', ' ', 'g'))
$$;

-- Peut-on écrire ? charte acceptée, pas suspendu, pas exclu, limite anti-spam
create or replace function public.cm_guard(what text) returns void
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); sa public.community_sanctions; n int;
begin
  if uid is null then raise exception 'swouf_login'; end if;
  if not exists (select 1 from public.community_members m where m.user_id = uid) then raise exception 'swouf_charter'; end if;
  select * into sa from public.community_sanctions s where s.user_id = uid;
  if sa.banned_at is not null then raise exception 'swouf_banned'; end if;
  if sa.suspended_until is not null and sa.suspended_until > now() then raise exception 'swouf_suspended'; end if;
  if public.is_admin() then return; end if;
  if what = 'post' then
    select count(*) into n from public.community_posts p where p.author_id = uid and p.created_at > now() - interval '1 hour';
    if n >= 5 then raise exception 'swouf_rate_limit'; end if;
  elsif what = 'comment' then
    select count(*) into n from public.community_comments c where c.author_id = uid and c.created_at > now() - interval '1 hour';
    if n >= 20 then raise exception 'swouf_rate_limit'; end if;
  end if;
end $$;

-- 10. Automatismes sur les publications
create or replace function public.community_posts_before() returns trigger
language plpgsql security definer set search_path = '' as $$
declare m public.community_members; why text[];
begin
  if tg_op = 'INSERT' then
    perform public.cm_guard('post');
    select * into m from public.community_members x where x.user_id = auth.uid();
    new.author_id := m.user_id; new.country := m.country; new.like_count := 0; new.comment_count := 0;
    new.created_at := now(); new.updated_at := now(); new.photo_path := null;
    if new.category = 'voyage' then
      if new.tab is null or not exists (select 1 from public.community_tabs t where t.slug = new.tab and t.active) then raise exception 'swouf_tab'; end if;
    else
      new.tab := null;
    end if;
  elsif new.body is not distinct from old.body then
    return new;   -- validation par l'administration, ou mise à jour des noms masqués
  else
    perform public.cm_guard('edit');
    new.updated_at := now();
  end if;
  why := public.cm_reasons(new.body);
  new.body_display := public.cm_mask(new.body);
  new.search_norm := public.cm_search(new.body_display);
  new.pending_reasons := why;
  if tg_op = 'UPDATE' and old.status = 'removed' then new.status := 'removed';
  elsif cardinality(why) > 0 then new.status := 'pending';
  else new.status := 'published';
  end if;
  return new;
end $$;
drop trigger if exists community_posts_before on public.community_posts;
create trigger community_posts_before before insert or update on public.community_posts
  for each row execute function public.community_posts_before();

-- 11. Automatismes sur les commentaires
create or replace function public.community_comments_before() returns trigger
language plpgsql security definer set search_path = '' as $$
declare m public.community_members; why text[]; tab_country text;
begin
  if tg_op = 'INSERT' then
    perform public.cm_guard('comment');
    select * into m from public.community_members x where x.user_id = auth.uid();
    if not exists (select 1 from public.community_posts p where p.id = new.post_id and p.status = 'published') then raise exception 'swouf_post'; end if;
    select t.country_code into tab_country from public.community_posts p join public.community_tabs t on t.slug = p.tab where p.id = new.post_id;
    new.author_id := m.user_id; new.is_local := (tab_country is not null and tab_country = m.country);
    new.created_at := now(); new.updated_at := now();
  elsif new.body is not distinct from old.body then
    return new;
  else
    perform public.cm_guard('edit');
    new.updated_at := now();
  end if;
  why := public.cm_reasons(new.body);
  new.body_display := public.cm_mask(new.body);
  new.search_norm := public.cm_search(new.body_display);
  new.pending_reasons := why;
  if tg_op = 'UPDATE' and old.status = 'removed' then new.status := 'removed';
  elsif cardinality(why) > 0 then new.status := 'pending';
  else new.status := 'published';
  end if;
  return new;
end $$;
drop trigger if exists community_comments_before on public.community_comments;
create trigger community_comments_before before insert or update on public.community_comments
  for each row execute function public.community_comments_before();

-- 12. Compteurs de likes et de commentaires
create or replace function public.community_count_comments() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pid uuid := case when tg_op = 'DELETE' then old.post_id else new.post_id end;
begin
  update public.community_posts p set comment_count =
    (select count(*) from public.community_comments c where c.post_id = pid and c.status = 'published')
  where p.id = pid;
  return null;
end $$;
drop trigger if exists community_comments_count on public.community_comments;
create trigger community_comments_count after insert or delete or update of status on public.community_comments
  for each row execute function public.community_count_comments();

create or replace function public.community_count_likes() returns trigger
language plpgsql security definer set search_path = '' as $$
declare pid uuid := case when tg_op = 'DELETE' then old.post_id else new.post_id end;
begin
  update public.community_posts p set like_count =
    (select count(*) from public.community_likes l where l.post_id = pid)
  where p.id = pid;
  return null;
end $$;
drop trigger if exists community_likes_count on public.community_likes;
create trigger community_likes_count after insert or delete on public.community_likes
  for each row execute function public.community_count_likes();

-- 13. Liker : uniquement avec un compte en règle, sur une publication visible
create or replace function public.community_likes_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform public.cm_guard('like');
  if not exists (select 1 from public.community_posts p where p.id = new.post_id and p.status = 'published') then raise exception 'swouf_post'; end if;
  new.user_id := auth.uid(); new.created_at := now();
  return new;
end $$;
drop trigger if exists community_likes_before on public.community_likes;
create trigger community_likes_before before insert on public.community_likes
  for each row execute function public.community_likes_before();

-- 14. Membre : la date d'acceptation de la charte ne se falsifie pas
create or replace function public.community_members_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then new.user_id := auth.uid(); new.charter_accepted_at := now(); new.created_at := now();
  else new.user_id := old.user_id; new.charter_accepted_at := old.charter_accepted_at; new.created_at := old.created_at;
  end if;
  return new;
end $$;
drop trigger if exists community_members_before on public.community_members;
create trigger community_members_before before insert or update on public.community_members
  for each row execute function public.community_members_before();

-- 15. Signalement : l'auteur visé se remplit tout seul
create or replace function public.community_reports_before() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.reporter_id := auth.uid(); new.status := 'open'; new.created_at := now();
  if new.target_type = 'post' then
    select p.author_id into new.target_user_id from public.community_posts p where p.id = new.post_id;
    new.comment_id := null;
  elsif new.target_type = 'comment' then
    select c.author_id, c.post_id into new.target_user_id, new.post_id from public.community_comments c where c.id = new.comment_id;
  else
    new.post_id := null; new.comment_id := null;
  end if;
  if new.target_user_id is null then raise exception 'swouf_report'; end if;
  return new;
end $$;
drop trigger if exists community_reports_before on public.community_reports;
create trigger community_reports_before before insert on public.community_reports
  for each row execute function public.community_reports_before();

-- 16. Vos listes : forme sans accents, et noms remis à jour dans tous les textes quand une liste change
create or replace function public.community_names_before() returns trigger
language plpgsql set search_path = '' as $$
begin new.norm_name := public.cm_norm(btrim(new.name)); return new; end $$;
drop trigger if exists community_names_before on public.community_names;
create trigger community_names_before before insert or update on public.community_names
  for each row execute function public.community_names_before();

create or replace function public.community_terms_before() returns trigger
language plpgsql set search_path = '' as $$
begin new.norm_term := public.cm_norm(btrim(new.term)); return new; end $$;
drop trigger if exists community_terms_before on public.community_filter_terms;
create trigger community_terms_before before insert or update on public.community_filter_terms
  for each row execute function public.community_terms_before();

create or replace function public.community_remask() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.community_posts p set body_display = public.cm_mask(p.body), search_norm = public.cm_search(public.cm_mask(p.body));
  update public.community_comments c set body_display = public.cm_mask(c.body), search_norm = public.cm_search(public.cm_mask(c.body));
  return null;
end $$;
drop trigger if exists community_names_remask on public.community_names;
create trigger community_names_remask after insert or update or delete on public.community_names
  for each statement execute function public.community_remask();

-- 17. Premières listes de mots (modifiables ensuite dans l'administration)
insert into public.community_filter_terms (list, term) values
 ('insulte','connard'),('insulte','connasse'),('insulte','salope'),('insulte','pute'),('insulte','enculé'),('insulte','ta gueule'),('insulte','ferme-la'),
 ('insulte','abruti'),('insulte','abrutie'),('insulte','crétin'),('insulte','crétine'),('insulte','imbécile'),('insulte','bouffon'),('insulte','merde'),('insulte','pauvre type'),
 ('vente','à vendre'),('vente','je vends'),('vente','je vend'),('vente','chiots disponibles'),('vente','chiot disponible'),('vente','portée'),
 ('vente','à donner'),('vente','je donne mon chien'),('vente','à placer'),('vente','cherche famille'),('vente','prix du chiot'),('vente','vente de chiots')
on conflict do nothing;

-- 18. Sécurité (Row Level Security) : visiteurs non connectés, aucun accès
alter table public.community_categories   enable row level security;
alter table public.community_tabs         enable row level security;
alter table public.community_members      enable row level security;
alter table public.community_sanctions    enable row level security;
alter table public.community_posts        enable row level security;
alter table public.community_comments     enable row level security;
alter table public.community_likes        enable row level security;
alter table public.community_reports      enable row level security;
alter table public.community_names        enable row level security;
alter table public.community_filter_terms enable row level security;
alter table public.community_suggestions  enable row level security;

drop policy if exists "catégories : lire" on public.community_categories;
drop policy if exists "catégories : gérer" on public.community_categories;
create policy "catégories : lire"  on public.community_categories for select to authenticated using (active or public.is_admin());
create policy "catégories : gérer" on public.community_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "onglets : lire" on public.community_tabs;
drop policy if exists "onglets : gérer" on public.community_tabs;
create policy "onglets : lire"  on public.community_tabs for select to authenticated using (active or public.is_admin());
create policy "onglets : gérer" on public.community_tabs for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "membres : lire" on public.community_members;
drop policy if exists "membres : rejoindre" on public.community_members;
drop policy if exists "membres : modifier le sien" on public.community_members;
drop policy if exists "membres : quitter" on public.community_members;
create policy "membres : lire"             on public.community_members for select to authenticated using (true);
create policy "membres : rejoindre"        on public.community_members for insert to authenticated with check (user_id = auth.uid());
create policy "membres : modifier le sien" on public.community_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "membres : quitter"          on public.community_members for delete to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "sanctions : voir les siennes" on public.community_sanctions;
create policy "sanctions : voir les siennes" on public.community_sanctions for select to authenticated using (user_id = auth.uid() or public.is_admin());

drop policy if exists "publications : lire" on public.community_posts;
drop policy if exists "publications : publier" on public.community_posts;
drop policy if exists "publications : modifier la sienne" on public.community_posts;
drop policy if exists "publications : supprimer" on public.community_posts;
create policy "publications : lire"              on public.community_posts for select to authenticated using (status = 'published' or (author_id = auth.uid() and status = 'pending') or public.is_admin());
create policy "publications : publier"           on public.community_posts for insert to authenticated with check (author_id = auth.uid());
create policy "publications : modifier la sienne" on public.community_posts for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "publications : supprimer"         on public.community_posts for delete to authenticated using (author_id = auth.uid() or public.is_admin());

drop policy if exists "commentaires : lire" on public.community_comments;
drop policy if exists "commentaires : écrire" on public.community_comments;
drop policy if exists "commentaires : modifier le sien" on public.community_comments;
drop policy if exists "commentaires : supprimer" on public.community_comments;
create policy "commentaires : lire"             on public.community_comments for select to authenticated using (status = 'published' or (author_id = auth.uid() and status = 'pending') or public.is_admin());
create policy "commentaires : écrire"           on public.community_comments for insert to authenticated with check (author_id = auth.uid());
create policy "commentaires : modifier le sien" on public.community_comments for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "commentaires : supprimer"        on public.community_comments for delete to authenticated using (author_id = auth.uid() or public.is_admin());

drop policy if exists "likes : voir les siens" on public.community_likes;
drop policy if exists "likes : liker" on public.community_likes;
drop policy if exists "likes : retirer" on public.community_likes;
create policy "likes : voir les siens" on public.community_likes for select to authenticated using (user_id = auth.uid());
create policy "likes : liker"          on public.community_likes for insert to authenticated with check (user_id = auth.uid());
create policy "likes : retirer"        on public.community_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists "signalements : signaler" on public.community_reports;
drop policy if exists "signalements : gérer" on public.community_reports;
create policy "signalements : signaler" on public.community_reports for insert to authenticated with check (true);
create policy "signalements : gérer"    on public.community_reports for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "noms : voir les partenaires" on public.community_names;
drop policy if exists "noms : gérer" on public.community_names;
create policy "noms : voir les partenaires" on public.community_names for select to authenticated using (kind = 'partner' or public.is_admin());
create policy "noms : gérer"                on public.community_names for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "mots : gérer" on public.community_filter_terms;
create policy "mots : gérer" on public.community_filter_terms for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "suggestions : proposer" on public.community_suggestions;
drop policy if exists "suggestions : gérer" on public.community_suggestions;
create policy "suggestions : proposer" on public.community_suggestions for insert to authenticated with check (true);
create policy "suggestions : gérer"    on public.community_suggestions for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 19. Droits par colonne : le texte d'origine n'est pas lisible, les champs sensibles ne s'écrivent pas
revoke all on public.community_categories, public.community_tabs, public.community_members, public.community_sanctions,
  public.community_posts, public.community_comments, public.community_likes, public.community_reports,
  public.community_names, public.community_filter_terms, public.community_suggestions from anon, authenticated;

grant select on public.community_categories, public.community_tabs to authenticated;
grant insert, update, delete on public.community_categories, public.community_tabs to authenticated;

grant select (user_id, display_name, dog_label, country, created_at) on public.community_members to authenticated;
grant insert (display_name, dog_label, country) on public.community_members to authenticated;
grant update (display_name, dog_label, country) on public.community_members to authenticated;
grant delete on public.community_members to authenticated;

grant select on public.community_sanctions to authenticated;

grant select (id, author_id, category, tab, country, body_display, status, photo_path, like_count, comment_count, created_at, updated_at) on public.community_posts to authenticated;
grant insert (category, tab, body) on public.community_posts to authenticated;
grant update (body) on public.community_posts to authenticated;
grant delete on public.community_posts to authenticated;

grant select (id, post_id, author_id, body_display, is_local, status, created_at, updated_at) on public.community_comments to authenticated;
grant insert (post_id, body) on public.community_comments to authenticated;
grant update (body) on public.community_comments to authenticated;
grant delete on public.community_comments to authenticated;

grant select (post_id, user_id, created_at) on public.community_likes to authenticated;
grant insert (post_id) on public.community_likes to authenticated;
grant delete on public.community_likes to authenticated;

grant insert (target_type, post_id, comment_id, target_user_id, reason, note) on public.community_reports to authenticated;
grant select, update, delete on public.community_reports to authenticated;

grant select, insert, update, delete on public.community_names, public.community_filter_terms to authenticated;

grant insert (name_id, note) on public.community_suggestions to authenticated;
grant select, update, delete on public.community_suggestions to authenticated;

-- 20. Recherche dans une catégorie (publications et commentaires, sans accents ni majuscules)
create or replace function public.community_search(p_category text, p_tab text, p_q text) returns setof uuid
language plpgsql stable security definer set search_path = '' as $$
declare me text; q text := public.cm_norm(btrim(coalesce(p_q, '')));
begin
  if auth.uid() is null or char_length(q) < 2 then return; end if;
  select m.country into me from public.community_members m where m.user_id = auth.uid();
  q := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
    select p.id from public.community_posts p
    where p.status = 'published'
      and case
            when p_category is null or p_category = 'tout' then (p.category <> 'voyage' and p.country = me) or (p.category = 'voyage' and (p.tab = 'general' or p.tab = me))
            when p_category = 'voyage' then p.category = 'voyage' and (p_tab is null or p.tab = p_tab)
            else p.category = p_category and p.country = me
          end
      and (p.search_norm like q or exists (select 1 from public.community_comments c where c.post_id = p.id and c.status = 'published' and c.search_norm like q))
    order by p.created_at desc limit 100;
end $$;
revoke all on function public.community_search(text, text, text) from public, anon;
grant execute on function public.community_search(text, text, text) to authenticated;

-- 21. Modération (réservée à l'administratrice)
-- Tout ce qui attend : textes en attente, signalements ouverts, suggestions, compteur
create or replace function public.admin_community_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  return jsonb_build_object(
    'posts', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select p.id, p.body, p.body_display, p.category, p.tab, p.pending_reasons, p.created_at, p.author_id, m.display_name, m.country
       from public.community_posts p join public.community_members m on m.user_id = p.author_id where p.status = 'pending') x),
    'comments', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select c.id, c.post_id, c.body, c.body_display, c.pending_reasons, c.created_at, c.author_id, m.display_name, m.country
       from public.community_comments c join public.community_members m on m.user_id = c.author_id where c.status = 'pending') x),
    'reports', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select r.id, r.target_type, r.reason, r.note, r.created_at, r.post_id, r.comment_id, r.target_user_id, m.display_name,
              case r.target_type when 'post' then p.body when 'comment' then c.body end as text,
              s.warnings, s.suspended_until, s.banned_at
       from public.community_reports r
       left join public.community_members m on m.user_id = r.target_user_id
       left join public.community_posts p on p.id = r.post_id
       left join public.community_comments c on c.id = r.comment_id
       left join public.community_sanctions s on s.user_id = r.target_user_id
       where r.status = 'open') x),
    'suggestions', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (
       select g.id, g.note, g.created_at, n.name from public.community_suggestions g
       left join public.community_names n on n.id = g.name_id where not g.handled) x)
  );
end $$;

-- Nombre d'éléments à vérifier (compteur de l'administration)
create or replace function public.admin_community_count() returns int
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  return (select count(*) from public.community_posts where status = 'pending')
       + (select count(*) from public.community_comments where status = 'pending')
       + (select count(*) from public.community_reports where status = 'open');
end $$;

-- Valider ou supprimer un texte
create or replace function public.admin_moderate(p_type text, p_id uuid, p_action text) returns void
language plpgsql security definer set search_path = '' as $$
declare st text := case p_action when 'validate' then 'published' when 'remove' then 'removed' end;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  if st is null then raise exception 'Action inconnue'; end if;
  if p_type = 'post' then update public.community_posts set status = st where id = p_id;
  elsif p_type = 'comment' then update public.community_comments set status = st where id = p_id;
  else raise exception 'Type inconnu'; end if;
  -- les signalements sur ce texte sont clos quand il est supprimé
  if st = 'removed' then
    update public.community_reports set status = 'closed' where (p_type = 'post' and post_id = p_id) or (p_type = 'comment' and comment_id = p_id);
  end if;
end $$;

-- Sanctions : avertir, suspendre (nombre de jours), exclure, lever. Le motif est visible par la personne.
create or replace function public.admin_sanction(p_user uuid, p_action text, p_days int, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  insert into public.community_sanctions (user_id) values (p_user) on conflict (user_id) do nothing;
  update public.community_sanctions s set
    warnings = case when p_action = 'warn' then s.warnings + 1 else s.warnings end,
    suspended_until = case when p_action = 'suspend' then now() + make_interval(days => greatest(coalesce(p_days, 7), 1))
                           when p_action = 'lift' then null else s.suspended_until end,
    banned_at = case when p_action = 'ban' then now() when p_action = 'lift' then null else s.banned_at end,
    last_reason = left(coalesce(p_reason, s.last_reason), 300),
    updated_at = now()
  where s.user_id = p_user;
end $$;

-- Clore un signalement sans autre action
create or replace function public.admin_close_report(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administration'; end if;
  update public.community_reports set status = 'closed' where id = p_id;
end $$;

-- 22. Fonctions internes : pas appelables depuis l'extérieur
revoke all on function public.cm_reasons(text), public.cm_mask(text), public.cm_guard(text) from public, anon, authenticated;
revoke all on function public.community_posts_before(), public.community_comments_before(), public.community_count_comments(),
  public.community_count_likes(), public.community_likes_before(), public.community_members_before(),
  public.community_reports_before(), public.community_names_before(), public.community_terms_before(), public.community_remask()
  from public, anon, authenticated;
revoke all on function public.admin_community_queue(), public.admin_community_count(), public.admin_moderate(text, uuid, text),
  public.admin_sanction(uuid, text, int, text), public.admin_close_report(uuid) from public, anon;
grant execute on function public.admin_community_queue(), public.admin_community_count(), public.admin_moderate(text, uuid, text),
  public.admin_sanction(uuid, text, int, text), public.admin_close_report(uuid) to authenticated;
