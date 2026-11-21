#!/usr/bin/env bash
# Restores the SAME signing key from the encrypted backup text. Never generates a key.
#
# The backup text is supplied in the environment variable SIGNING_BACKUP (from the repository
# secret ANDROID_SIGNING_BACKUP), so the original GitHub artifact is NOT needed.
#
# Overwrite policy, checked BEFORE anything is decrypted or written:
#   0 of the 4 secrets exist  -> restore proceeds.
#   1 to 3 exist              -> partial recovery; needs PARTIAL_CONFIRM=COMPLETE-PARTIAL-RESTORE.
#   all 4 exist               -> refused unless REPLACE_CONFIRM=REPLACE-COMPLETE-SIGNING-KEY.
#
# Then: decrypt and authenticate the backup, check the restored keystore unlocks, check its
# certificate SHA-256 against the fingerprint recorded at creation, and only then write the secrets.
#
# Required environment: GH_TOKEN (temporary token with secrets write), REPO, BACKUP_PASSPHRASE,
# SIGNING_BACKUP, WORK (scratch folder, always deleted on exit). Optional: PARTIAL_CONFIRM, REPLACE_CONFIRM.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${HERE}/common.sh"

require_env GH_TOKEN REPO BACKUP_PASSPHRASE SIGNING_BACKUP WORK
export GH_TOKEN
trap 'rm -rf "${WORK}"' EXIT
mkdir -m 700 "${WORK}"

# 1. Inspect the current secrets (names only) and apply the overwrite policy.
read_existing_signing_secrets
EXISTING_COUNT="$(wc -w <<<"${EXISTING_SIGNING_SECRETS}" | tr -d ' ')"
if [ -n "${EXISTING_SIGNING_SECRETS}" ]; then
  MISSING=""
  for name in ${SIGNING_SECRET_NAMES}; do
    case " ${EXISTING_SIGNING_SECRETS} " in
      *" ${name} "*) ;;
      *) MISSING="${MISSING}${name} " ;;
    esac
  done
fi

if [ "${EXISTING_COUNT}" = "0" ]; then
  echo "No signing secrets exist yet. Restore can proceed."
elif [ "${EXISTING_COUNT}" -lt 4 ]; then
  echo "PARTIAL STATE: these signing secrets already exist: ${EXISTING_SIGNING_SECRETS}"
  echo "Not yet saved: ${MISSING% }"
  echo "An earlier setup or restore stopped part way. Restoring writes the same key's values, which"
  echo "completes the set. The existing values cannot be inspected, so confirm this backup is yours."
  if [ "${PARTIAL_CONFIRM:-}" != "COMPLETE-PARTIAL-RESTORE" ]; then
    die "Partial recovery needs explicit confirmation: type COMPLETE-PARTIAL-RESTORE in the workflow input partial_confirm. Nothing was changed."
  fi
else
  echo "ALL FOUR signing secrets already exist. A restore will not overwrite them by default."
  if [ "${REPLACE_CONFIRM:-}" != "REPLACE-COMPLETE-SIGNING-KEY" ]; then
    die "Refusing to overwrite a complete signing identity. To replace it, type REPLACE-COMPLETE-SIGNING-KEY in the workflow input replace_confirm. Nothing was changed."
  fi
  echo "::warning::Replacing a complete signing identity. If the app is already published with a different key, replacing the key can prevent future updates for installed copies. Only continue if this backup holds the key that signed the published app."
fi

# 2. Authenticate and decrypt. A wrong passphrase, a modified backup or a damaged paste stops here.
printf '%s\n' "${SIGNING_BACKUP}" > "${WORK}/backup.txt"
python3 "${HERE}/backup_crypto.py" unpack --in "${WORK}/backup.txt" --dir "${WORK}/restored"
rm -f "${WORK}/backup.txt"

# 3. Check the restored key against the fingerprint recorded when it was created.
EXPECTED_FP="$(cat "${WORK}/restored/expected-sha256.txt")"
RESTORE_PW="$(grep -m1 '^ANDROID_KEYSTORE_PASSWORD=' "${WORK}/restored/credentials.env" | cut -d= -f2-)"
RESTORE_ALIAS="$(grep -m1 '^ANDROID_KEY_ALIAS=' "${WORK}/restored/credentials.env" | cut -d= -f2-)"
export RESTORE_PW
ACTUAL_FP="$(keystore_fingerprint "${WORK}/restored/mylife-upload.p12" "${RESTORE_ALIAS}" RESTORE_PW)"
[ -n "${ACTUAL_FP}" ] || die "restored keystore could not be read. Nothing was changed."
[ "${ACTUAL_FP}" = "${EXPECTED_FP}" ] || die "restored certificate does not match the backup record. Nothing was changed."

# 4. Write the same key's four secrets.
save_signing_secrets "${WORK}/restored/credentials.env"

echo "Restored the existing key. Certificate SHA-256: ${ACTUAL_FP}"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Signing key restored"
    echo ""
    echo "Certificate SHA-256: \`${ACTUAL_FP}\` (matches the backup record)."
    echo ""
    echo "Delete the ANDROID_SIGNING_BACKUP secret now. It is no longer needed."
  } >> "${GITHUB_STEP_SUMMARY}"
fi
