# Android release setup (iPhone only, one-time)

The APK is published by `.github/workflows/android-release.yml`. It publishes **only** when the four
signing secrets exist. Until then it runs tests and a debug build and publishes nothing.

Stable download link (newest published APK):
https://github.com/Ishor22/Lifestylegame/releases/latest/download/my-life-business-tycoon.apk

Android only lets an update replace an installed app if it is signed with the **same key**. The key
is created once by `.github/workflows/android-keystore-setup.yml`, which refuses to run again once the
secrets exist, so it can never overwrite the key.

## Before you start: who can see what

- The repository is **public**. Anyone can read the code and the workflow files.
- The **backup** is a workflow artifact. Downloading it needs a GitHub sign-in. Anyone signed in to GitHub
  can potentially download it, not only repository members. It is useless without the backup passphrase,
  but treat it as sensitive.
- The **secrets** can be read only by the workflows themselves. Nobody can view their values after saving,
  including you. Only the workflow can use them.
- Workflow logs never contain the passwords or key file.

## Step 1: Create a passphrase for the backup (on iPhone)

1. Open your password manager (Apple Passwords, 1Password, etc.).
2. Create a new password with **at least 20 random characters**.
3. Name it `My Life Android signing backup`. Do not reuse another password.

## Step 2: Create a temporary GitHub token (on iPhone)

This token lets the workflow save the four secrets. You delete it at the end.

1. Open Safari and go to github.com, then sign in.
2. Tap the **account picture** (top right) → **Settings**.
3. Scroll down and tap **Developer settings** → **Personal access tokens** → **Fine-grained tokens**.
4. Tap **Generate new token**.
5. **Token name:** `Android signing setup`. **Expiration:** 7 days.
6. **Repository access:** tap **Only select repositories** → choose `Lifestylegame`.
7. **Permissions** → **Repository permissions** → **Secrets** → set **Read and write**.
8. Tap **Generate token**. Copy the token and save it in your password manager now. You will not see it again.

## Step 3: Save the two secrets (on iPhone)

Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Name | Value |
|---|---|
| `BACKUP_PASSPHRASE` | the password from Step 1 |
| `ANDROID_SETUP_TOKEN` | the token from Step 2 |

## Step 4: Run the one-time key setup (on iPhone)

1. Go to the **Actions** tab → **Android signing setup (one-time)**.
2. Tap **Run workflow**. Make sure the branch is `claude/upbeat-hamilton-74kh8x`.
3. In **Type CREATE-ANDROID-KEY to confirm**, type exactly `CREATE-ANDROID-KEY`.
4. Tap **Run workflow** and wait for the green check (about 1–2 minutes).
5. Open the run. In **Summary** you will see the certificate fingerprint. Save it with the backup.

If the run fails, open its log. The messages never show secret values. The most common causes:
- "A signing key is already configured": the key already exists. Do **not** run it again.
- "ANDROID_SETUP_TOKEN is missing" or "BACKUP_PASSPHRASE is missing": check the secret names in Step 3.

## Step 5: Clean up (on iPhone)

1. Go to github.com → **Settings** → **Developer settings** → **Fine-grained tokens**.
2. Tap **Android signing setup** → **Delete**.
3. Go to the repository → **Settings** → **Secrets and variables** → **Actions** → tap `ANDROID_SETUP_TOKEN` → **Remove secret**.

## Step 6: Keep a copy of the backup

1. Go to **Actions** → the **Android signing setup (one-time)** run → scroll to **Artifacts**.
2. Tap `my-life-android-signing-backup-encrypted` to download it (a zip containing one `.enc` file).
3. Keep that file in iCloud Drive or another private place, together with the passphrase from Step 1.
4. The artifact expires after 90 days, so keep your own copy.

To restore the key later you need the `.enc` file and the passphrase. **No restore script exists yet.**
If you ever need to restore, ask for one to be added. Do not try to decrypt it by hand.

## Step 7: Publish the APK

After the setup run is green, run **Actions** → **Android APK** → **Run workflow**, or push to the branch.
If the signing secrets are set, the release job builds a signed APK and publishes it as a Release. The
stable link above then works.

## Rules

- Never commit `.jks`, `.p12`, `.keystore`, `key.properties`, or secret values.
- Never create a new key. Always use the same one.
- If the key is lost, installed copies cannot be updated and users must uninstall first.
