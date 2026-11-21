#!/usr/bin/env bash
# Restores the SAME signing key from the encrypted backup. Never generates a key.
#
# Steps: authenticate and decrypt the backup, check that the restored keystore unlocks with its
# passwords and that its certificate SHA-256 matches the fingerprint recorded when the key was
# created, then write the four secrets.
#
# Required environment: GH_TOKEN (temporary token with secrets write), REPO, BACKUP_PASSPHRASE,
# BACKUP_FILE (path to the downloaded .enc file), WORK (scratch folder, deleted on exit).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${HERE}/common.sh"

require_env GH_TOKEN REPO BACKUP_PASSPHRASE BACKUP_FILE WORK
export GH_TOKEN
trap 'rm -rf "${WORK}"' EXIT

[ -f "${BACKUP_FILE}" ] || die "backup file not found"
mkdir -m 700 "${WORK}"

# 1. Authenticate and decrypt. A wrong passphrase or a modified file stops here (exit code 2).
python3 "${HERE}/backup_crypto.py" unpack --in "${BACKUP_FILE}" --dir "${WORK}/restored"

# 2. Check the restored key. The stored fingerprint is compared with the keystore's real fingerprint.
EXPECTED_FP="$(cat "${WORK}/restored/expected-sha256.txt")"
RESTORE_PW="$(grep -m1 '^ANDROID_KEYSTORE_PASSWORD=' "${WORK}/restored/credentials.env" | cut -d= -f2-)"
RESTORE_ALIAS="$(grep -m1 '^ANDROID_KEY_ALIAS=' "${WORK}/restored/credentials.env" | cut -d= -f2-)"
export RESTORE_PW
ACTUAL_FP="$(keystore_fingerprint "${WORK}/restored/mylife-upload.p12" "${RESTORE_ALIAS}" RESTORE_PW)"
[ -n "${ACTUAL_FP}" ] || die "restored keystore could not be read"
[ "${ACTUAL_FP}" = "${EXPECTED_FP}" ] || die "restored certificate does not match the backup record. Nothing was changed."

# 3. Write the same key's secrets. Restore is the only path that may overwrite them.
save_signing_secrets "${WORK}/restored/credentials.env"

echo "Restored the existing key. Certificate SHA-256: ${ACTUAL_FP}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Signing key restored"
    echo ""
    echo "Certificate SHA-256: \`${ACTUAL_FP}\` (matches the backup record)."
  } >> "${GITHUB_STEP_SUMMARY}"
fi
