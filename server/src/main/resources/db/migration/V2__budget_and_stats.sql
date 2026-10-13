-- Global daily analysis budget: a cost fuse independent of per-user quotas.
create table daily_usage (
  day      date primary key,
  analyses integer not null default 0
);

-- Consume one analysis from today's budget. Returns the new count, or -1
-- when the budget is exhausted (nothing consumed).
create or replace function consume_daily_budget(p_limit integer)
returns integer
language plpgsql
as $$
declare
  v_day   date := (now() at time zone 'utc')::date;
  v_count integer;
begin
  insert into daily_usage (day, analyses) values (v_day, 0)
    on conflict (day) do nothing;
  select analyses into v_count from daily_usage where day = v_day for update;
  if v_count >= p_limit then
    return -1;
  end if;
  update daily_usage set analyses = analyses + 1 where day = v_day;
  return v_count + 1;
end;
$$;

create or replace function release_daily_budget()
returns void
language sql
as $$
  update daily_usage
     set analyses = greatest(analyses - 1, 0)
   where day = (now() at time zone 'utc')::date;
$$;

-- Recognition-quality counters (spec section 10), aggregated over all
-- devices per prompt version. Counts only; never item content.
create table review_stats (
  prompt_version text primary key,
  accepted       bigint not null default 0,
  edited         bigint not null default 0,
  deleted        bigint not null default 0,
  updated_at     timestamptz not null default now()
);
