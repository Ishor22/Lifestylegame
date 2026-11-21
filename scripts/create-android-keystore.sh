#!/usr/bin/env bash
# One-time: creates the Android release signing key for My Life: Business Tycoon.
# Run it ONCE, in a trusted terminal (e.g. a GitHub Codespace). It writes files
# OUTSIDE the repository. Never commit or share the output.
set -euo pipefail

OUT_DIR="${HOME}/android-release-keystore"
KEYSTORE="${OUT_DIR}/my-life-business-tycoon-release.jks"
ALIAS="upload"

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install Java first: sudo apt-get install -y openjdk-17-jdk-headless" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

if [ -e "${KEYSTORE}" ]; then
  echo "A keystore already exists at ${KEYSTORE}. Not overwriting it." >&2
  echo "Overwriting would break updates for installed copies of the app." >&2
  exit 1
fi

# Letters and digits only, so the passwords are safe to paste into GitHub.
STORE_PASS="$(openssl rand -hex 24)"

keytool -genkeypair \
  -keystore "${KEYSTORE}" \
  -storetype JKS \
  -alias "${ALIAS}" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "${STORE_PASS}" -keypass "${STORE_PASS}" \
  -dname "CN=My Life Business Tycoon, OU=Mobile, O=Lifestylegame, C=US" \
  -noprompt

base64 -w0 "${KEYSTORE}" > "${OUT_DIR}/keystore-base64.txt"

cat > "${OUT_DIR}/github-secrets.txt" <<EOF
Add these 4 secrets in GitHub:
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret

ANDROID_KEYSTORE_BASE64  = contents of keystore-base64.txt
ANDROID_KEYSTORE_PASSWORD = ${STORE_PASS}
ANDROID_KEY_ALIAS        = ${ALIAS}
ANDROID_KEY_PASSWORD     = ${STORE_PASS}
EOF
chmod 600 "${OUT_DIR}/keystore-base64.txt" "${OUT_DIR}/github-secrets.txt" "${KEYSTORE}"

echo ""
echo "Done. Files created in: ${OUT_DIR}"
echo "  1. my-life-business-tycoon-release.jks  <- BACK THIS UP (copy it somewhere safe, offline)"
echo "  2. keystore-base64.txt                   <- value for ANDROID_KEYSTORE_BASE64"
echo "  3. github-secrets.txt                    <- the other three values"
echo ""
echo "Losing the keystore or its passwords means existing installs can never be updated."
echo "Delete github-secrets.txt and keystore-base64.txt after adding the secrets to GitHub."
