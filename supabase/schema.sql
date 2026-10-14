-- Run this once in Supabase: SQL Editor > New query > Run

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role text not null default 'hospital' check (role in ('hospital','admin')),
  hospital_name text, email text, address text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz default now()
);

create table blood_stock (blood_group text primary key, units int not null default 0);
insert into blood_stock(blood_group) values ('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('O+'),('O-');

create table donors (
  id uuid primary key default gen_random_uuid(),
  name text not null, age int not null check (age between 18 and 65),
  gender text, blood_group text not null references blood_stock, mobile text not null, address text not null,
  created_at timestamptz default now()
);

create table requests (
  id uuid primary key default gen_random_uuid(),
  name text not null, age int, gender text,
  blood_group text not null references blood_stock, mobile text not null, address text not null,
  needed_by timestamptz not null,
  is_emergency boolean not null default false,
  created_at timestamptz default now()
);

create table camps (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references profiles on delete cascade,
  hospital_name text not null, camp_date date not null, camp_time text not null, address text not null,
  created_at timestamptz default now()
);

-- helpers
create function is_admin() returns boolean language sql security definer stable set search_path = public as
$$ select exists(select 1 from profiles where id = auth.uid() and role = 'admin') $$;

create function is_hospital() returns boolean language sql security definer stable set search_path = public as
$$ select exists(select 1 from profiles where id = auth.uid() and status = 'approved' and role in ('hospital','admin')) $$;

-- new auth user -> hospital profile
create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id,email,hospital_name,address)
  values (new.id,new.email,new.raw_user_meta_data->>'hospital_name',new.raw_user_meta_data->>'address')
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_signup after insert on auth.users for each row execute function handle_new_user();

-- each donor adds one unit to their blood group
create function add_unit() returns trigger language plpgsql security definer set search_path = public as $$
begin update blood_stock set units = units + 1 where blood_group = new.blood_group; return new; end $$;
create trigger on_donor after insert on donors for each row execute function add_unit();

-- request deadline under 24h => emergency
create function flag_emergency() returns trigger language plpgsql as $$
begin new.is_emergency := new.needed_by <= now() + interval '24 hours'; return new; end $$;
create trigger on_request before insert on requests for each row execute function flag_emergency();

-- public read-only data (donor/patient details stay private)
create function get_stats() returns json language sql security definer stable set search_path = public as
$$ select json_build_object('donors', (select count(*) from donors)) $$;

create view emergency_public as
  select id, name, blood_group, address, mobile, needed_by
  from requests where is_emergency and needed_by > now();

grant select on emergency_public to anon, authenticated;
grant execute on function get_stats() to anon, authenticated;

-- row level security
alter table profiles enable row level security;
alter table blood_stock enable row level security;
alter table donors enable row level security;
alter table requests enable row level security;
alter table camps enable row level security;

create policy "own profile or admin" on profiles for select using (id = auth.uid() or is_admin());
create policy "admin deletes profiles" on profiles for delete using (is_admin());
create policy "admin approves hospitals" on profiles for update using (is_admin()) with check (is_admin());

create policy "anyone sees stock" on blood_stock for select using (true);
create policy "admin edits stock" on blood_stock for update using (is_admin());

create policy "anyone registers as donor" on donors for insert to anon, authenticated with check (true);
create policy "admin reads donors" on donors for select using (is_admin());
create policy "admin deletes donors" on donors for delete using (is_admin());

create policy "anyone requests blood" on requests for insert to anon, authenticated with check (true);
create policy "hospitals read requests" on requests for select using (is_hospital());
create policy "admin deletes requests" on requests for delete using (is_admin());

create policy "anyone sees camps" on camps for select using (true);
create policy "hospital posts own camp" on camps for insert to authenticated
  with check (hospital_id = auth.uid() and exists(select 1 from profiles where id = auth.uid() and role = 'hospital' and status = 'approved'));
create policy "hospital deletes own camp" on camps for delete using (hospital_id = auth.uid() or is_admin());

-- admin deletes a hospital completely: login account, profile and camps (so it can never get emails again)
create or replace function public.admin_delete_hospital(hid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Admins only'; end if;
  if exists (select 1 from public.profiles where id = hid and role = 'admin') then raise exception 'An admin cannot be deleted'; end if;
  delete from auth.users where id = hid;  -- profile and camps are removed by cascade
end $$;
revoke all on function public.admin_delete_hospital(uuid) from public, anon;
grant execute on function public.admin_delete_hospital(uuid) to authenticated;

-- AFTER running this file: create the admin user in Authentication > Users (tick Auto Confirm User), then run:
-- update public.profiles set role = 'admin', status = 'approved', hospital_name = 'Admin' where email = 'YOUR_ADMIN_EMAIL';
