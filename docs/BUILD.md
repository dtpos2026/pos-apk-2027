# Building the APK

## Where the APK comes from
The APK is built by GitHub Actions (`.github/workflows/build-apk.yml`) on every push that touches `app/`. The runner has the
Android SDK; the authoring container used for development does not. After a green run:

- `releases/dt-food-pos-latest.apk` (and a versioned copy) is committed to the repository, with its SHA-256.
- The APK and the Play Store bundle (AAB) are also attached to the run as an artifact (`dt-food-pos-android`).

Install: copy the APK to the phone, allow "install unknown apps", open it.

## Signing
Without secrets the APK is signed with the **debug** key: good for installing and testing, not for the Play Store, and a
phone will refuse to update it if you later switch to a real key (uninstall first).

Create a real key once and keep it safe (lose it and you can never update the Play Store app):

```sh
keytool -genkeypair -v -keystore dt-food-pos.keystore -alias dtfoodpos -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 dt-food-pos.keystore    # paste into the secret below
```

Repository secrets (Settings, Secrets and variables, Actions): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. Never commit the keystore or passwords.

## Local build (needs the Android SDK)
```sh
cd app && flutter pub get && flutter build apk --release
```
