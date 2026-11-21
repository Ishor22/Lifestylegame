# Android release setup (iPhone only, one-time)

The APK is published by `.github/workflows/android-release.yml`. It publishes **only** when the four
signing secrets exist. Until then it runs tests and a debug build and publishes nothing.

Stable download link (newest published APK):
https://github.com/Ishor22/Lifestylegame/releases/latest/download/my-life-business-tycoon.apk

Android only lets an update replace an installed app if it is signed with the **same key**.

Three workflows handle the key:

| Workflow | Purpose | Can create a key? |
|---|---|---|
| `Android signing setup (one-time)` | Creates the key once and the encrypted backup | Yes, only if no signing secret exists |
| `Android signing restore` | Restores the **same** key from an encrypted backup | Never |
| `Android APK` (release) | Builds and publishes the signed APK | Never |

## Who can see what

- The repository is **public**. Anyone can read the code and the workflow files.
- The **backup** is a workflow artifact. Downloading it needs a GitHub sign-in. Anyone signed in to GitHub
  may be able to download it, not only repository members. It is encrypted, so it is useless without the
  passphrase, but treat it as sensitive.
- The **four secrets** can be read only by workflows. Nobody can view their values afterwards, including you.
- Workflow logs never contain passwords, tokens or key material.

## How the backup is protected

- AES-256-GCM encryption: any change to the file is detected, and a wrong passphrase is rejected.
- The key is derived from the passphrase with scrypt, so guessing is slow.
- Before any secret is saved, the backup is restored into a scratch folder and checked against the
  original key.

## Step 1: Create a passphrase for the backup (on iPhone)

1. Open your password manager (Apple Passwords, 1Password, etc.).
2. Create a new password with **at least 20 random characters**.
3. Name it `My Life Android signing backup`. Do not reuse another password.

## Step 2: Create a temporary GitHub token (on iPhone)

1. Open Safari, go to github.com, and sign in.
2. Tap your **account picture** (top right) → **Settings**.
3. Tap **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
4. **Token name:** `Android signing setup`. **Expiration:** 7 days.
5. **Repository access:** **Only select repositories** → `Lifestylegame`.
6. **Permissions** → **Repository permissions** → **Secrets** → **Read and write**.
7. Tap **Generate token**. Save it in your password manager now. You will not see it again.

## Step 3: Save two repository secrets (on iPhone)

Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Name | Value |
|---|---|
| `BACKUP_PASSPHRASE` | the password from Step 1 |
| `ANDROID_SETUP_TOKEN` | the token from Step 2 |

## Step 4: Run the one-time key setup (on iPhone)

1. **Actions** tab → **Android signing setup (one-time)** → **Run workflow**.
2. Branch: `claude/upbeat-hamilton-74kh8x`.
3. Type exactly `CREATE-ANDROID-KEY` in the confirm box, then tap **Run workflow**.
4. Wait for the green check. Note the **run ID** in the page address (the digits after `/runs/`).

The workflow stops before creating anything if **any** of these exists: `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. In that case, no key is created
and nothing changes.

## Step 5: Clean up (on iPhone)

1. github.com → **Settings** → **Developer settings** → **Fine-grained tokens** → **Android signing setup** → **Delete**.
2. Repository → **Settings** → **Secrets and variables** → **Actions** → `ANDROID_SETUP_TOKEN` → **Remove secret**.

## Step 6: Keep a copy of the backup

1. On the run page, scroll to **Artifacts** → download `my-life-android-signing-backup-encrypted`.
2. Keep the `.enc` file in iCloud Drive **together with** the passphrase from Step 1, in a different place
   from the password itself.
3. The artifact expires after 90 days. Keep your own copy.

## If the setup run fails partway through

Do **not** run the setup workflow again. Instead:

1. Create a new temporary token (repeat Step 2), and save it as `ANDROID_SETUP_TOKEN` (Step 3).
2. Go to **Actions** → **Android signing restore** → **Run workflow**.
3. Type `RESTORE-SAME-KEY` and enter the **run ID** from Step 4 in **setup_run_id**.
4. Tap **Run workflow**. The workflow restores the same key and writes all four secrets.
5. Delete the token again (Step 5).

Restore never creates a new key. If the restored certificate does not match the fingerprint recorded at
creation, it stops and changes nothing.

## Step 7: Publish the APK

Once the setup or restore run is green, run **Actions** → **Android APK** → **Run workflow**, or push to the branch.
The release job builds a signed APK and publishes it as a Release. The stable link above then works.

## Rules

- Never commit `.jks`, `.p12`, `.keystore`, `key.properties`, `.enc` backups or secret values.
- Never create a new key for an existing app. Always use the same one.
- If the key and every backup are lost, installed copies cannot be updated, and users must uninstall first.
