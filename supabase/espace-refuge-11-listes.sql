-- ============================================================
-- SWOUF - Communaute : correction de l'ajout dans les listes
-- A coller dans Supabase -> SQL Editor -> New query -> Run
-- Peut etre relance sans risque : aucune donnee n'est supprimee.
-- ============================================================

-- Le calcul de la forme sans accents d'un nom ou d'un mot s'execute avec les droits necessaires
alter function public.community_names_before() security definer;
alter function public.community_terms_before() security definer;

-- Essai sans risque : ajoute un nom en tant qu'administratrice, puis annule tout.
-- Si tout va bien, le resultat affiche une ligne avec le nom "essai liste".
begin;
select set_config('request.jwt.claims', (select json_build_object('sub', id, 'role', 'authenticated')::text from auth.users where lower(email) = 'swouf.app@gmail.com'), true);
set local role authenticated;
insert into public.community_names (kind, name) values ('blocked', 'essai liste') returning kind, name, norm_name;
rollback;
