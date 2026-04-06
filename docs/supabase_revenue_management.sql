create extension if not exists pgcrypto;

create table if not exists public.revenue_admins (
  id text primary key,
  nom text not null,
  role text not null,
  login text not null unique,
  mot_de_passe text not null,
  is_super_admin boolean not null default false,
  created_by_admin_id text,
  local_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.revenue_agents (
  id text primary key,
  nom text not null,
  genre text not null default 'Masculin',
  telephone text not null,
  commune text not null,
  identifiant_unique text not null unique,
  mot_de_passe text not null,
  photo text,
  photo_url text,
  actif boolean not null default true,
  local_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.revenue_transactions (
  id text primary key,
  numero_transaction text not null unique,
  montant double precision not null default 0,
  type text not null,
  contribuable text not null,
  date timestamptz not null default now(),
  agent_id text not null,
  agent_nom text not null,
  commune text not null,
  statut text not null default 'EN_ATTENTE',
  commentaire text not null default '',
  local_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_revenue_admins_updated_at on public.revenue_admins;
create trigger trg_revenue_admins_updated_at
before update on public.revenue_admins
for each row execute function public.set_updated_at();

drop trigger if exists trg_revenue_agents_updated_at on public.revenue_agents;
create trigger trg_revenue_agents_updated_at
before update on public.revenue_agents
for each row execute function public.set_updated_at();

drop trigger if exists trg_revenue_transactions_updated_at on public.revenue_transactions;
create trigger trg_revenue_transactions_updated_at
before update on public.revenue_transactions
for each row execute function public.set_updated_at();

alter table public.revenue_admins enable row level security;
alter table public.revenue_agents enable row level security;
alter table public.revenue_transactions enable row level security;

drop policy if exists "revenue_admins_all" on public.revenue_admins;
create policy "revenue_admins_all"
on public.revenue_admins
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "revenue_agents_all" on public.revenue_agents;
create policy "revenue_agents_all"
on public.revenue_agents
for all
to anon, authenticated
using (true)
with check (true);

drop policy if exists "revenue_transactions_all" on public.revenue_transactions;
create policy "revenue_transactions_all"
on public.revenue_transactions
for all
to anon, authenticated
using (true)
with check (true);

insert into public.revenue_admins (
  id,
  nom,
  role,
  login,
  mot_de_passe,
  is_super_admin,
  local_only
)
values (
  'ADM-00001',
  'Super administrateur',
  'SUPER_ADMIN',
  'admin',
  'admin123',
  true,
  false
)
on conflict (id) do update
set
  nom = excluded.nom,
  role = excluded.role,
  login = excluded.login,
  mot_de_passe = excluded.mot_de_passe,
  is_super_admin = excluded.is_super_admin,
  local_only = excluded.local_only,
  updated_at = now();

-- Bucket conseille pour les photos d'agents:
-- reutilise le bucket existant "profiles"
-- et autorise l'upload anonyme/authentifie selon la politique deja en place.
