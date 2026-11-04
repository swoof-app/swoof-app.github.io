-- ============================================================
-- SWOUF - Communaute : correction des accents, photos dans Betises
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Ce fichier n'utilise que des lettres sans accent : le copier-coller ne peut plus les abimer.
-- Peut etre relance sans risque.
-- ============================================================

-- 1. Remet l'outil qui retire les accents en bon etat
create or replace function public.cm_norm(t text) returns text
language sql immutable set search_path = '' as $fn$
  select lower(extensions.unaccent('extensions.unaccent'::regdictionary, translate(coalesce(t, ''), E'\u2019', '''')))
$fn$;

-- 2. Remet les textes corrects dans les categories et les onglets
update public.community_categories set label_fr='Chiot', label_en='Puppy', label_nl='Pup', desc_fr=E'L''arriv\u00e9e d''un chiot : propret\u00e9, mordillements, premi\u00e8res sorties, socialisation, nuits\u2026', desc_en=E'A puppy''s arrival: house-training, nipping, first walks, socialisation, nights\u2026', desc_nl=E'De komst van een pup: zindelijkheid, bijten, eerste uitstapjes, socialisatie, nachten\u2026' where slug='chiot';
update public.community_categories set label_fr='Promenade', label_en='Walks', label_nl='Wandelen', desc_fr=E'Balades, parcs et for\u00eats, rencontres entre chiens, bons plans pr\u00e8s de chez toi.', desc_en='Walks, parks and forests, dogs meeting dogs, good spots near you.', desc_nl='Wandelingen, parken en bossen, ontmoetingen tussen honden, leuke plekjes bij jou in de buurt.' where slug='promenade';
update public.community_categories set label_fr='Voyage', label_en='Travel', label_nl='Reizen', desc_fr=null, desc_en=null, desc_nl=null where slug='voyage';
update public.community_categories set label_fr='Adoption', label_en='Adoption', label_nl='Adoptie', desc_fr=E'Adopter en refuge : pr\u00e9parer son arriv\u00e9e, les premiers jours, vos belles histoires.', desc_en='Adopting from a shelter: preparing for the arrival, the first days, your lovely stories.', desc_nl='Adopteren uit een asiel: de komst voorbereiden, de eerste dagen, jullie mooie verhalen.' where slug='adoption';
update public.community_categories set label_fr='Senior', label_en='Senior', label_nl='Senior', desc_fr=E'Le quotidien avec un chien \u00e2g\u00e9 : confort, rythme, astuces et tendresse.', desc_en='Daily life with an older dog: comfort, pace, tips and tenderness.', desc_nl='Het dagelijks leven met een oudere hond: comfort, ritme, tips en tederheid.' where slug='senior';
update public.community_categories set label_fr='Petites victoires', label_en='Small victories', label_nl='Kleine overwinningen', desc_fr=E'Les progr\u00e8s dont tu es fier\u00b7e : laisse, rappel, propret\u00e9, confiance\u2026', desc_en=E'The progress you''re proud of: leash, recall, house-training, confidence\u2026', desc_nl=E'De vooruitgang waar je trots op bent: leiband, terugroepen, zindelijkheid, vertrouwen\u2026' where slug='victoires';
update public.community_categories set label_fr=E'B\u00eatises', label_en='Mischief', label_nl='Kattenkwaad', desc_fr=E'Les b\u00eatises qui nous font (un peu) rire : vols, objets d\u00e9truits, regards coupables.', desc_en='The mischief that makes us laugh (a little): thefts, destroyed objects, guilty looks.', desc_nl='Het kattenkwaad waar we (een beetje) om lachen: diefstal, vernielde spullen, schuldige blikken.' where slug='betises';
update public.community_tabs set label_fr=E'G\u00e9n\u00e9ral', label_en='General', label_nl='Algemeen', desc_fr='Conseils pour voyager avec ton chien, quelle que soit la destination.', desc_en='Tips for travelling with your dog, whatever the destination.', desc_nl='Tips om met je hond te reizen, wat de bestemming ook is.', flag=E'\U0001f30d' where slug='general';
update public.community_tabs set label_fr='Belgique', label_en='Belgium', label_nl=E'Belgi\u00eb', desc_fr='Bons plans et questions pour voyager en Belgique avec ton chien.', desc_en='Good tips and questions for travelling in Belgium with your dog.', desc_nl=E'Tips en vragen om met je hond in Belgi\u00eb te reizen.', flag=E'\U0001f1e7\U0001f1ea' where slug='BE';
update public.community_tabs set label_fr='France', label_en='France', label_nl='Frankrijk', desc_fr='Bons plans et questions pour voyager en France avec ton chien.', desc_en='Good tips and questions for travelling in France with your dog.', desc_nl='Tips en vragen om met je hond in Frankrijk te reizen.', flag=E'\U0001f1eb\U0001f1f7' where slug='FR';

-- 3. Remet les listes de mots correctes (elles n'ont pas encore pu etre modifiees)
delete from public.community_filter_terms;
insert into public.community_filter_terms (list, term) values
 ('insulte','vente'),
 ('insulte','connard'),
 ('insulte','connasse'),
 ('insulte','salope'),
 ('insulte','pute'),
 ('insulte',E'encul\u00e9'),
 ('insulte','ta gueule'),
 ('insulte','ferme-la'),
 ('insulte','abruti'),
 ('insulte','abrutie'),
 ('insulte',E'cr\u00e9tin'),
 ('insulte',E'cr\u00e9tine'),
 ('insulte',E'imb\u00e9cile'),
 ('insulte','bouffon'),
 ('insulte','merde'),
 ('insulte','pauvre type'),
 ('vente',E'\u00e0 vendre'),
 ('vente','je vends'),
 ('vente','je vend'),
 ('vente','chiots disponibles'),
 ('vente','chiot disponible'),
 ('vente',E'port\u00e9e'),
 ('vente',E'\u00e0 donner'),
 ('vente','je donne mon chien'),
 ('vente',E'\u00e0 placer'),
 ('vente','cherche famille'),
 ('vente','prix du chiot'),
 ('vente','vente de chiots')
on conflict do nothing;

-- 4. Photos : une par publication et par commentaire, uniquement dans Betises
alter table public.community_comments add column if not exists photo_path text;
alter table public.community_posts drop constraint if exists community_posts_body_check;
alter table public.community_posts add constraint community_posts_body_check
  check (char_length(body) <= 2000 and (char_length(btrim(body)) >= 1 or photo_path is not null or status = 'removed'));
alter table public.community_comments drop constraint if exists community_comments_body_check;
alter table public.community_comments add constraint community_comments_body_check
  check (char_length(body) <= 1000 and (char_length(btrim(body)) >= 1 or photo_path is not null or status = 'removed'));

-- Le dossier des photos : images uniquement, 300 Ko maximum (l'app les reduit avant l'envoi)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('community', 'community', true, 307200, array['image/webp','image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 307200, allowed_mime_types = array['image/webp','image/jpeg'];

drop policy if exists "communaute photos : voir"      on storage.objects;
drop policy if exists "communaute photos : ajouter"   on storage.objects;
drop policy if exists "communaute photos : supprimer" on storage.objects;
create policy "communaute photos : voir" on storage.objects for select to authenticated
  using (bucket_id = 'community' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy "communaute photos : ajouter" on storage.objects for insert to authenticated
  with check (bucket_id = 'community' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "communaute photos : supprimer" on storage.objects for delete to authenticated
  using (bucket_id = 'community' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- Verifie qu'une photo appartient bien a son auteur
create or replace function public.cm_check_photo(p text) returns void
language plpgsql stable set search_path = '' as $fn$
begin
  if p is not null and p !~ ('^' || auth.uid()::text || '/[a-z0-9-]+\.(webp|jpg)$') then raise exception 'swouf_photo'; end if;
end $fn$;

create or replace function public.community_posts_before() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare m public.community_members; why text[];
begin
  if tg_op = 'INSERT' then
    perform public.cm_guard('post');
    select * into m from public.community_members x where x.user_id = auth.uid();
    new.author_id := m.user_id; new.country := m.country; new.like_count := 0; new.comment_count := 0;
    new.created_at := now(); new.updated_at := now();
    if new.category = 'voyage' then
      if new.tab is null or not exists (select 1 from public.community_tabs t where t.slug = new.tab and t.active) then raise exception 'swouf_tab'; end if;
    else
      new.tab := null;
    end if;
    if new.photo_path is not null and new.category <> 'betises' then raise exception 'swouf_photo'; end if;
    perform public.cm_check_photo(new.photo_path);
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
end $fn$;

create or replace function public.community_comments_before() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare m public.community_members; why text[]; tab_country text; cat text;
begin
  if tg_op = 'INSERT' then
    perform public.cm_guard('comment');
    select * into m from public.community_members x where x.user_id = auth.uid();
    select p.category into cat from public.community_posts p where p.id = new.post_id and p.status = 'published';
    if cat is null then raise exception 'swouf_post'; end if;
    if new.photo_path is not null and cat <> 'betises' then raise exception 'swouf_photo'; end if;
    perform public.cm_check_photo(new.photo_path);
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
end $fn$;

-- Quand un texte disparait, sa photo part a la corbeille (videe depuis l'administration)
create table if not exists public.community_photo_trash (
  path       text primary key,
  created_at timestamptz not null default now()
);
alter table public.community_photo_trash enable row level security;
drop policy if exists "corbeille photos : gerer" on public.community_photo_trash;
create policy "corbeille photos : gerer" on public.community_photo_trash for all to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.community_photo_trash from anon, authenticated;
grant select, delete on public.community_photo_trash to authenticated;

create or replace function public.community_photo_gone() returns trigger
language plpgsql security definer set search_path = '' as $fn$
begin
  if old.photo_path is not null and (tg_op = 'DELETE' or new.photo_path is distinct from old.photo_path) then
    insert into public.community_photo_trash (path) values (old.photo_path) on conflict do nothing;
  end if;
  return null;
end $fn$;
drop trigger if exists community_posts_photo_gone on public.community_posts;
create trigger community_posts_photo_gone after delete or update of photo_path on public.community_posts
  for each row execute function public.community_photo_gone();
drop trigger if exists community_comments_photo_gone on public.community_comments;
create trigger community_comments_photo_gone after delete or update of photo_path on public.community_comments
  for each row execute function public.community_photo_gone();

-- Supprimer un texte retire aussi sa photo
create or replace function public.admin_moderate(p_type text, p_id uuid, p_action text) returns void
language plpgsql security definer set search_path = '' as $fn$
declare st text := case p_action when 'validate' then 'published' when 'remove' then 'removed' end;
begin
  if not public.is_admin() then raise exception 'admin'; end if;
  if st is null then raise exception 'action'; end if;
  if p_type = 'post' then
    update public.community_posts set status = st, photo_path = case when st = 'removed' then null else photo_path end where id = p_id;
  elsif p_type = 'comment' then
    update public.community_comments set status = st, photo_path = case when st = 'removed' then null else photo_path end where id = p_id;
  else raise exception 'type'; end if;
  if st = 'removed' then
    update public.community_reports set status = 'closed' where (p_type = 'post' and post_id = p_id) or (p_type = 'comment' and comment_id = p_id);
  end if;
end $fn$;

-- Droits : la photo peut etre envoyee et lue
grant insert (category, tab, body, photo_path) on public.community_posts to authenticated;
grant select (id, post_id, author_id, body_display, is_local, status, photo_path, created_at, updated_at) on public.community_comments to authenticated;
grant insert (post_id, body, photo_path) on public.community_comments to authenticated;
revoke all on function public.community_photo_gone(), public.cm_check_photo(text) from public, anon, authenticated;

-- 5. Remet a jour les textes deja publies avec les filtres corrects
update public.community_posts p set search_norm = public.cm_search(p.body_display);
update public.community_comments c set search_norm = public.cm_search(c.body_display);
update public.community_posts p set status = 'pending', pending_reasons = public.cm_reasons(p.body)
  where p.status = 'published' and cardinality(public.cm_reasons(p.body)) > 0;
update public.community_comments c set status = 'pending', pending_reasons = public.cm_reasons(c.body)
  where c.status = 'published' and cardinality(public.cm_reasons(c.body)) > 0;
