#!/usr/bin/env bash
# One-time creation of the Android release signing key.
#
#   setup_key.sh backup   Stops if any signing secret exists. Otherwise creates a key, creates an
#                         authenticated encrypted backup in $OUT, verifies it by restoring it into a
#                         scratch folder, and leaves the unencrypted credentials in $WORK for the save step.
#   setup_key.sh save     Saves the four secrets from $WORK/credentials.env. Run only after the backup
#                         artifact has been uploaded. Stops if any secret already exists.
#
# Required environment: GH_TOKEN (temporary token with secrets write), REPO, BACKUP_PASSPHRASE,
# WORK (scratch folder, deleted on exit), OUT (backup output folder; backup mode only).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${HERE}/common.sh"

MODE="${1:-}"
BACKUP_NAME="my-life-android-signing-backup.txt"
KEYSTORE_NAME="mylife-upload.p12"

case "${MODE}" in
  backup)
    require_env GH_TOKEN REPO BACKUP_PASSPHRASE WORK OUT
    if [ "${#BACKUP_PASSPHRASE}" -lt 16 ]; then
      die "BACKUP_PASSPHRASE is missing or shorter than 16 characters"
    fi
    export GH_TOKEN

    # 1. Refuse to continue if any signing secret already exists. Never replace a key.
    check_no_existing_signing_secrets

    # Remove plaintext key material if this phase fails. Keep it on success for the save phase.
    mkdir -m 700 "${WORK}"
    mkdir -m 700 -p "${OUT}"
    trap 'status=$?; if [ "${status}" -ne 0 ]; then rm -rf "${WORK}"; fi' EXIT

    # 2. Create the key. Passwords are random, masked in logs and never printed.
    STORE_PASS="$(openssl rand -hex 24)"
    mask_value "${STORE_PASS}"
    export SIGN_PW="${STORE_PASS}"
    KEYSTORE="${WORK}/${KEYSTORE_NAME}"
    keytool -genkeypair \
      -keystore "${KEYSTORE}" -storetype PKCS12 \
      -alias "${KEY_ALIAS}" -keyalg RSA -keysize 2048 -validity 10000 \
      -storepass:env SIGN_PW -keypass:env SIGN_PW \
      -dname "CN=My Life Business Tycoon, OU=Mobile, O=Lifestylegame, C=US" \
      -noprompt >/dev/null 2>&1
    FINGERPRINT="$(keystore_fingerprint "${KEYSTORE}" "${KEY_ALIAS}" SIGN_PW)"
    [ -n "${FINGERPRINT}" ] || die "could not read the certificate fingerprint"

    # 3. Authenticated encrypted backup (AES-256-GCM, scrypt key derivation).
    python3 "${HERE}/backup_crypto.py" pack \
      --p12 "${KEYSTORE}" --alias "${KEY_ALIAS}" --fingerprint "${FINGERPRINT}" \
      --store-pass-env SIGN_PW --out "${OUT}/${BACKUP_NAME}"

    # 4. Credentials for the save step (plaintext, stays only in WORK).
    P12_B64="$(base64 -w0 "${KEYSTORE}")"
    mask_value "${P12_B64}"
    {
      echo "ANDROID_KEYSTORE_BASE64=${P12_B64}"
      echo "ANDROID_KEYSTORE_PASSWORD=${STORE_PASS}"
      echo "ANDROID_KEY_PASSWORD=${STORE_PASS}"
      echo "ANDROID_KEY_ALIAS=${KEY_ALIAS}"
    } > "${WORK}/credentials.env"
    chmod 600 "${WORK}/credentials.env"

    # 5. Verify: restore the backup into a scratch folder and compare it with the original key.
    python3 "${HERE}/backup_crypto.py" unpack --in "${OUT}/${BACKUP_NAME}" --dir "${WORK}/verify"
    cmp -s "${KEYSTORE}" "${WORK}/verify/${KEYSTORE_NAME}" \
      || die "backup verification failed: restored keystore differs from the original"
    VERIFY_PW="$(grep -m1 '^ANDROID_KEYSTORE_PASSWORD=' "${WORK}/verify/credentials.env" | cut -d= -f2-)"
    export VERIFY_PW
    RESTORED_FP="$(keystore_fingerprint "${WORK}/verify/${KEYSTORE_NAME}" "${KEY_ALIAS}" VERIFY_PW)"
    [ "${RESTORED_FP}" = "${FINGERPRINT}" ] || die "backup verification failed: fingerprint mismatch"
    rm -rf "${WORK}/verify"

    echo "Key created and backup verified. Certificate SHA-256: ${FINGERPRINT}"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "### Signing key created"
        echo ""
        echo "Certificate SHA-256: \`${FINGERPRINT}\`"
        echo ""
        echo "Encrypted backup verified. Next: the backup is uploaded as an artifact, then the secrets are saved."
        echo ""
        echo "Save the artifact's text file to iCloud Drive. Restore needs only that file and the passphrase."
      } >> "${GITHUB_STEP_SUMMARY}"
    fi
    ;;

  save)
    require_env GH_TOKEN REPO WORK
    export GH_TOKEN
    trap 'rm -rf "${WORK}"' EXIT
    [ -f "${WORK}/credentials.env" ] || die "credentials file not found; run the backup phase first"
    check_no_existing_signing_secrets
    save_signing_secrets "${WORK}/credentials.env"
    echo "All four signing secrets saved."
    ;;

  *)
    echo "usage: setup_key.sh backup|save" >&2
    exit 64
    ;;
esac
