# HomeVault — project conventions

Flutter (Android-only in v1) app that builds a home contents inventory for
insurance from room photos, plus a Java server that runs the AI analysis.
The spec lives with the product owner; the decisions below are the ones that
are not obvious from the code.

## Stack

- App: Flutter 3.44 / Dart 3.12, Riverpod 3 with `riverpod_generator`,
  go_router, Drift (SQLite) as the source of truth on device.
- Server: Spring Boot 4.1 on Java 21 in `server/`, any PostgreSQL 14+ via
  JDBC, Flyway migrations, Spring Security resource server for bearer tokens.
  Model: Gemini (`GEMINI_MODEL` env, default `gemini-3.1-flash-lite`) via
  REST with `responseSchema` structured output. Paid tier only.
- Auth: server-issued anonymous device tokens. The app generates a device id
  on first launch together with a random 256-bit device secret, registers via
  `POST /v1/devices` using both, keeps the token and secret in
  flutter_secure_storage and re-registers once on 401 (`lib/data/auth/`).
  Server side `AUTH_MODE=supabase` verifies
  Supabase Auth JWTs against the project JWKS instead. Real accounts are v2.
  The server stores only the device secret hash (migration V4). A public device
  id alone cannot renew a token. Legacy rows without a hash require an
  authenticated migration or a fresh local setup; never allow arbitrary takeover.
- Hosting: undecided. The server ships as a plain Docker image.
- JSON models in the app use `json_serializable`. `freezed` is deliberately
  absent: its stable release conflicts with `drift_dev` on the analyzer.
- `go_router` is pinned to 17.x: 18.x depends on `cupertino_ui` /
  `material_ui`, which need a newer Flutter than 3.44.8 (they reference
  `awaitNotRequired`, not exported by this SDK). Re-check after a Flutter
  upgrade.
- Providers that return Drift row classes (`Home`, `Room`, …) are written by
  hand (`StreamProvider`, `Provider`), not with `@riverpod`: the row classes
  live in a generated part file that `riverpod_generator` cannot see in the
  same build phase. Providers returning other types use codegen.
- App Check = Play Integrity standard API. The app sends `X-App-Check`
  when built with `PLAY_INTEGRITY_PROJECT_NUMBER`; the server verifies it in
  `APP_CHECK_MODE=off|log|enforce` (see "App Check" below).

## Commands

```bash
# app
dart run build_runner build          # regenerate *.g.dart (Drift, Riverpod, JSON)
flutter gen-l10n                     # regenerate lib/l10n/app_localizations*.dart
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080   # emulator -> host

# server (from server/)
docker compose up -d                 # local Postgres on 5432
mvn test
AUTH_SECRET=<32+ bytes> GEMINI_API_KEY=... mvn spring-boot:run
docker build -t homevault-server .
```

Generated files (`*.g.dart`, `lib/l10n/app_localizations*.dart`,
`server/target/`) are git-ignored. Run the two generate commands after a
fresh clone.

## Code layout

```
lib/core/        enums, constants, env, router, disclaimer text
lib/data/db/     Drift tables, database, DAOs
lib/data/api/    analyze-room client, wire models, error types, idempotency
lib/data/auth/   device id + token store, registration client, Session notifier
lib/data/media/  image preparation (resize / recompress for upload)
lib/data/providers.dart   app-wide Riverpod providers
lib/features/<feature>/   screens and feature-local providers
lib/l10n/        ARB files; all user-facing strings go here

server/src/main/java/com/homevault/server/
  api/       controller, ApiException, error rendering
  analysis/  AnalysisService (worker flow), GeminiClient, ItemValidator,
             PromptRegistry, wire records
  auth/      device registration and token issuing
  backup/    PDF report backups and transfer codes
  billing/   RevenueCat webhook
  integrity/ Play Integrity (App Check) verification
  stats/     review counters endpoint
  quota/     quota RPC wrapper, idempotency cache, entitlements, budget
  config/    properties, security, JWT decoder selection
server/src/main/resources/
  prompts/   analyze-room.txt (versioned prompt), response schema JSON
  db/migration/  Flyway migrations
```

## Rules that must hold

- Every user change to an item goes through `ItemsDao.applyUserEdit` so
  `user_edited` is set. Re-analysis never touches `user_edited = true` rows
  and replaces everything else, accepted rows included. Keeping accepted
  rows was tried (2026-09-21) and duplicated every item on a re-run, because
  the model recognises the same objects again.
