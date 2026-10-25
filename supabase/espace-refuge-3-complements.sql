-- ============================================================
-- SWOUF – Espace refuge, compléments
-- À coller dans Supabase → SQL Editor → New query → Run
-- Peut être relancé sans risque : rien n'est supprimé.
-- ============================================================

-- 1. Un refuge qui a demandé la suppression de son compte (RGPD) disparaît tout de suite de l'app
create or replace function public.public_shelter_dogs(include_test boolean default false)
returns table (
  dog_id uuid, name text, birth_date date, age_estimated boolean, sex text, breed text,
  sterilized boolean, chipped boolean, vaccinated boolean, adoption_fee numeric,
  criteria jsonb, special_needs text, story text, photo_path text, updated_at timestamptz,
  shelter_id uuid, shelter_name text, shelter_postal_code text, shelter_city text, shelter_country text,
  shelter_phone text, shelter_website text, shelter_logo_path text
)
language sql stable security definer set search_path = '' as $$
  select d.id, d.name, d.birth_date, d.age_estimated, d.sex, d.breed,
         d.sterilized, d.chipped, d.vaccinated, d.adoption_fee,
         d.criteria, d.special_needs, d.story, d.photo_path, d.updated_at,
         s.id, s.name, s.postal_code, s.city, s.country, s.phone, s.website, s.logo_path
  from public.shelter_dogs d
  join public.shelters s on s.id = d.shelter_id
  where s.status = 'actif' and s.deletion_requested_at is null
    and d.published and not d.hidden_by_admin
    and ((not s.is_test and not d.is_test) or (include_test and public.is_admin()))
$$;
revoke all on function public.public_shelter_dogs(boolean) from public;
grant execute on function public.public_shelter_dogs(boolean) to anon, authenticated;

-- 2. … et ne peut plus rien publier ni modifier
create or replace function public.shelter_is_active(sid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.shelters s where s.id = sid and s.status = 'actif' and s.deletion_requested_at is null)
$$;
