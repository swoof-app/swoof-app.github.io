-- ============================================================
-- SWOUF – Avis et propositions de l'app, visibles dans l'administration
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- Un avis après le test (note + commentaire), une proposition (profil) ou un vétérinaire à ajouter.
-- Anonyme : ni nom, ni e-mail, ni compte.
create table if not exists public.app_feedback (
  id         uuid primary key default gen_random_uuid(),
  kind       text not null check (kind in ('avis','proposition','veterinaire')),
  rating     smallint check (rating between 1 and 5),
  message    text check (char_length(message) <= 2000),
  breeds     text check (char_length(breeds) <= 300),   -- races obtenues au test (pour les avis)
  lang       text check (char_length(lang) <= 5),
  handled    boolean not null default false,             -- « traité » dans l'administration
  created_at timestamptz not null default now()
);
create index if not exists app_feedback_created_idx on public.app_feedback(created_at desc);

-- Tout le monde peut envoyer un avis (même sans compte) ; seule l'administratrice peut les lire, les marquer et les supprimer
alter table public.app_feedback enable row level security;
drop policy if exists "avis : envoyer"          on public.app_feedback;
drop policy if exists "avis : lire (admin)"     on public.app_feedback;
drop policy if exists "avis : marquer (admin)"  on public.app_feedback;
drop policy if exists "avis : supprimer (admin)" on public.app_feedback;
create policy "avis : envoyer"           on public.app_feedback for insert to anon, authenticated with check (handled = false);
create policy "avis : lire (admin)"      on public.app_feedback for select to authenticated using (public.is_admin());
create policy "avis : marquer (admin)"   on public.app_feedback for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "avis : supprimer (admin)" on public.app_feedback for delete to authenticated using (public.is_admin());

revoke all on public.app_feedback from anon, authenticated;
grant insert on public.app_feedback to anon, authenticated;
grant select, update, delete on public.app_feedback to authenticated;