- Review-screen order is `est_high DESC`. Do not re-sort client-side.
- Items with `confidence < 0.6` need explicit confirmation in the UI.
- `is_high_value` = `est_high >= threshold` (default 1500) **or** category in
  Jewelry & Watches / Art & Collectibles.
- Upload images: ≤ 1024 px long side, JPEG q80, and ≤ 400 KB. `image_prep.dart`
  lowers quality until the size limit holds; the server rejects larger files
  with 413.
- The idempotency key is SHA-256 over the sorted capture hashes. The server
  recomputes the same value if the header is missing; keep `IdempotencyKeys`
  and `idempotency.dart` in sync.
- Prompt text lives only in `server/src/main/resources/prompts/analyze-room.txt`.
  Its first line is `version: <id>`; bump it on any wording change. Never put
  prompt text in the app.
- The disclaimer strings in `core/constants.dart` appear on the results
  screen and in every report. Do not remove or paraphrase them.
- Strings: English only in v1, but every user-facing string goes through
  `AppLocalizations`. No literals in widgets.
- Serial-number OCR runs on device (ML Kit, `lib/data/ocr/`). Attachments
  live under `attachments/<itemId>/` via `AttachmentStore` and are never
  uploaded. A label photo is OCR'd and `LabelParser` offers serial / model
  candidates; the user picks, nothing is written until Save. The server
  never persists images.
- Capture files live under the app documents dir as
  `captures/<roomId>/<id>.jpg` plus `<id>_thumb.jpg`; `captures.file_path`
  and `thumb_path` are stored RELATIVE to that dir. Resolve through
  `CaptureStore.absolutePath`, never store absolute paths. Originals are
  written byte-for-byte (the SHA-256 must keep matching); the 1024 px upload
  copy is produced at analysis time by `prepareForAnalysis`, not stored.
- Files are never deleted synchronously with rows (cascades, undoable
  deletes). `StorageJanitor.sweep()` runs at app start and after a room is
  deleted and removes `captures/<roomId>`, `attachments/<itemId>`, PDFs
  without a `reports` row and CSVs older than a day.
- Camera permission: show the in-app rationale pane before the system prompt
  (spec section 8). `CaptureScreen` owns that flow; gallery import must stay
  available when the camera is denied.

## Schema additions vs the spec

- App: `items.review_status` (pending | accepted) for the re-analysis rule;
  `review_stats` (accepted / edited / deleted counters per prompt version,
  plus `synced_*` columns holding what was last uploaded; schema v2);
  `items.prompt_version` to attribute quality metrics to a prompt revision;
  `analysis_jobs` as the persistent offline queue.
- Server: `devices`, `entitlements`, `analysis_cache`, `daily_usage` (global
  budget), `review_stats` (aggregated counters), `report_backups` and
  `backup_transfers` (cloud backup); `usage` matches the spec.
- App: `reports.backed_up_at` (schema v3).

## Analysis queue semantics (app)

`AnalysisQueue` drains `analysis_jobs` one job at a time. `enqueue(roomId)`
is idempotent while a job for that room is queued or running. The runner
sends up to 8 captures (close-ups included, oldest first), recomputes the
idempotency key from their hashes, and on success calls
`ItemsDao.replaceAnalyzedItems`, marks captures analyzed and sets the room
to `analyzed`. Network and upstream failures leave the job `queued` with a
`last_error` code (retried on connectivity change, app start or manual
retry, up to 5 attempts); everything else is `failed` with a `JobError`
code that the UI maps to text via `analysisErrorReason`. Jobs stuck in
`running` after a crash are reset on `start()`.

## Review semantics (app)

`ReviewRepository` is the only path for accept / delete / undo / save. Saving
the item card sets `user_edited` AND accepts the item. Every action bumps
`review_stats` (accepted / edited / deleted per `prompt_version`, counts
only; undo decrements). The room flips `analyzed` -> `reviewed` when no
pending items remain and back if a pending item reappears (undo, re-run).
On the card stack a right swipe is refused for items below the confidence
threshold; the button reads "Confirm" instead of "Accept".

## Reports (app)

