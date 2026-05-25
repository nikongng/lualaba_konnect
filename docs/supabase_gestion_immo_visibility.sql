-- Gestion Immo visibility rules:
-- - houses published by a commissionnaire are public
-- - houses published by a proprietaire stay visible only to their creator
-- - tenants stay private to the creator/owner account

alter table public.gestion_immo_houses
  add column if not exists owner_id uuid default auth.uid();

alter table public.gestion_immo_tenants
  add column if not exists owner_id uuid default auth.uid();

alter table public.gestion_immo_houses
  alter column owner_id set default auth.uid();

alter table public.gestion_immo_tenants
  alter column owner_id set default auth.uid();

alter table public.gestion_immo_houses enable row level security;
alter table public.gestion_immo_tenants enable row level security;

drop policy if exists "gestion_immo_houses_read_public_commissioner_or_own"
  on public.gestion_immo_houses;
create policy "gestion_immo_houses_read_public_commissioner_or_own"
on public.gestion_immo_houses
for select
to anon, authenticated
using (
  coalesce(from_commissioner, false)
  or owner_id = auth.uid()
);

drop policy if exists "gestion_immo_houses_insert_own"
  on public.gestion_immo_houses;
create policy "gestion_immo_houses_insert_own"
on public.gestion_immo_houses
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "gestion_immo_houses_update_own"
  on public.gestion_immo_houses;
create policy "gestion_immo_houses_update_own"
on public.gestion_immo_houses
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "gestion_immo_houses_delete_own"
  on public.gestion_immo_houses;
create policy "gestion_immo_houses_delete_own"
on public.gestion_immo_houses
for delete
to authenticated
using (owner_id = auth.uid());

drop policy if exists "gestion_immo_tenants_select_own"
  on public.gestion_immo_tenants;
create policy "gestion_immo_tenants_select_own"
on public.gestion_immo_tenants
for select
to authenticated
using (owner_id = auth.uid());

drop policy if exists "gestion_immo_tenants_insert_own"
  on public.gestion_immo_tenants;
create policy "gestion_immo_tenants_insert_own"
on public.gestion_immo_tenants
for insert
to authenticated
with check (owner_id = auth.uid());

drop policy if exists "gestion_immo_tenants_update_own"
  on public.gestion_immo_tenants;
create policy "gestion_immo_tenants_update_own"
on public.gestion_immo_tenants
for update
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "gestion_immo_tenants_delete_own"
  on public.gestion_immo_tenants;
create policy "gestion_immo_tenants_delete_own"
on public.gestion_immo_tenants
for delete
to authenticated
using (owner_id = auth.uid());
