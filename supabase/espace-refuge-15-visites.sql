-- ============================================================
-- SWOUF - Compteur de visites anonyme
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Aucun cout : reste dans le plan gratuit. Peut etre relance sans risque.
-- Une ligne par arrivee sur swouf.com : seulement la date et la source
-- (instagram, facebook ou autre). Aucune donnee personnelle : pas d'IP,
-- pas d'identifiant, pas de cookie.
-- Tout le monde peut seulement ajouter une ligne ; seule l'administratrice
-- (public.is_admin()) peut lire.
-- ============================================================

create table if not exists public.visites (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  source     text not null check (source in ('instagram', 'facebook', 'autre'))
);
create index if not exists visites_created_idx on public.visites (created_at desc);

alter table public.visites enable row level security;
drop policy if exists "visites : ajouter"      on public.visites;
drop policy if exists "visites : lire (admin)" on public.visites;
create policy "visites : ajouter"      on public.visites for insert to anon, authenticated with check (true);
create policy "visites : lire (admin)" on public.visites for select to authenticated using (public.is_admin());

-- Seule la source peut etre envoyee (la date est mise par Supabase, impossible a falsifier)
revoke all on public.visites from anon, authenticated;
grant insert (source) on public.visites to anon, authenticated;
grant select on public.visites to authenticated;

-- Chiffres du bloc "Visites" de l'onglet Statistiques (admin seulement)
-- Semaines du lundi au dimanche, heure de Bruxelles, 12 dernieres semaines.
create or replace function public.admin_visits() returns json
language plpgsql stable security definer set search_path = '' as $fn$
declare r json;
begin
  if not public.is_admin() then raise exception 'admin'; end if;
  select json_build_object(
    'total',     (select count(*) from public.visites),
    'last7',     (select count(*) from public.visites where created_at >= now() - interval '7 days'),
    'instagram', (select count(*) from public.visites where source = 'instagram'),
    'facebook',  (select count(*) from public.visites where source = 'facebook'),
    'autre',     (select count(*) from public.visites where source = 'autre'),
    'weeks', coalesce((
      select json_agg(w order by w.week desc) from (
        select date_trunc('week', created_at at time zone 'Europe/Brussels')::date as week,
               count(*) filter (where source = 'instagram') as instagram,
               count(*) filter (where source = 'facebook')  as facebook,
               count(*) filter (where source = 'autre')     as autre
        from public.visites
        where (created_at at time zone 'Europe/Brussels') >= date_trunc('week', now() at time zone 'Europe/Brussels') - interval '11 weeks'
        group by 1
      ) w), '[]'::json)
  ) into r;
  return r;
end $fn$;
revoke all on function public.admin_visits() from public, anon;
grant execute on function public.admin_visits() to authenticated;
