# Release limitations

HomeVault is a local prototype prepared for source publication, not an approved
production deployment or Google Play release.

## Before exposing the backend

- Deploy with HTTPS, private PostgreSQL access, dedicated credentials, and securely
  managed authentication/provider/webhook secrets.
- Test Flyway migrations and quota/backup repositories against real PostgreSQL.
  Repository unit tests use mocks and do not establish database concurrency behavior.
- Analysis idempotency is a completed-response cache. Overlapping requests with
  the same key can both miss it, consume quota, and call the provider. Introduce a
  database-backed request reservation/lease before relying on it to prevent duplicate
  spend. Avoid keeping database connections open during provider HTTP calls.
- Cache identity depends on a client key derived from image hashes. Include room
  type, currency, prompt revision, and ordered images in a request fingerprint, and
  reject a reused key with different content; otherwise changed context can return
  stale results.
- Backup count/byte checks and writes are not one locked operation. Concurrent
  uploads can exceed limits. Transfers should also respect destination limits.
- Billing webhooks lack persisted event-id deduplication/event-time ordering.
  Replay or out-of-order delivery can overwrite a newer entitlement.
- The mobile runner needs explicit handling for damaged/missing photo files and
  malformed responses; restart recovery should not be its only exception recovery.

## Before a store release

- Configure Google Play/RevenueCat products, restore flows, and a real signing key.
  Gradle currently permits a debug-key fallback for local release builds.
- Verify purchase/webhook consistency and Play Integrity on an actual Play track.
- Test real recognition with a representative, consented dataset.
- Exercise camera denial, offline use, photo corruption, repeat analysis, and report
  restore/transfer on a device.
- Replace draft policy/contact URLs with verified resources. PDF backups may contain
  home details and photo thumbnails.
- Implement the retention/deletion behavior promised by the published policy.
  Current housekeeping removes inactive report backups, not all device records.

## AI provider documentation

Do not promise that Google never retains submitted images. Paid Gemini API terms
describe limited safety/abuse logging, distinct from model-training use:
[Gemini API terms](https://ai.google.dev/gemini-api/terms). Check applicable terms
and the provider configuration before distributing the app.
