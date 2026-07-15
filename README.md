# HealthLink Scanner (Flutter)

Personal mobile + web app that scans **all** Lien Santé NB Health link (TELUS Health
Connect) locations for the next N months and surfaces the soonest open appointment of a
chosen type — then hands off to TELUS to book.

Built against the TELUS Health Connect ("EBB") GraphQL API.

## Status

| Piece | State |
|---|---|
| Pure-Dart core (models, GraphQL ops, API client, scanner, auth/refresh) | ✅ implemented + unit-tested |
| Account/chart bootstrap (no hardcoded IDs) | ✅ implemented |
| Scanner engine (all-locations × N-month sweep, ranked) | ✅ implemented + tested |
| Mobile UI (patient/type/modality, months 1–6, per-location toggles, results) | ✅ implemented |
| Background monitor + high-priority notification when a slot opens | ✅ implemented (in-app timer — see **Monitoring**) |
| **Email/password login (+ 2FA)** | ✅ implemented + unit-tested — the only supported login |
| SSO (Google/Apple) | ❌ not supported by design — see **Auth** |
| Web target (CORS proxy + web auth) | ⛔ not yet — see **Web** |

## Run

Verified against **Flutter 3.44.6 / Dart 3.12.2** (WSL). `android/ios/web` scaffolding is generated,
deps resolve, `flutter analyze` is clean, and `flutter test` is green.

```bash
cd app
flutter pub get
flutter test        # 7 tests: auth API (sign-in/2FA/refresh) + scanner ranking
flutter analyze     # no issues
flutter run         # on a connected Android/iOS device
```

Android needs `INTERNET` permission (default). The scanner needs a real signed-in session, so run it
on a device against a TELUS account with a password set (see **Auth**).

## Architecture

```
lib/
  main.dart                     bootstrap: restore session → HealthLinkApp
  src/
    config.dart                 endpoints, localStorage keys, token skew
    models/                     enums (BookingType/VisitType/Modality) + data classes
    api/
      graphql_ops.dart          verbatim captured queries + mutations
      api_client.dart           GraphQLTransport (Direct) + EbbApi (+ auth-retry) + GraphQLExecutor seam
      booking_repository.dart    typed booking queries
      account_bootstrap.dart     accounts + charts → List<Patient>
    auth/
      tokens.dart               Tokens + JWT-exp decode (pure, tested)
      auth_api.dart             email/password sign-in, 2FA, refresh endpoints (tested)
      auth_controller.dart      session state + token freshness, secure storage
    scanner/scanner.dart        the sweep engine (concurrency-limited, ranked)
    ui/                         login_screen + scan_screen + results_view
```

The whole `src/api`, `src/scanner`, `src/models`, `src/auth/tokens.dart` layer is pure Dart
and reused unchanged on web. Only `login_webview.dart` (auth capture) and the transport
swap out per platform.

## Auth (email/password only)

Login is a **direct native call** — no WebView, no SSO:

```
POST /auth/sign-in   body {username, password}
  headers: ClientId: d0Vi, endpoint-version: 2024-02-07, x-long-lived-refresh-token: <bool>
  → 200 with {accessToken, refreshToken}    (signed in)
  → 200 with {ref, primaryTwoFactorAuthenticationMethod, isEmailEnabled, isSMSEnabled, email}
        → POST /auth/services/two-factor/request {ref, type}
        → POST /auth/services/two-factor/confirm {ref, pin}  (header x-check-2fa: true) → tokens
POST /auth/refresh   body {refreshToken}   header ClientId: d0Vi  → rotated {accessToken, refreshToken}
```

Key facts (from the app bundle / live capture):
- **`ClientId` is a constant `"d0Vi"`** (`Dk(){return "d0Vi"}`) — not device-generated. Hardcoded in `config.dart`.
- Tokens are camelCase and both rotate on every refresh; access token TTL ~5 min.

**Why SSO is not supported (both paths empirically closed for a third-party app):**
- **Embedded WebView** → Google rejects OAuth in embedded views ("insecure browser" / disallowed_useragent).
- **Native `google_sign_in`** → Google Play Services returns `UNREGISTERED_ON_API_CONSOLE`: it won't
  mint an ID token for TELUS's web client on behalf of our app, because our package/signing key isn't
  registered in TELUS's Google Cloud project (only TELUS can add it).

So this app requires a TELUS account with a **password** set. (Reference for completeness: TELUS's own
native login is `POST /auth/sign-in/{google,apple}` with a provider `idToken`.)

## Monitoring (notify me when a slot opens)

When a search finds nothing, the results screen offers **"Keep checking in the background"** with an
interval (5/15/30/60 min). It re-runs the same search on a `Timer.periodic`; the moment any location
has an open day it fires a **high-importance local notification** (channel `slot_alerts`, `Importance.max`)
and stops. Requires notification permission (requested on start; `POST_NOTIFICATIONS` in the manifest).

**Reliability caveat:** this is an in-app timer, so it runs while the app is foregrounded or recently
backgrounded. Android will suspend timers under Doze once the app is fully closed for a while. For
truly-closed-app polling, the upgrade is a foreground service or `workmanager` periodic task (min 15 min)
that reconstructs auth+scan in a background isolate — left as a follow-up.

## Web (next phase)

Flutter web can't WebView-capture cross-origin tokens, and `backend.thconnect.telushealth.com`
will CORS-block our origin. Plan: a thin proxy (holds refresh token, adds CORS, proxies GraphQL)
+ a browser-extension or paste-based token hand-off. The Dart core is reused as-is behind the
`GraphQLTransport` interface (add a `ProxyGraphQLTransport`).

## Ethics

The scanner is read-only and mirrors the app's own calls; keep concurrency modest (default 4).
Booking (`createAppointment`) is real and consumes scarce slots — the app only ever opens the
TELUS booking page; it never books automatically.
