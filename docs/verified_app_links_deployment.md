# Verified App Links — deployment guide

The Android app already declares an `<intent-filter android:autoVerify="true">`
for `https://rodnya-tree.ru/oauth/*`, AND `_mobileOauthCallback` is now
the https URL. The only missing piece for the OS to grant us exclusive
ownership of those paths (so no other app can intercept the OAuth
callback) is publishing the matching `assetlinks.json` on the marketing
site so Android's autoVerify pass succeeds.

> **Front-end note**: production currently uses nginx, not Caddy.
> The active site config is in
> [`deploy/nginx/rodnya.conf`](../deploy/nginx/rodnya.conf) and is
> installed via [`deploy/nginx/install_nginx_config.sh`](../deploy/nginx/install_nginx_config.sh).
> Both the `assetlinks.json` content-type override and the
> `/oauth/callback` bridge route are already in that conf.

The deployment is a single push of the latest commit to prod:

1. Publish the latest web build so `web/.well-known/assetlinks.json`
   and `web/oauth/callback/index.html` land in `/var/www/rodnya-site`.
2. Re-run `deploy/nginx/install_nginx_config.sh` on the host so the
   server blocks pick up any updates to `rodnya.conf` (cache headers,
   SPA fallback, etc.). Idempotent — safe to run on every release.
3. Confirm via:

   ```
   curl -fsS https://rodnya-tree.ru/.well-known/assetlinks.json | head
   curl -fsSI https://rodnya-tree.ru/.well-known/assetlinks.json \
     | grep -i content-type
   ```

   Headers must show `application/json` (no charset suffix).

The verified-https filter ALREADY protects against spoofed inbound
links from email/SMS that happen to match `rodnya-tree.ru/oauth/...`
— the OS routes those to the app instead of the browser regardless of
verification status — but full autoVerify is what closes the OAuth
deep-link spoofing hole during the auth handshake itself.

---

## 1. assetlinks.json content

Serve **exactly this JSON** at:

```
https://rodnya-tree.ru/.well-known/assetlinks.json
```

with `Content-Type: application/json` (no `charset` suffix is fine but case
must match).

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.ahjkuio.rodnya_family_app",
      "sha256_cert_fingerprints": [
        "14:A2:2A:B7:9F:03:F9:49:A3:23:AE:A6:68:2D:67:34:E3:A1:68:F4:C6:EE:BC:EB:37:E3:E3:85:D0:F5:D2:AC"
      ]
    }
  }
]
```

The fingerprint above is the SHA-256 of the **release** keystore at
`android/KEYS/my-release-key.jks`, alias `my-key-alias`. To re-derive it:

```
keytool -list -v \
  -keystore android/KEYS/my-release-key.jks \
  -alias my-key-alias
```

If you ever rotate the keystore (new app version on a different signing key),
ADD the new fingerprint to the array — DO NOT remove the old one until every
shipped install has been re-signed via Play Integrity / RuStore upgrades.

The dev flavor uses `applicationIdSuffix .dev`, which gives it a different
package name (`com.ahjkuio.rodnya_family_app.dev`). If you ever want verified
links to work on dev builds too, append a second JSON object with the dev
package name + the dev keystore fingerprint.

## 2. Verifying the manifest is correct

Once `assetlinks.json` is live, you can pre-flight-check from a terminal:

```
adb shell pm verify-app-links --re-verify com.ahjkuio.rodnya_family_app
adb shell pm get-app-links com.ahjkuio.rodnya_family_app
```

The output should list `rodnya-tree.ru` with state `verified`.

You can also use Google's tool:
https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://rodnya-tree.ru&relation=delegate_permission/common.handle_all_urls

A 200 response with our package + fingerprint means the OS will trust the
filter on next install / update.

## 3. After step 1 lands — switching finalRedirect

Once verification is green, edit
`lib/services/custom_api_auth_service.dart`:

```dart
static const String _mobileOauthCallback = 'rodnya://oauth/callback';
```

to:

```dart
static const String _mobileOauthCallback =
    'https://rodnya-tree.ru/oauth/callback';
```

AND ensure the marketing site at `rodnya-tree.ru` has a route at
`/oauth/callback` that:

* Accepts arbitrary query parameters (the OAuth code lives in
  `?xxxAuthCode=...`).
* Renders a small HTML page that does:
  * `<meta http-equiv="refresh" content="0; url=rodnya://oauth/callback?<same query>">`
  * As a fallback, a button "Открыть в приложении Родня" that links to
    the same `rodnya://` URI.
  * Optional Play / RuStore install link for users who don't have the
    app installed.

That guarantees the verified-https flow works on installs WITH verified
links AND falls back gracefully on devices that don't have verified
links yet (Android <12 without the new manifest, or pre-`assetlinks.json`
installs that haven't re-verified).

## 4. Testing

Cold-launch test (with verified links live):

```
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://rodnya-tree.ru/oauth/callback?test=1" \
  com.ahjkuio.rodnya_family_app
```

Expected: Родня opens the auth screen. No chooser dialog appears even if
another app (Chrome / Firefox / something else) also handles `https://`.

If the chooser DOES appear, verification has not happened yet. Re-run
`pm verify-app-links --re-verify` and check the JSON file's
`Content-Type` header.
