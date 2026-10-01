create extension if not exists pgcrypto;

create table if not exists public.libraries (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique not null,
  edit_token_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  library_id uuid not null references public.libraries(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.libraries enable row level security;
alter table public.recipes enable row level security;

drop policy if exists "public can view libraries" on public.libraries;
create policy "public can view libraries" on public.libraries for select using (true);
drop policy if exists "public can view recipes" on public.recipes;
create policy "public can view recipes" on public.recipes for select using (true);

create or replace function public.create_library(p_name text, p_slug text, p_edit_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if exists(select 1 from public.libraries) then raise exception 'Library already created'; end if;
  if length(p_edit_token) < 24 then raise exception 'Editing key is too short'; end if;
  insert into public.libraries(name,slug,edit_token_hash)
  values(p_name,p_slug,encode(digest(p_edit_token,'sha256'),'hex')) returning id into new_id;
  return new_id;
end; $$;

create or replace function public.save_recipe(p_slug text, p_edit_token text, p_id uuid, p_data jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare lib_id uuid; saved_id uuid;
begin
  select id into lib_id from public.libraries where slug=p_slug and edit_token_hash=encode(digest(p_edit_token,'sha256'),'hex');
  if lib_id is null then raise exception 'Invalid editing link'; end if;
  if p_id is null then
    insert into public.recipes(library_id,data) values(lib_id,p_data) returning id into saved_id;
  else
    update public.recipes set data=p_data,updated_at=now() where id=p_id and library_id=lib_id returning id into saved_id;
    if saved_id is null then raise exception 'Recipe not found'; end if;
  end if;
  return saved_id;
end; $$;

create or replace function public.delete_recipe(p_slug text, p_edit_token text, p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare lib_id uuid;
begin
  select id into lib_id from public.libraries where slug=p_slug and edit_token_hash=encode(digest(p_edit_token,'sha256'),'hex');
  if lib_id is null then raise exception 'Invalid editing link'; end if;
  delete from public.recipes where id=p_id and library_id=lib_id;
  return found;
end; $$;

grant execute on function public.create_library(text,text,text) to anon;
grant execute on function public.save_recipe(text,text,uuid,jsonb) to anon;
grant execute on function public.delete_recipe(text,text,uuid) to anon;
grant select on public.libraries, public.recipes to anon;

