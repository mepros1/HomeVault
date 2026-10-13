-- Legacy devices have no ownership proof. Never let a caller claiming their
-- id choose a new secret. Existing JWTs remain valid until they expire; those
-- devices need an explicit, authenticated migration before token renewal.
alter table devices add column secret_hash text;
