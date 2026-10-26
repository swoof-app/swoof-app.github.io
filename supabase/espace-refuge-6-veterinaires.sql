-- ============================================================
-- SWOUF – Vétérinaires proposés par les utilisateurs, approuvés dans l'administration
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- 1. Une proposition de vétérinaire garde chaque information séparément (nom, adresse, code postal…)
alter table public.app_feedback add column if not exists details jsonb
  check (details is null or (jsonb_typeof(details) = 'object' and length(details::text) <= 2000));

-- 2. Les vétérinaires ajoutés à l'app (en plus de la liste intégrée à l'app)
create table if not exists public.vets_added (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 2 and 150),
  address     text not null check (char_length(address) <= 200),   -- rue et numéro
  postal_code text not null check (postal_code ~ '^[0-9]{4}$'),     -- sert à placer le vétérinaire sur la carte
  city        text not null check (char_length(city) <= 80),
  phone       text check (char_length(phone) <= 40),
  website     text check (char_length(website) <= 300),
  hidden      boolean not null default false,                      -- masqué de l'app
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists vets_added_touch on public.vets_added;
create trigger vets_added_touch before update on public.vets_added for each row execute function public.touch_updated_at();

-- 3. Tout le monde voit les vétérinaires visibles ; seule l'administratrice ajoute, modifie, masque et supprime
alter table public.vets_added enable row level security;
drop policy if exists "vétérinaires : lire les visibles" on public.vets_added;
drop policy if exists "vétérinaires : ajouter (admin)"   on public.vets_added;
drop policy if exists "vétérinaires : modifier (admin)"  on public.vets_added;
drop policy if exists "vétérinaires : supprimer (admin)" on public.vets_added;
create policy "vétérinaires : lire les visibles" on public.vets_added for select using (not hidden or public.is_admin());
create policy "vétérinaires : ajouter (admin)"   on public.vets_added for insert to authenticated with check (public.is_admin());
create policy "vétérinaires : modifier (admin)"  on public.vets_added for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "vétérinaires : supprimer (admin)" on public.vets_added for delete to authenticated using (public.is_admin());

revoke all on public.vets_added from anon, authenticated;
grant select on public.vets_added to anon, authenticated;
grant insert, update, delete on public.vets_added to authenticated;
