# Android release setup (iPhone only)

The APK is published by `.github/workflows/android-release.yml`. It publishes **only** when the four
signing secrets exist. Until then it runs tests and a debug build and publishes nothing.

Stable download link (newest published APK):
https://github.com/Ishor22/Lifestylegame/releases/latest/download/my-life-business-tycoon.apk

Android only lets an update replace an installed app if it is signed with the **same key**.

| Workflow | Purpose | Can create a key? |
|---|---|---|
| `Android signing setup (one-time)` | Creates the key once, plus an encrypted backup | Yes, only if no signing secret exists |
| `Android signing restore` | Restores the **same** key from your saved backup | Never |
| `Android signing self-test (no secrets)` | Tests the crypto tools on a GitHub runner | Never (uses no secrets) |
| `Android APK` (release) | Builds and publishes the signed APK | Never |

## Who can see what

- The repository is **public**. Anyone can read the code and the workflow files.
- The backup text file is encrypted (AES-256-GCM). Without the passphrase it is useless. The passphrase
  lives only in your password manager.
- The **GitHub artifact** of the setup run expires after 90 days. Anyone **signed in to GitHub** may be able
  to download it while it exists. Your iCloud copy is what you rely on long-term.
- The secrets can be read only by workflows. Nobody can view their values afterwards, including you.
- Workflow logs never contain passwords, tokens, passphrases or backup text.

## What the backup is

A short text file named `my-life-android-signing-backup.txt`, with a BEGIN line, base64 text and an END line.
It contains the encrypted signing key. It is safe to keep in iCloud Drive, **together with the passphrase
kept separately** in your password manager. Never store the passphrase in the same note as the backup.

---

## Part A: One-time key setup

### A1. Create the backup passphrase (on iPhone)
1. Open your password manager. Create a password with **at least 20 random characters**.
2. Name it `My Life Android signing backup`. Do not reuse another password.

### A2. Create a temporary GitHub token (on iPhone)
1. Safari → github.com → sign in → tap your **account picture** → **Settings**.
2. **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**.
3. **Token name:** `Android signing setup`. **Expiration:** 7 days.
4. **Repository access:** **Only select repositories** → `Lifestylegame`.
5. **Permissions** → **Repository permissions** → **Secrets** → **Read and write**.
6. Tap **Generate token**. Save it in your password manager now. You will not see it again.

### A3. Save two repository secrets (on iPhone)
Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Name | Value |
|---|---|
| `BACKUP_PASSPHRASE` | the password from A1 |
| `ANDROID_SETUP_TOKEN` | the token from A2 |

### A4. Run the setup (on iPhone)
1. **Actions** → **Android signing setup (one-time)** → **Run workflow**.
2. Branch: `claude/upbeat-hamilton-74kh8x`. In the confirm box, type `CREATE-ANDROID-KEY`. Tap **Run workflow**.
3. Wait for the green check. Note the **run ID** in the page address (the digits after `/runs/`).

The setup refuses to run, and creates nothing, if **any** of these four secrets already exists:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

### A5. Save the backup to iCloud Drive (on iPhone) — do this now
1. On the run page, scroll to **Artifacts**. Tap **my-life-android-signing-backup**. It downloads as a zip.
2. Open the **Files** app → **Downloads** → tap the zip. It unzips into a folder.
3. Open the folder and move `my-life-android-signing-backup.txt` into **iCloud Drive** (long-press → **Move To** →
   **iCloud Drive** → create a folder called `Lifestyle Backups`).
4. Open that file once to check it starts with `-----BEGIN MYLIFE SIGNING BACKUP v1-----`.
5. Write down the **certificate SHA-256** shown in the run summary, next to the file. You will compare it after a restore.

### A6. Clean up (on iPhone)
1. github.com → **Settings** → **Developer settings** → **Fine-grained tokens** → **Android signing setup** → **Delete**.
2. Repository → **Settings** → **Secrets and variables** → **Actions** → `ANDROID_SETUP_TOKEN` → **Remove secret**.

Keep `BACKUP_PASSPHRASE` for restores.

---

## Part B: Restoring the same key (on iPhone)

Use this if setup stopped part way, if the four secrets were lost, or to recover on a new repository setup.
You do **not** need the GitHub artifact. The iCloud file is enough.

### B1. Copy the backup text (on iPhone)
1. Files → **iCloud Drive** → `Lifestyle Backups` → tap `my-life-android-signing-backup.txt`.
2. Tap and hold the text, tap **Select All**, then **Copy**. If Select All is not offered, tap the **Share** button,
   choose **Notes**, open the note, then tap and hold → **Select All** → **Copy**. Delete that note afterwards.

### B2. Put the backup into a temporary secret (on iPhone)
1. Create a new token exactly as in A2 (name `Android signing restore`, 7 days, Secrets: Read and write).
2. Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
3. **Name:** `ANDROID_SIGNING_BACKUP`. **Secret:** paste the copied text. Tap **Add secret**.
4. Update `ANDROID_SETUP_TOKEN` with the new token (tap the secret → **Update**). Keep `BACKUP_PASSPHRASE`.

### B3. Run the restore (on iPhone)
1. **Actions** → **Android signing restore** → **Run workflow**. Branch: `claude/upbeat-hamilton-74kh8x`.
2. **confirm:** `RESTORE-SAME-KEY`.
3. Leave the other two boxes empty **unless the run asks for them**:
   - **partial_confirm** = `COMPLETE-PARTIAL-RESTORE` if the run says 1 to 3 secrets already exist.
     It means an earlier attempt stopped part way. Restoring the same key completes the set.
   - **replace_confirm** = `REPLACE-COMPLETE-SIGNING-KEY` only if the run says **all four** secrets exist. This **replaces
     a complete signing identity**. If the app is already published with a different key, replacing the key can
     **prevent future updates** for people who have installed it. Do this only if you are certain this backup holds
     the key that signed the published app.
4. Tap **Run workflow**. If the run stops with a message, read it. Nothing is changed when a run stops.

### B4. Check and clean up (on iPhone)
1. The green run's **Summary** shows the certificate SHA-256. Compare it with the value you wrote down in A5.
   If they differ, do not continue; tell me.
2. Delete the temporary secret `ANDROID_SIGNING_BACKUP`, and the token `ANDROID_SETUP_TOKEN` (github.com → Settings →
   Developer settings → Fine-grained tokens → Delete).

---

## Part C: Publish the APK

After a green setup or restore run, **Actions** → **Android APK** → **Run workflow**, or push to the branch.
The release job builds a signed APK and publishes it. The stable link above then works.

## Rules

- Never commit `.jks`, `.p12`, `.keystore`, `key.properties`, backup files or secret values.
- Never create a new key for an app that is already published. Always restore the same one.
- If the key and every backup are lost, installed copies cannot be updated, and users must uninstall first.