`ReportBuilder` reads home, rooms in order, items in review order and
captures into `ReportData`; line values are estimate x quantity. PDF layout
lives in `PdfReportGenerator` (title, room summary, category summary,
high-value section, item table with thumbnails, photo appendix with
time / coordinates / hash prefix, disclaimer page). Fonts are Noto Sans from
`assets/fonts` (OFL); tests load them from disk. Free tier PDFs carry the
"HOMEVAULT FREE" watermark; CSV (`CsvReportGenerator`, RFC 4180) throws
`ProRequired` on Free. Files go to `<base>/reports/`, paths relative like
captures; PDFs get a `reports` row, CSVs do not. Sharing uses share_plus.

## Cloud backup of reports

PDFs (never photos, never the inventory database) are copied to the server
when `CloudBackupEnabled` (Settings, default on) holds. `ReportBackupService`
uploads right after export and retries pending rows (`reports.backed_up_at`
null, schema v3) at app start; network failures and a full backup stop the
run. Server: `backup/` package, `report_backups` (bytea in Postgres,
`BACKUP_*` limits: 20 reports, 8 MB each, 100 MB per device) and
`backup_transfers`. Endpoints under `/v1/backups`: list, multipart upload
(PDF magic check, upsert by id), download, delete, `transfer-code`
(8 chars, 15 min, one use) and `claim` (moves every backup of the old
device to the caller). The RevenueCat `TRANSFER` webhook moves backups the
same way. Backups of devices unseen for `BACKUP_RETENTION` (365d) are purged
daily. UI: `CloudBackupSection` on the report screen (download goes to a
temp dir and the share sheet, not into `reports/`, so the janitor leaves it
alone).

## Mock recognition (server)

`GEMINI_MOCK=true` makes `GeminiClient` return canned items from
`MockRecognition` (kitchen / living / bedroom / generic by room type, spread
over the uploaded images, one low-confidence row, multi-quantity rows) with
`model: "mock"`. Everything else (auth, quota, cache, validation, the app)
runs unchanged. Never enable it in a production deployment.

## Server quota semantics

`consume_room_quota` counts analyses per calendar month (UTC). Defaults:
free 3 / month (so the one free room can be re-analysed a couple of times),
pro 300 / month as an abuse cap. The Free-tier "one room" limit is enforced
in the app, not on the server. A 422 or a model failure releases the quota.

Two more fuses sit in front of the per-user quota:

- `DAILY_BUDGET` (default 2000, 0 = off): global analyses per UTC day in
  `daily_usage` via `consume_daily_budget`; exhausted -> 503
  `budget_exhausted`. Released on the same paths as the user quota.
- `RateLimitFilter`: per-IP fixed hourly windows on `POST /v1/devices`
  (`RATE_DEVICES_PER_HOUR`, 20) and `POST /v1/analyze-room`
  (`RATE_ANALYZE_PER_HOUR`, 120) -> 429 `rate_limited`. In-memory, so the
  effective limit scales with the instance count. `TRUST_FORWARDED_FOR=true`
  only behind a proxy that overwrites `X-Forwarded-For`. The filter is
  registered in `RateLimitConfig` (not component-scanned) so `@WebMvcTest`
  slices do not load it.

## Review stats upload

`ReviewStatsUploader` posts `review_stats` deltas (counts per prompt
version, nothing else) to `POST /v1/stats/review` at app start and when a
room flips to `reviewed`; on 204 it stores the uploaded values in
`synced_*`. Negative deltas (undo after a sync) are sent as 0 and re-based.
The server adds them to its `review_stats` table. Failures are silent and
retried on the next trigger.

## Purchases and settings (app)

`PurchasesGateway` wraps RevenueCat (`purchases_flutter`); without
`REVENUECAT_API_KEY` the app uses `UnavailablePurchasesGateway` and the
paywall says purchases are unavailable. `CurrentEntitlement` is the only
source of Free / Pro: it follows SDK updates, purchase and restore results,
and a debug-only switch in Settings. Entitlement id in RevenueCat: `pro`,
lifetime package. Every gated feature calls `showProDialog` -> paywall.
RevenueCat is configured with the device id as `appUserID`
(`Session.deviceId()`), which is what the server webhook keys on.
The high-value threshold lives in `HighValueThreshold` (shared_preferences);
changing it runs `ItemsDao.recomputeHighValue` over all items.

## Deferred (v1 backlog, do not build unless asked)

GPS on captures (schema ready, collection off), merge-items UI, list mode on
the review screen.

## App Check (Play Integrity)

