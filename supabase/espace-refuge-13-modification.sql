-- ============================================================
-- SWOUF - Communaute : modifier ses propres publications et commentaires
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Peut etre relance sans risque : aucune donnee n'est supprimee.
-- ============================================================

-- 1. Date de modification et ancien texte (visible seulement par l'administration)
alter table public.community_posts    add column if not exists edited_at timestamptz;
alter table public.community_posts    add column if not exists previous_body text;
alter table public.community_comments add column if not exists edited_at timestamptz;
alter table public.community_comments add column if not exists previous_body text;

-- 2. Limite anti-spam des modifications : 10 par heure
create table if not exists public.community_edits (
  user_id    uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists community_edits_idx on public.community_edits (user_id, created_at desc);
alter table public.community_edits enable row level security;
revoke all on public.community_edits from anon, authenticated;

create or replace function public.cm_guard(what text) returns void
language plpgsql stable security definer set search_path = '' as $fn$
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
  elsif what = 'edit' then
    select count(*) into n from public.community_edits e where e.user_id = uid and e.created_at > now() - interval '1 hour';
    if n >= 10 then raise exception 'swouf_rate_limit'; end if;
  end if;
end $fn$;

-- 3. Une modification repasse dans les memes filtres qu'une nouvelle publication
create or replace function public.community_posts_before() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare m public.community_members; why text[];
begin
  if tg_op = 'INSERT' then
    perform public.cm_guard('post');
    select * into m from public.community_members x where x.user_id = auth.uid();
    new.author_id := m.user_id; new.country := m.country; new.like_count := 0; new.comment_count := 0;
    new.created_at := now(); new.updated_at := now(); new.edited_at := null; new.previous_body := null;
    if new.category = 'voyage' then
      if new.tab is null or not exists (select 1 from public.community_tabs t where t.slug = new.tab and t.active) then raise exception 'swouf_tab'; end if;
    else
      new.tab := null;
    end if;
    if new.photo_path is not null and new.category <> 'betises' then raise exception 'swouf_photo'; end if;
    perform public.cm_check_photo(new.photo_path);
  elsif new.body is not distinct from old.body and new.tab is not distinct from old.tab then
    return new;   -- validation par l'administration, compteurs ou noms masques
  else
    perform public.cm_guard('edit');
    insert into public.community_edits (user_id) values (auth.uid());
    delete from public.community_edits e where e.user_id = auth.uid() and e.created_at < now() - interval '1 day';
    if new.category = 'voyage' then
      if new.tab is null or not exists (select 1 from public.community_tabs t where t.slug = new.tab and t.active) then raise exception 'swouf_tab'; end if;
    else
      new.tab := old.tab;
    end if;
    new.updated_at := now(); new.edited_at := now();
    if new.body is distinct from old.body then new.previous_body := old.body; end if;
  end if;
  why := public.cm_reasons(new.body);
  new.body_display := public.cm_mask(new.body);
  new.search_norm := public.cm_search(new.body_display);
  if tg_op = 'UPDATE' and new.body is not distinct from old.body then
    new.status := old.status;  -- seul l'onglet a change
    return new;
  end if;
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
    new.created_at := now(); new.updated_at := now(); new.edited_at := null; new.previous_body := null;
  elsif new.body is not distinct from old.body then
    return new;
  else
    perform public.cm_guard('edit');
    insert into public.community_edits (user_id) values (auth.uid());
    delete from public.community_edits e where e.user_id = auth.uid() and e.created_at < now() - interval '1 day';
    new.updated_at := now(); new.edited_at := now(); new.previous_body := old.body;
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

-- 4. Retrouver son propre texte pour le modifier (jamais celui des autres)
create or replace function public.community_my_text(p_type text, p_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $fn$
declare t text;
begin
  if p_type = 'post' then select p.body into t from public.community_posts p where p.id = p_id and p.author_id = auth.uid();
  elsif p_type = 'comment' then select c.body into t from public.community_comments c where c.id = p_id and c.author_id = auth.uid();
  end if;
  return t;
end $fn$;
revoke all on function public.community_my_text(text, uuid) from public, anon;
grant execute on function public.community_my_text(text, uuid) to authenticated;

-- 5. Droits : l'auteur change seulement son texte (et l'onglet de Voyage), jamais le statut, les likes ou les dates
grant select (edited_at) on public.community_posts to authenticated;
grant select (edited_at) on public.community_comments to authenticated;
grant update (body, tab) on public.community_posts to authenticated;

-- 6. Le compteur de commentaires et l'alerte suivent aussi les textes qui repassent en attente
drop trigger if exists community_comments_count on public.community_comments;
drop trigger if exists community_comments_count_upd on public.community_comments;
create trigger community_comments_count after insert or delete on public.community_comments
  for each row execute function public.community_count_comments();
create trigger community_comments_count_upd after update on public.community_comments
  for each row when (old.status is distinct from new.status) execute function public.community_count_comments();

drop trigger if exists community_posts_alert on public.community_posts;
drop trigger if exists community_posts_alert_upd on public.community_posts;
create trigger community_posts_alert after insert on public.community_posts
  for each row when (new.status = 'pending') execute function public.cm_alert_admin();
create trigger community_posts_alert_upd after update on public.community_posts
  for each row when (new.status = 'pending' and old.status is distinct from new.status) execute function public.cm_alert_admin();
drop trigger if exists community_comments_alert on public.community_comments;
drop trigger if exists community_comments_alert_upd on public.community_comments;
create trigger community_comments_alert after insert on public.community_comments
  for each row when (new.status = 'pending') execute function public.cm_alert_admin();
create trigger community_comments_alert_upd after update on public.community_comments
  for each row when (new.status = 'pending' and old.status is distinct from new.status) execute function public.cm_alert_admin();

-- 7. La file de moderation montre l'ancien et le nouveau texte
create or replace function public.admin_community_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.is_admin() then raise exception 'admin'; end if;
  return jsonb_build_object(
    'posts', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select p.id, p.body, p.previous_body, p.edited_at, p.category, p.tab, p.photo_path, p.pending_reasons, p.created_at, p.author_id, m.display_name, m.country
       from public.community_posts p join public.community_members m on m.user_id = p.author_id where p.status = 'pending') x),
    'comments', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select c.id, c.post_id, c.body, c.previous_body, c.edited_at, c.photo_path, c.pending_reasons, c.created_at, c.author_id, m.display_name, m.country
       from public.community_comments c join public.community_members m on m.user_id = c.author_id where c.status = 'pending') x),
    'reports', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select r.id, r.target_type, r.reason, r.note, r.created_at, r.post_id, r.comment_id, r.target_user_id, m.display_name,
              case r.target_type when 'post' then p.body when 'comment' then c.body end as text,
              case r.target_type when 'post' then p.photo_path when 'comment' then c.photo_path end as photo_path,
              s.warnings, s.suspended_until, s.banned_at
       from public.community_reports r
       left join public.community_members m on m.user_id = r.target_user_id
       left join public.community_posts p on p.id = r.post_id
       left join public.community_comments c on c.id = r.comment_id
       left join public.community_sanctions s on s.user_id = r.target_user_id
       where r.status = 'open') x),
    'suggestions', (select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) from (
       select g.id, g.note, g.created_at, n.name from public.community_suggestions g
       left join public.community_names n on n.id = g.name_id where not g.handled) x),
    'sanctions', (select coalesce(jsonb_agg(x order by x.updated_at desc), '[]'::jsonb) from (
       select s.user_id, s.warnings, s.suspended_until, s.banned_at, s.last_reason, s.updated_at, m.display_name
       from public.community_sanctions s join public.community_members m on m.user_id = s.user_id
       where s.warnings > 0 or s.banned_at is not null or s.suspended_until > now()) x)
  );
end $fn$;
