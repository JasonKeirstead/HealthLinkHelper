# 🧑‍⚕️ Health Link Helper

> ## ⚠️ USE AT YOUR OWN RISK — NO WARRANTY
> This is **unofficial** software provided **“AS IS”, without warranty of any kind**, express or
> implied. You assume **all risk** for using it. It is **not affiliated with, authorized, or endorsed
> by TELUS, TELUS Health, or Lien Santé NB / NB Health Link.** It talks to a third‑party service that
> can change or break at any time, and it may stop working without notice. Do not rely on it for
> urgent or time‑critical medical needs. By downloading, installing, or using it you accept full
> responsibility for the consequences.

---

**Health Link Helper** is an open-source Android app that helps you find an available appointment on
**Lien Santé NB / NB Health Link** (which runs on TELUS Health Connect). Instead of checking each
clinic one at a time, it scans **every location at once**, across the next **1–6 months**, for the
appointment type you choose — and tells you where the soonest opening is, so you can grab it.

It’s a read-only helper: it **finds** openings and hands you off to the official site to actually
**book**. It never books anything by itself.

## What it does

- 🔎 **Scan all clinics at once** for a chosen appointment type (e.g. Medical Visit), in-person or virtual.
- 🗓️ **Look 1–6 months ahead** (default: 1 month).
- ✅ **Pick which clinics** to include with per-location toggles.
- 🔔 **“Keep checking” background alerts** — if nothing’s open now, it re-checks on an interval and
  sends a **high-priority notification** the moment a slot opens up.
- ↗️ **One tap to book** — opens the official booking page for that clinic (you complete the booking there).

## Requirements

- An **Android** phone (roughly **Android 8.0+**).
- A **Lien Santé NB / NB Health Link** account **that has an email + password set.**
  - ⚠️ **If your account only uses “Sign in with Google/Apple,” this app cannot log you in.** That’s a
    hard limitation imposed by Google/Apple (they block third-party apps from using their sign-in), not
    a bug. If you can, set a password on your account and use that. See the FAQ below.
- Two-factor authentication (email/SMS code) is supported.

## Install (Android)

1. Go to the **[Releases](../../releases)** page and download the latest **`app-release.apk`**.
2. On your phone, open the APK (Files/Downloads app). Android will ask you to allow installs from that
   app — enable **“Install unknown apps”** for it.
3. Tap **Install**, then open **Health Link Helper**.

> The APK is signed with the developer’s key. Android may warn that it’s from an “unknown developer” —
> that’s normal for apps installed outside the Play Store.

## How to use it

1. **Sign in** with your NB Health Link **email and password** (enter the 2FA code if prompted).
2. Choose the **appointment type**, **In-person / Virtual**, and how many **months** ahead to look.
3. Toggle the **clinics** you care about, then tap **Search**.
4. See the soonest openings ranked first. Tap **Book** to open the official site and finish booking.
5. Nothing open? Tap **Keep checking**, pick an interval, and you’ll get a notification when a slot appears.

## FAQ

**Why can’t I sign in with Google/Apple?**
Google and Apple deliberately block their sign-in from working inside third-party apps like this one
(both the embedded-web method and the native method are locked down unless the app is registered in
the *provider’s own* project — which only TELUS controls). There is no way around it from this app.
Use an email/password login instead.

**Does it store my password or send my data anywhere?**
No. The app talks **only** to the official NB Health Link API — there are no analytics and no servers
run by this project. Your login tokens are kept in Android’s **Keystore-encrypted** storage on your
device, app backups are disabled, and the app trusts only system certificate authorities.

**Will there be an iPhone version?**
Technically possible (it’s built with Flutter), but iOS requires a Mac to build and an Apple Developer
account to distribute, and iOS has no simple “download-and-install” like Android. Not currently provided.

**Is this allowed / against TELUS’s terms?**
This is an unofficial client and may be against the service’s Terms of Use. Use it respectfully and at
your own risk — see the disclaimer at the top. Please don’t abuse the service (keep the check interval
reasonable).

## Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (built/tested on 3.44).

```bash
flutter pub get
flutter test        # unit tests for the auth API + scanner
flutter run         # run on a connected device/emulator
```

To build a **release APK**, create `android/key.properties` pointing at your own signing keystore:

```properties
storePassword=…
keyPassword=…
keyAlias=…
storeFile=my-release-key.jks
```

Then:

```bash
flutter build apk --release   # → build/app/outputs/flutter-apk/app-release.apk
```

(Without `key.properties` the release build falls back to the debug key so `flutter run` still works.)

### How it’s built (brief)

Flutter app over the NB Health Link / TELUS Health Connect **GraphQL** API. Login is native
email/password + 2FA (`/auth/sign-in` → `/auth/refresh`, 5-minute access tokens). The scanner sweeps
`locations → services → available days` across all clinics with limited concurrency and ranks the
results. Background monitoring is an in-app timer + local notification (reliable while the app is open
or recently backgrounded).

## License / warranty

Provided **as-is, with no warranty** (see the top of this file). No license is granted beyond viewing
the source unless a `LICENSE` file is added by the author. You are responsible for how you use it.
