-- HomeVault server schema. The device is the source of truth for inventory
-- data (spec section 4); the server holds only identities, quotas,
-- entitlements and the analysis worker's idempotency cache.
-- Works on any PostgreSQL 14+ (Supabase included).

-- Anonymous device identities (auth mode "device"). One row per install;
-- user_id is what every other table refers to, so a real account system can
-- take over later by mapping devices to users.
create table devices (
  device_id    text primary key,
  user_id      uuid not null unique default gen_random_uuid(),
  platform     text,
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

-- Pro entitlement, written by the RevenueCat webhook (later) or manually.
create table entitlements (
  user_id    uuid primary key,
  is_pro     boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Monthly analysis counters (spec section 4 `usage`).
create table usage (
  user_id         uuid not null,
  period_ym       text not null,                -- 'YYYYMM', UTC
  rooms_analyzed  integer not null default 0,
  last_request_at timestamptz,
  primary key (user_id, period_ym)
);

-- 24-hour idempotency cache (spec section 5.1). Images are never stored.
create table analysis_cache (
  user_id         uuid not null,
  idempotency_key text not null,
  response        jsonb not null,
  created_at      timestamptz not null default now(),
  primary key (user_id, idempotency_key)
);
create index analysis_cache_created_idx on analysis_cache (created_at);

-- Atomically check and consume one room analysis for the current month.
-- Returns {allowed, used, limit, resets_at}.
create or replace function consume_room_quota(
  p_user_id    uuid,
  p_free_limit integer,
  p_pro_limit  integer
) returns jsonb
language plpgsql
as $$
declare
  v_period text := to_char(now() at time zone 'utc', 'YYYYMM');
  v_pro    boolean;
  v_limit  integer;
  v_used   integer;
  -- next month boundary in UTC, independent of the session time zone
  v_resets timestamptz := (date_trunc('month', now() at time zone 'utc') + interval '1 month') at time zone 'utc';
begin
  select coalesce(is_pro, false) into v_pro
    from entitlements where user_id = p_user_id;
  v_limit := case when coalesce(v_pro, false) then p_pro_limit else p_free_limit end;

  insert into usage (user_id, period_ym, rooms_analyzed, last_request_at)
    values (p_user_id, v_period, 0, now())
    on conflict (user_id, period_ym) do nothing;

  select rooms_analyzed into v_used
    from usage
    where user_id = p_user_id and period_ym = v_period
    for update;

  if v_used >= v_limit then
    return jsonb_build_object(
      'allowed', false, 'used', v_used, 'limit', v_limit, 'resets_at', v_resets);
  end if;

  update usage
     set rooms_analyzed = rooms_analyzed + 1, last_request_at = now()
   where user_id = p_user_id and period_ym = v_period;

  return jsonb_build_object(
    'allowed', true, 'used', v_used + 1, 'limit', v_limit, 'resets_at', v_resets);
end;
$$;

-- Gives one analysis back when the model failed or recognised nothing: the
-- user should not pay quota for an unusable result.
create or replace function release_room_quota(p_user_id uuid)
returns void
language sql
as $$
  update usage
     set rooms_analyzed = greatest(rooms_analyzed - 1, 0)
   where user_id = p_user_id
     and period_ym = to_char(now() at time zone 'utc', 'YYYYMM');
$$;
