-- ============================================================
-- SWOUF - Communaute : remise a jour des textes quand une liste de noms change
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Peut etre relance sans risque : aucune donnee n'est supprimee.
-- ============================================================

-- Supabase refuse une mise a jour sans condition : on precise "tous les textes"
create or replace function public.community_remask() returns trigger
language plpgsql security definer set search_path = '' as $fn$
begin
  update public.community_posts p set body_display = public.cm_mask(p.body), search_norm = public.cm_search(public.cm_mask(p.body)) where p.id is not null;
  update public.community_comments c set body_display = public.cm_mask(c.body), search_norm = public.cm_search(public.cm_mask(c.body)) where c.id is not null;
  return null;
end $fn$;
revoke all on function public.community_remask() from public, anon, authenticated;
