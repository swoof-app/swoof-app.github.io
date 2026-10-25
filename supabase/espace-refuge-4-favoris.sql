-- ============================================================
-- SWOUF – Espace refuge, étape 6 : favoris des utilisateurs de l'app
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- Le cœur sur la fiche d'un chien de refuge (uniquement pour les personnes connectées).
-- Quand le chien est adopté (fiche supprimée), ses favoris disparaissent avec lui.
create table if not exists public.shelter_dog_favorites (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  dog_id     uuid not null references public.shelter_dogs(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, dog_id)
);
create index if not exists shelter_dog_favorites_dog_idx on public.shelter_dog_favorites(dog_id);

-- Chacun ne voit et ne gère que ses propres favoris (les refuges ne les voient pas)
alter table public.shelter_dog_favorites enable row level security;
drop policy if exists "favoris : lire les siens"     on public.shelter_dog_favorites;
drop policy if exists "favoris : ajouter"            on public.shelter_dog_favorites;
drop policy if exists "favoris : retirer les siens"  on public.shelter_dog_favorites;
create policy "favoris : lire les siens"    on public.shelter_dog_favorites for select using (auth.uid() = user_id);
create policy "favoris : ajouter"           on public.shelter_dog_favorites for insert with check (auth.uid() = user_id);
create policy "favoris : retirer les siens" on public.shelter_dog_favorites for delete using (auth.uid() = user_id);

revoke all on public.shelter_dog_favorites from anon;
grant select, insert, delete on public.shelter_dog_favorites to authenticated;
