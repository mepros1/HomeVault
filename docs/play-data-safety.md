> Draft for a local prototype. Answers require validation against the actual
> deployment; see release-limitations.md. PDF backups can contain photo thumbnails
> and home details. Provider retention follows its terms.

# Google Play Data Safety — answers for HomeVault 1.x

Working sheet for the Play Console form. Keep in sync with
`docs/privacy-policy.md` and with what the code actually does.

## Overview questions

| Question | Answer | Why |
| --- | --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** | Photos leave the device for analysis; a device identifier is stored on our server. |
| Is all of the user data collected by your app encrypted in transit? | **Yes** | HTTPS only in release builds (cleartext is allowed in debug builds only). |
| Do you provide a way for users to request that their data is deleted? | **Yes** | In-app deletion for local data; email for the server-side device record. |

## Data types

### Photos and videos → Photos
- Collected: **Yes**. Shared: **Yes** (processed by Google Gemini API on our behalf).
- Ephemeral processing: **Yes** — compressed copies are held in memory for the request only, never stored on our server or by the provider.
- Required or optional: **Optional** — the user chooses when to tap Analyze; the app works without it.
- Purpose: **App functionality** (item recognition).

### Device or other IDs
- Collected: **Yes**. Shared: **Yes** (the same app-generated id is the
  RevenueCat app user id, so RevenueCat acts as a processor for purchases).
- Ephemeral: **No** — stored to enforce usage limits.
- Required: **Yes** for the analysis feature.
- Purpose: **App functionality**, **Fraud prevention, security and compliance** (abuse limits).
- Note: this is an app-generated random identifier, not the Android ID or advertising ID.

### Purchase history (App activity → In-app purchases)
- Collected: **Yes** via RevenueCat / Google Play. Shared: **Yes** with RevenueCat as a processor.
- Purpose: **App functionality** (unlocking Pro).

### Files and docs
- Collected: **Yes** (PDF reports, when cloud backup is on). Shared: **No**.
- Ephemeral: **No** — stored until the user deletes them or after twelve
  months of inactivity.
- Required or optional: **Optional** — the Settings switch turns it off.
- Purpose: **App functionality** (restore reports on a new phone).
- Note: the report embeds small thumbnails of room photos; the photos
  themselves are never uploaded for backup.

### App activity → App interactions
- Collected: **Yes**. Shared: **No**.
- What: counts of accepted / edited / deleted suggestions per prompt
  version, aggregated server-side into one shared counter (not linked to
  the device record). No item content.
- Ephemeral: **No**. Required: **Yes** (sent automatically, cannot be
  opted out of in v1).
- Purpose: **Analytics** (recognition quality).

### Not collected
- Location (no GPS on captures in v1), contacts, financial info entered by
  the user (purchase price stays on device), health, messages, audio,
  files other than the photos above, calendar, web browsing, installed apps,
  crash logs and diagnostics (no crash reporting SDK in v1), name, email,
  address (home address is typed by the user and stays on device).

## Security practices
- Data encrypted in transit: **Yes**.
- Play Integrity API is used (standard requests). Google's SDK handles the
  device signals; the app itself only forwards the opaque token to our
  server. No extra data type needs declaring for it, but the privacy
  policy mentions it.
- Users can request deletion: **Yes** (privacy@homevault.app).
- Independent security review: **No**.

## AI-generated content declaration
- Store listing graphics: declare **Yes** if any screenshot, feature graphic
  or icon was produced with a generative tool (Scenario is planned for
  listing art). Keep a note of which assets were generated.
- In-app: the results screen and every report state that items and
  estimates were generated automatically and must be reviewed.

## Before submitting
- [ ] Privacy policy hosted at the URL passed as `PRIVACY_POLICY_URL` and entered in the console.
- [ ] `targetSdk = 36` (set), release build signed with the upload key.
- [ ] Camera permission rationale shown before the system prompt (done in `CaptureScreen`).
- [ ] Re-check this sheet if GPS capture, crash reporting or analytics are added.
