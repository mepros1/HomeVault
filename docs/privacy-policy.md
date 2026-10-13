# HomeVault Privacy Policy

> Draft for a local prototype. Hosting, retention/deletion implementation,
> provider configuration, and contact details must be verified before distribution.

**Effective date:** 2026-09-21 · **Applies to:** HomeVault for Android, version 1.x

HomeVault helps you build a home contents inventory for insurance purposes.
This policy explains what data the app handles, what leaves your device, and
why. It is written to be read, not skimmed: the short version is that your
photos and inventory stay on your phone, and only compressed copies of room
photos are sent to our server for the few seconds it takes to recognise
items.

## The short version

| Data | Where it lives | Leaves your device? |
| --- | --- | --- |
| Room photos (originals) | Your phone only | No |
| Compressed copies of room photos (≤ 1024 px) | Sent for analysis, never stored | Yes, transiently |
| Recognised items and estimates | Your phone only | No |
| Receipt, label and extra photos | Your phone only | No |
| Serial numbers read from labels | Your phone only (recognised on the device) | No |
| Home name, address, room names | Your phone only; printed in reports you create | No |
| Anonymous device identifier | Our server, for usage limits | Yes |
| Purchase status | RevenueCat and Google Play | Yes |

## Automated recognition (AI processing)

When you tap **Analyze**, HomeVault sends compressed copies of the photos
of that room (at most eight, each reduced to 1024 pixels on the long side)
to our server. The server forwards them to **Google's Gemini API** (Google
LLC), which returns a list of items it can see with estimated replacement
values. Our server validates that list and returns it to your phone.

- **Retention:** our server holds submitted images in memory only for the
  duration of the request. Google's handling follows the applicable
  [Gemini API terms](https://ai.google.dev/gemini-api/terms); paid-service
  terms describe limited safety/abuse logging, distinct from model-training
  use. This prototype does not promise zero provider retention.
  The recognised list (item names, categories,
  estimates) is cached on our server for up to 24 hours so that a retried
  request after a dropped connection does not count against your usage
  limit; it contains no images.
- **Nothing else is sent.** Receipts, labels, close-up photos you attach to
  an item, serial numbers and everything you type stay on your device.
- **Results are suggestions.** Items and estimates are generated
  automatically and must be reviewed by you. HomeVault is not an appraisal
  and not insurance advice; estimated replacement values are for reference
  only.

## App integrity checks

To keep the analysis service available and affordable, the app asks
**Google Play Integrity** for a token that confirms it is a genuine copy of
HomeVault running on a genuine Android device, and sends that token to our
server together with the analysis request. Google processes device and app
information for this purpose under its own privacy policy; our server only
learns whether the check passed. We do not use the result for anything
other than accepting or refusing the request.

## Data we keep on our server

- **An anonymous device identifier** created by the app on first launch
  and a token derived from it. We use it to count how many rooms have been
  analysed this month and to apply the free and Pro limits. It is not
  linked to your name, email, Google account or advertising ID.
- **Usage counters** per device per month.
- **Review statistics**: how many suggested items were accepted, edited or
  deleted, as plain totals per version of our recognition prompt. These
  are added to a single shared counter and are not stored per device; they
  contain no item names, values, photos or room information. We use them
  to measure and improve recognition quality.
- **Recognition results** for up to 24 hours, as described above.
- **Backup copies of your PDF reports**, if you leave "Back up reports to
  the cloud" switched on in Settings (it is on by default). A report
  contains your inventory, estimated values, the home details you entered
  and small thumbnails of your room photos. Backups are tied to your
  anonymous device identifier; you can download or delete each one from
  the Report screen, and move them to a new phone with a one-time transfer
  code. We never look at their contents. Backups are deleted after twelve
  months without activity from the device.

We do not run analytics or advertising SDKs. We do not collect location
data: room photos are not tagged with GPS coordinates in this version.

## Purchases

HomeVault Pro is a one-time purchase processed by **Google Play**. We use
**RevenueCat** to check whether a purchase is active. RevenueCat receives
the same anonymous device identifier described above and the purchase
receipt from Google; it does not receive your photos or inventory. When a
purchase, refund or transfer happens, RevenueCat notifies our server so that
Pro limits apply to your device. See RevenueCat's privacy policy at
https://www.revenuecat.com/privacy and Google Play's terms for payments.

## Reports you create

PDF and CSV reports are generated on your device and saved in the app's
private storage. They contain your inventory, estimated values, photos and
the home details you entered. You choose whether and with whom to share
them through the Android share sheet; we never see them.

## Permissions

- **Camera** to photograph rooms and labels. Requested only when you open
  the camera screen.
- **Photos** through the Android photo picker, limited to the photos you
  select.
- **Internet** to reach our server for item recognition and to verify
  purchases.

## Your choices

- Delete photos, items, rooms or the whole home inside the app; the files
  are removed from your device immediately.
- Uninstalling the app removes all local data. The anonymous device record
  on our server is removed after twelve months without activity; email us
  to have it deleted sooner.
- Use the app without ever tapping Analyze: rooms, photos, manual items
  and reports work fully offline.

## Children

HomeVault is not directed at children under 13 and does not knowingly
collect personal information from them.

## Changes

We will update this page when the policy changes and note the effective
date at the top. Material changes are also announced inside the app.

## Contact

Questions and deletion requests: **privacy@homevault.app**
