-- AGRI-KARTA initial schema for Mid-Mile logistics orchestration.

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

create type user_role as enum ('pengepul', 'super_admin', 'b2b_buyer');
create type level_status as enum ('none', 'amatir', 'junior', 'senior');
create type pengiriman_status as enum ('on_the_way', 'completed', 'cancelled');

create table if not exists profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role user_role not null default 'pengepul',
  no_hp text not null unique,
  virtual_email text unique,
  pin_hash text not null,
  latitude double precision not null,
  longitude double precision not null,
  zona smallint not null default 4 check (zona between 1 and 4),
  level_gamifikasi level_status not null default 'none',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists bahan_baku (
  id bigserial primary key,
  nama_komoditas text not null unique,
  total_stok_gudang numeric(14, 2) not null default 0 check (total_stok_gudang >= 0),
  harga_dasar numeric(14, 2) not null check (harga_dasar >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists factory_center (
  id smallint primary key default 1 check (id = 1),
  latitude double precision not null,
  longitude double precision not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into factory_center (id, latitude, longitude)
values (1, -6.2088, 106.8456)
on conflict (id) do nothing;

create table if not exists zona_sla (
  zona smallint primary key check (zona between 1 and 4),
  tenggat_jam smallint not null check (tenggat_jam > 0)
);

insert into zona_sla (zona, tenggat_jam)
values
  (1, 2),
  (2, 4),
  (3, 6),
  (4, 6)
on conflict (zona) do nothing;

create table if not exists pengiriman (
  id bigserial primary key,
  pengepul_id uuid not null references profiles (id) on delete restrict,
  bahan_baku_id bigint not null references bahan_baku (id) on delete restrict,
  status pengiriman_status not null default 'on_the_way',
  tenggat_waktu_kirim timestamptz,
  is_extended boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists sanksi_booking (
  id bigserial primary key,
  pengiriman_id bigint not null references pengiriman (id) on delete cascade,
  pengepul_id uuid not null references profiles (id) on delete cascade,
  reason text not null default 'Overdue shipment auto-cancelled',
  berlaku_sampai timestamptz not null,
  created_at timestamptz not null default now(),
  unique (pengiriman_id, pengepul_id, reason)
);

create table if not exists pembelian_b2b (
  id bigserial primary key,
  b2b_buyer_id uuid not null references profiles (id) on delete restrict,
  bahan_baku_id bigint not null references bahan_baku (id) on delete restrict,
  jumlah numeric(14, 2) not null check (jumlah > 0),
  harga_satuan numeric(14, 2) not null check (harga_satuan >= 0),
  total_harga numeric(14, 2) generated always as (jumlah * harga_satuan) stored,
  created_at timestamptz not null default now()
);

create or replace function haversine_distance_km(
  lat1 double precision,
  lon1 double precision,
  lat2 double precision,
  lon2 double precision
)
returns double precision
language plpgsql
immutable
strict
as $$
declare
  earth_radius_km constant double precision := 6371;
  d_lat double precision;
  d_lon double precision;
  a double precision;
  c double precision;
begin
  d_lat := radians(lat2 - lat1);
  d_lon := radians(lon2 - lon1);

  a := sin(d_lat / 2) * sin(d_lat / 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * sin(d_lon / 2) * sin(d_lon / 2);

  c := 2 * atan2(sqrt(a), sqrt(1 - a));

  return earth_radius_km * c;
end;
$$;

create or replace function calculate_user_zona(
  user_lat double precision,
  user_lon double precision,
  factory_lat double precision,
  factory_lon double precision
)
returns smallint
language plpgsql
immutable
strict
as $$
declare
  distance_km double precision;
begin
  distance_km := haversine_distance_km(user_lat, user_lon, factory_lat, factory_lon);

  if distance_km <= 10 then
    return 1;
  elsif distance_km <= 25 then
    return 2;
  elsif distance_km <= 50 then
    return 3;
  end if;

  return 4;
end;
$$;

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function set_profiles_zona()
returns trigger
language plpgsql
as $$
declare
  center_lat double precision;
  center_lon double precision;
begin
  select fc.latitude, fc.longitude
  into center_lat, center_lon
  from factory_center fc
  where fc.id = 1;

  if center_lat is null or center_lon is null then
    raise exception 'Factory center coordinate not configured';
  end if;

  new.zona := calculate_user_zona(new.latitude, new.longitude, center_lat, center_lon);
  return new;
end;
$$;

create or replace function set_pengiriman_tenggat_waktu()
returns trigger
language plpgsql
as $$
declare
  assigned_zona smallint;
  deadline_hours smallint;
begin
  select p.zona into assigned_zona
  from profiles p
  where p.id = new.pengepul_id;

  if assigned_zona is null then
    raise exception 'Pengepul profile % not found or missing zona', new.pengepul_id;
  end if;

  select zs.tenggat_jam into deadline_hours
  from zona_sla zs
  where zs.zona = assigned_zona;

  if deadline_hours is null then
    raise exception 'No SLA deadline configured for zona %', assigned_zona;
  end if;

  new.tenggat_waktu_kirim := now() + make_interval(hours => deadline_hours);

  return new;
end;
$$;

create trigger trg_profiles_set_zona
before insert or update of latitude, longitude on profiles
for each row
execute function set_profiles_zona();

create trigger trg_profiles_set_updated_at
before update on profiles
for each row
execute function set_updated_at();

create trigger trg_bahan_baku_set_updated_at
before update on bahan_baku
for each row
execute function set_updated_at();

create trigger trg_factory_center_set_updated_at
before update on factory_center
for each row
execute function set_updated_at();

create trigger trg_pengiriman_set_updated_at
before update on pengiriman
for each row
execute function set_updated_at();

create trigger trg_pengiriman_set_tenggat
before insert or update of pengepul_id on pengiriman
for each row
execute function set_pengiriman_tenggat_waktu();

create or replace function public.cancel_overdue_pengiriman()
returns void
language plpgsql
as $$
declare
  end_of_day timestamptz;
begin
  end_of_day := date_trunc('day', now()) + interval '1 day' - interval '1 second';

  with overdue as (
    update pengiriman p
    set status = 'cancelled',
        updated_at = now()
    where p.status = 'on_the_way'
      and p.tenggat_waktu_kirim is not null
      and p.tenggat_waktu_kirim < now()
    returning p.id, p.pengepul_id
  )
  insert into sanksi_booking (pengiriman_id, pengepul_id, reason, berlaku_sampai)
  select o.id,
         o.pengepul_id,
         'Overdue shipment auto-cancelled',
         end_of_day
  from overdue o
  on conflict (pengiriman_id, pengepul_id, reason) do nothing;
end;
$$;

select cron.schedule(
  'cancel-overdue-pengiriman-every-15-min',
  '*/15 * * * *',
  $$select public.cancel_overdue_pengiriman();$$
)
where not exists (
  select 1
  from cron.job
  where jobname = 'cancel-overdue-pengiriman-every-15-min'
);
