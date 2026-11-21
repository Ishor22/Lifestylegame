#!/usr/bin/env bash
# Shared helpers for the Android signing scripts. Sourced, not executed.
# Rules: never print passwords, key material, backup text or tokens. Only secret NAMES and fingerprints are printed.

SIGNING_SECRET_NAMES="ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD"
KEY_ALIAS="upload"

die() {
  echo "::error::$*" >&2
  exit 1
}

mask_value() {
  # Only inside GitHub Actions, so the value is hidden in logs. Never echoed locally.
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::add-mask::$1"
  fi
}

require_env() {
  local name
  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      die "required variable ${name} is not set"
    fi
  done
}

# Sets EXISTING_SIGNING_SECRETS to the space-separated names (of the four) that exist.
# Stops the script if the list cannot be read, so an unreadable list is never treated as "none exist".
read_existing_signing_secrets() {
  local listed name
  if ! listed="$(gh api "repos/${REPO}/actions/secrets" --paginate --jq '.secrets[].name' 2>/dev/null)"; then
    die "Could not list repository secrets. Stopping. Nothing was changed."
  fi
  EXISTING_SIGNING_SECRETS=""
  for name in ${SIGNING_SECRET_NAMES}; do
    if grep -qx "${name}" <<<"${listed}"; then
      EXISTING_SIGNING_SECRETS="${EXISTING_SIGNING_SECRETS}${name} "
    fi
  done
  EXISTING_SIGNING_SECRETS="${EXISTING_SIGNING_SECRETS% }"
}

# Setup mode: stops if ANY of the four signing secrets already exists.
check_no_existing_signing_secrets() {
  read_existing_signing_secrets
  if [ -n "${EXISTING_SIGNING_SECRETS}" ]; then
    die "Secret(s) already exist: ${EXISTING_SIGNING_SECRETS}. Stopping. No key was generated and no secret was changed. Use the restore workflow if you need to restore the existing key."
  fi
}

# Prints the SHA-256 certificate fingerprint of alias $2 in PKCS12 keystore $1.
# The keystore password is read from the environment variable named in $3.
keystore_fingerprint() {
  local keystore="$1" alias="$2" pw_var="$3"
  keytool -list -keystore "${keystore}" -storetype PKCS12 -alias "${alias}" \
      -storepass:env "${pw_var}" \
    | grep 'SHA-256' | sed 's/^.*: *//'
}

# Saves the four secrets from a credentials file, one at a time, stopping at the first failure.
# Values are sent through stdin, never on the command line.
save_signing_secrets() {
  local creds="$1" name value saved=0
  for name in ANDROID_KEY_ALIAS ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_PASSWORD ANDROID_KEYSTORE_BASE64; do
    value="$(grep -m1 "^${name}=" "${creds}" | cut -d= -f2-)"
    if [ -z "${value}" ]; then
      die "credentials file is missing ${name}. ${saved} of 4 secrets saved."
    fi
    if ! printf '%s' "${value}" | gh secret set "${name}" --repo "${REPO}" >/dev/null 2>&1; then
      die "Could not save ${name}. ${saved} of 4 secrets were saved. Do NOT run the setup workflow again. Run the restore workflow with the same backup text to finish safely."
    fi
    saved=$((saved + 1))
    echo "Saved secret ${name} (${saved} of 4)."
  done
}
