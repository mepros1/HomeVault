-- Cloud backup of PDF reports (the only user files the server keeps).
-- Content lives in Postgres: a few MB per report, a handful per user. Move
-- to object storage if that stops being true.
create table report_backups (
  id           uuid primary key,
  user_id      uuid not null,
  file_name    text not null,
  size_bytes   integer not null,
  sha256       text not null,
  generated_at timestamptz not null,
  item_count   integer not null default 0,
  total_low    numeric(14,2) not null default 0,
  total_high   numeric(14,2) not null default 0,
  content      bytea not null,
  created_at   timestamptz not null default now()
);
create index idx_report_backups_user on report_backups (user_id, generated_at desc);

-- One-time codes that move a user's backups to another device.
create table backup_transfers (
  code         text primary key,
  from_user_id uuid not null,
  expires_at   timestamptz not null,
  used_at      timestamptz
);
