-- Swouf – mise à jour 18 : demandes d'ebooks gratuits
-- À coller dans Supabase > SQL Editor > Run (aucun coût : reste dans le plan gratuit)
-- Chaque fois qu'une personne laisse son e-mail pour lire un ebook gratuit, une ligne est ajoutée ici.
-- Seule l'administratrice (swouf.app@gmail.com, via public.is_admin()) peut lire, modifier ou supprimer ces lignes.

create table if not exists public.ebook_requests (
  id         uuid primary key default gen_random_uuid(),
  ebook      text not null check (char_length(ebook) <= 60),          -- ex. 'adopter-refuge'
  email      text not null check (char_length(email) <= 254),
  first_name text check (char_length(first_name) <= 80),
  lang       text check (char_length(lang) <= 5),
  newsletter boolean not null default false,                          -- a coché « recevoir les nouvelles de Swouf »
  created_at timestamptz not null default now()
);
create index if not exists ebook_requests_created_idx on public.ebook_requests (created_at desc);

alter table public.ebook_requests enable row level security;
drop policy if exists "ebooks : demander"      on public.ebook_requests;
drop policy if exists "ebooks : gérer (admin)" on public.ebook_requests;
create policy "ebooks : demander"      on public.ebook_requests for insert to anon, authenticated with check (true);
create policy "ebooks : gérer (admin)" on public.ebook_requests for all to authenticated using (public.is_admin()) with check (public.is_admin());

revoke all on public.ebook_requests from anon, authenticated;
grant insert (ebook, email, first_name, lang, newsletter) on public.ebook_requests to anon, authenticated;
grant select, update, delete on public.ebook_requests to authenticated;
