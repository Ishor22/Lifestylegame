# Android release setup (one-time)

The workflow `.github/workflows/android-release.yml` builds and publishes the Android APK.
It publishes a release only when the signing secrets below are set. Without them it still runs
tests and a debug build, but it does not publish anything.

Stable download link (always the newest published APK):
https://github.com/Ishor22/Lifestylegame/releases/latest/download/my-life-business-tycoon.apk

## Why this matters

Android only allows an update to replace an installed app if it is signed with the **same key**.
Create the key once, keep a backup, and reuse it forever.

## Step 1: Create the signing key (once)

Use a GitHub Codespace (works from a phone browser in desktop mode):

1. Open https://github.com/Ishor22/Lifestylegame, switch to branch `claude/upbeat-hamilton-74kh8x`.
2. Tap **Code** → **Codespaces** → **Create codespace on claude/upbeat-hamilton-74kh8x**.
3. In the terminal at the bottom, run:
   `bash scripts/create-android-keystore.sh`
4. It creates files in `~/android-release-keystore/`.
5. **Back up** `my-life-business-tycoon-release.jks` somewhere safe (cloud drive, not GitHub).

## Step 2: Add 4 GitHub secrets (once)

Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Secret name | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | full contents of `keystore-base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the `ANDROID_KEYSTORE_PASSWORD` line in `github-secrets.txt` |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the `ANDROID_KEY_PASSWORD` line in `github-secrets.txt` |

Then delete `keystore-base64.txt` and `github-secrets.txt` from the Codespace.

## Step 3: Publish

Run the workflow: **Actions** → **Android APK** → **Run workflow**, or push to the working branch.
The release appears under **Releases** and the stable link above starts working.

## Rules

- Never commit `.jks`, `.keystore`, `key.properties` or the secret values.
- Never create a new key for a later build. Always use the same key.
- Losing the key means existing installs cannot be updated; users would have to uninstall first.
