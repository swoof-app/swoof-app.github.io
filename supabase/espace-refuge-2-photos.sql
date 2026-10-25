-- ============================================================
-- SWOUF – Espace refuge, étape 3 : dossier des photos et logos
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- 1. Le dossier « refuges » : photos visibles par tous (pour l'app), 500 Ko maximum par fichier, images uniquement
--    Rangement : refuges/<identifiant du refuge>/logo.webp et refuges/<identifiant du refuge>/<identifiant du chien>.webp
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('refuges', 'refuges', true, 512000, array['image/webp','image/jpeg','image/png'])
on conflict (id) do update set public = true, file_size_limit = 512000, allowed_mime_types = array['image/webp','image/jpeg','image/png'];

-- 2. Qui peut gérer les fichiers d'un sous-dossier : l'équipe de ce refuge, ou l'administratrice
create or replace function public.can_manage_shelter_folder(folder text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  return public.is_admin() or public.is_member(folder::uuid);
exception when invalid_text_representation then
  return false;  -- nom de sous-dossier qui n'est pas un refuge
end $$;

-- 3. Règles du dossier (la lecture des photos par l'app passe par le lien public, sans règle)
drop policy if exists "photos refuge : voir les siennes"  on storage.objects;
drop policy if exists "photos refuge : ajouter"           on storage.objects;
drop policy if exists "photos refuge : remplacer"         on storage.objects;
drop policy if exists "photos refuge : supprimer"         on storage.objects;
create policy "photos refuge : voir les siennes" on storage.objects for select to authenticated
  using (bucket_id = 'refuges' and public.can_manage_shelter_folder((storage.foldername(name))[1]));
create policy "photos refuge : ajouter" on storage.objects for insert to authenticated
  with check (bucket_id = 'refuges' and public.can_manage_shelter_folder((storage.foldername(name))[1]));
create policy "photos refuge : remplacer" on storage.objects for update to authenticated
  using (bucket_id = 'refuges' and public.can_manage_shelter_folder((storage.foldername(name))[1]))
  with check (bucket_id = 'refuges' and public.can_manage_shelter_folder((storage.foldername(name))[1]));
create policy "photos refuge : supprimer" on storage.objects for delete to authenticated
  using (bucket_id = 'refuges' and public.can_manage_shelter_folder((storage.foldername(name))[1]));