- App: `lib/data/integrity/app_check.dart`. `PlayIntegrityAppCheck` talks to
  the `homevault/app_check` MethodChannel in `MainActivity.kt` (`prepare`
  once per process with the Cloud project number, `token(requestHash)`).
  `DeviceAuthClient` binds the token to the device id, `AnalyzeRoomClient`
  to the idempotency key, one fresh token per attempt. Any failure means
  "no header"; the app never blocks on integrity itself.
- Server: `integrity/` package. `AppCheckVerifier.verify(token, expectedHash,
  context)` runs on `POST /v1/devices` and `/v1/analyze-room`. Checks:
  package name, `requestHash`, token age <= `APP_CHECK_MAX_TOKEN_AGE` (10m),
  `appRecognitionVerdict == PLAY_RECOGNIZED`, device verdict contains
  `MEETS_DEVICE_INTEGRITY`. `log` mode only logs `would_reject`; `enforce`
  answers 403 `app_check_failed` (the app shows the "update the app" stub).
  Decoding goes through `playintegrity.googleapis.com` with a service
  account (`GoogleServiceAccount`: RFC 7523 JWT grant, no Google SDK).
  `enforce` without `PLAY_INTEGRITY_SERVICE_ACCOUNT_FILE` refuses to start.
- Rollout: sideloaded / debug builds never get `PLAY_RECOGNIZED`, so keep
  the server in `log` until the Play internal-track build shows clean
  verdicts, then switch to `enforce`. Emulator and `flutter run` builds keep
  working in `off` / `log`.

## RevenueCat webhook (server)

`POST /v1/webhooks/revenuecat` (own security chain, no JWT) checks the
`Authorization` header against `REVENUECAT_WEBHOOK_SECRET` (empty = 503,
endpoint off) and writes `entitlements.is_pro` for the device matching
`app_user_id` or any of `aliases`. Purchase-type events grant when
`entitlement_ids` contains `pro`; `EXPIRATION` revokes; `CANCELLATION`
revokes only with a past `expiration_at_ms` (refund); `TRANSFER` moves the
flag. Unknown users and other event types are acknowledged with 200 so
RevenueCat stops retrying. Dashboard setup: Integrations -> Webhooks, URL
`https://<host>/v1/webhooks/revenuecat`, Authorization header value =
the secret.

## Release

- `flutter build appbundle --release --dart-define=API_BASE_URL=... --dart-define=REVENUECAT_API_KEY=... --dart-define=PRIVACY_POLICY_URL=... --dart-define=PLAY_INTEGRITY_PROJECT_NUMBER=<cloud project number>`
- Signing: `android/key.properties` (template `key.properties.example`,
  git-ignored). Without it release builds are signed with the debug key.
- Release builds are minified (R8) with `android/app/proguard-rules.pro`;
  re-test OCR and purchases after touching those rules.
- Size budget (spec: APK <= 40 MB): arm64 release APK is ~38 MB, of which
  ML Kit's bundled OCR pipeline is ~11 MB. If it ever crosses 40 MB, the
  first lever is the unbundled ML Kit text recogniser (model via Play
  Services) at the cost of a download on first OCR.
- Store docs: `docs/privacy-policy.md` (host it, pass the URL as
  `PRIVACY_POLICY_URL`) and `docs/play-data-safety.md` (answers for the
  console form). Update both when data flows change.

## Testing notes

- Widget tests use `AppDatabase(NativeDatabase.memory())` via
  `appDatabaseProvider.overrideWithValue`. End each widget test with the
  `finish(tester)` helper from `test/rooms_flow_test.dart`: unmount, then
  `pump(const Duration(milliseconds: 1))` so Drift's zero-delay timer fires.
  Do not call `db.close()` inside `testWidgets`: it never completes under the
  fake-async zone. Plain `test()` bodies can close the database normally.
- Use `pumpAndSettle` with an explicit short timeout (see `settle()`); the
  default is 10 minutes and turns a stuck animation into a very slow failure.
- End-to-end: `integration_test/app_flow_test.dart` runs the whole flow on
  a device against an in-process fake server (`FakeServer` in the test):
  `flutter test integration_test/app_flow_test.dart -d <device> --dart-define=API_BASE_URL=http://127.0.0.1:9`.
  The dart-define only needs to be non-empty; every client is overridden.
  Photos are written through `CaptureStore` (camera and gallery picker
  cannot be driven). Not part of CI (needs an emulator); run it before a
  release build.
- CI (`.github/workflows/ci.yml`): analyze with `--fatal-infos`, `flutter
  test`, `mvn test` and a Docker image build. Server tests need no database.
