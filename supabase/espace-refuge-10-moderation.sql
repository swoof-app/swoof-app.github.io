-- ============================================================
-- SWOUF - Communaute : file de moderation et alerte du matin
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Peut etre relance sans risque : aucune donnee n'est supprimee.
-- ============================================================

-- 1. La file de moderation montre aussi les photos
create or replace function public.admin_community_queue() returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
begin
  if not public.is_admin() then raise exception 'admin'; end if;
  return jsonb_build_object(
    'posts', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select p.id, p.body, p.category, p.tab, p.photo_path, p.pending_reasons, p.created_at, p.author_id, m.display_name, m.country
       from public.community_posts p join public.community_members m on m.user_id = p.author_id where p.status = 'pending') x),
    'comments', (select coalesce(jsonb_agg(x order by x.created_at), '[]'::jsonb) from (
       select c.id, c.post_id, c.body, c.photo_path, c.pending_reasons, c.created_at, c.author_id, m.display_name, m.country
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

-- 2. Alerte : une notification le lendemain matin s'il y a quelque chose a verifier.
--    Elle utilise les rappels deja en place : rien de plus a payer. Une seule alerte en attente a la fois.
--    Si l'alerte echoue, la publication n'est jamais bloquee.
create or replace function public.cm_alert_admin() returns trigger
language plpgsql security definer set search_path = '' as $fn$
declare aid uuid;
begin
  begin
    select id into aid from auth.users where lower(email) = 'swouf.app@gmail.com';
    if aid is not null and not exists (select 1 from public.reminders r where r.user_id = aid and r.sent = false and r.url = './admin/') then
      insert into public.reminders (user_id, send_on, title, body, url)
      values (aid, current_date + 1, E'\U0001F43E Swouf', E'Des \u00e9l\u00e9ments de la communaut\u00e9 attendent ta v\u00e9rification.', './admin/');
    end if;
  exception when others then null;
  end;
  return null;
end $fn$;
revoke all on function public.cm_alert_admin() from public, anon, authenticated;

drop trigger if exists community_posts_alert on public.community_posts;
create trigger community_posts_alert after insert or update of status on public.community_posts
  for each row when (new.status = 'pending') execute function public.cm_alert_admin();
drop trigger if exists community_comments_alert on public.community_comments;
create trigger community_comments_alert after insert or update of status on public.community_comments
  for each row when (new.status = 'pending') execute function public.cm_alert_admin();
drop trigger if exists community_reports_alert on public.community_reports;
create trigger community_reports_alert after insert on public.community_reports
  for each row execute function public.cm_alert_admin();
