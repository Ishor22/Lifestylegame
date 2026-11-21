#!/usr/bin/env bash
# Local tests for the Android signing scripts. No network, no real GitHub calls.
# A stub "gh" records what would be saved. A wrapper "python3" can simulate a crash.
# Usage: bash scripts/android-signing/tests/run_tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # scripts/android-signing
TESTBIN="${HERE}/tests/bin"
REAL_PYTHON="$(command -v python3)"
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT
chmod +x "${TESTBIN}/gh" "${TESTBIN}/python3"

GH_TOKEN_VALUE="test-token-do-not-print-7f3a9c"
PASS_OK="correct-horse-battery-42"
PASS_WRONG="wrong-horse-battery-42"
REPO_VALUE="owner/repo"
ENV_PATH="${TESTBIN}:${PATH}"

PASSED=0
FAILED=0
check() {
  local description="$1"; shift
  if "$@"; then
    echo "PASS: ${description}"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: ${description}"
    FAILED=$((FAILED + 1))
  fi
}

# Runs one setup phase in a clean environment. Arguments: mode case-name.
# Optional variables: EXIST, FAILSET, APIFAIL, FAILPACK, PASSPHRASE_USED.
run_setup() {
  local mode="$1" c="$2"
  mkdir -p "${ROOT}/stub-${c}"
  env -i PATH="${ENV_PATH}" HOME="${HOME}" REAL_PYTHON="${REAL_PYTHON}" \
    GH_TOKEN="${GH_TOKEN_VALUE}" REPO="${REPO_VALUE}" \
    BACKUP_PASSPHRASE="${PASSPHRASE_USED:-${PASS_OK}}" \
    WORK="${ROOT}/w-${c}" OUT="${ROOT}/o-${c}" STUB_DIR="${ROOT}/stub-${c}" \
    STUB_EXISTING="${EXIST:-}" STUB_FAIL_SET="${FAILSET:-}" STUB_API_FAIL="${APIFAIL:-0}" \
    FAIL_PACK="${FAILPACK:-0}" \
    bash "${HERE}/setup_key.sh" "${mode}" > "${ROOT}/log-${c}.txt" 2>&1
}

# Runs restore. Arguments: case-name backup-file passphrase.
run_restore() {
  local c="$1" file="$2" pass="$3"
  mkdir -p "${ROOT}/stub-${c}"
  env -i PATH="${ENV_PATH}" HOME="${HOME}" REAL_PYTHON="${REAL_PYTHON}" \
    GH_TOKEN="${GH_TOKEN_VALUE}" REPO="${REPO_VALUE}" \
    BACKUP_PASSPHRASE="${pass}" BACKUP_FILE="${file}" \
    WORK="${ROOT}/rw-${c}" STUB_DIR="${ROOT}/stub-${c}" \
    STUB_EXISTING="" STUB_FAIL_SET="" STUB_API_FAIL=0 \
    bash "${HERE}/restore_key.sh" > "${ROOT}/log-${c}.txt" 2>&1
}

# Prints the SHA-256 fingerprint of the key saved in a stub folder.
fingerprint_of_saved() {
  local dir="$1" tmp
  tmp="$(mktemp -d)"
  base64 -d "${dir}/saved-ANDROID_KEYSTORE_BASE64" > "${tmp}/k.p12"
  keytool -list -keystore "${tmp}/k.p12" -storetype PKCS12 \
    -alias "$(cat "${dir}/saved-ANDROID_KEY_ALIAS")" \
    -storepass "$(cat "${dir}/saved-ANDROID_KEYSTORE_PASSWORD")" 2>/dev/null \
    | grep 'SHA-256' | sed 's/^.*: *//'
  rm -rf "${tmp}"
}

fingerprint_in_log() { sed -n 's/.*Certificate SHA-256: *//p' "$1" | head -1; }

saved_count() { ls "$1"/saved-* 2>/dev/null | wc -l | tr -d ' '; }

has_no_saved() { [ "$(saved_count "$1")" = "0" ]; }

# ---------------------------------------------------------------------------
echo "== 1. First-time key generation, backup and save"
PASSPHRASE_USED="${PASS_OK}" EXIST="" run_setup backup first
check "backup phase exits 0" [ "$?" -eq 0 ]
ENC="${ROOT}/o-first/mylife-android-signing-backup.enc"
check "encrypted backup exists" [ -s "${ENC}" ]
check "backup starts with the MLBK magic bytes" [ "$(head -c 4 "${ENC}")" = "MLBK" ]
check "credentials kept only in the scratch folder for the save step" [ -f "${ROOT}/w-first/credentials.env" ]
FP="$(fingerprint_in_log "${ROOT}/log-first.txt")"
check "a certificate SHA-256 fingerprint was reported" [ -n "${FP}" ]

EXIST="" run_setup save first
check "save phase exits 0" [ "$?" -eq 0 ]
check "exactly four secrets were written" [ "$(saved_count "${ROOT}/stub-first")" = "4" ]
check "saved key fingerprint equals the reported fingerprint" \
  [ "$(fingerprint_of_saved "${ROOT}/stub-first")" = "${FP}" ]
check "scratch folder with plaintext key material is removed after save" [ ! -e "${ROOT}/w-first" ]

# ---------------------------------------------------------------------------
echo "== 2. Correct backup decryption restores the same key"
run_restore restore-ok "${ENC}" "${PASS_OK}"
check "restore exits 0 with the correct passphrase" [ "$?" -eq 0 ]
check "restored key fingerprint is identical to the original" \
  [ "$(fingerprint_of_saved "${ROOT}/stub-restore-ok")" = "${FP}" ]
check "restored secret values are byte-identical to the originals" bash -c "
  for n in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_PASSWORD ANDROID_KEY_ALIAS; do
    cmp -s '${ROOT}/stub-first/saved-'\$n '${ROOT}/stub-restore-ok/saved-'\$n || exit 1
  done"
check "restore scratch folder is removed" [ ! -e "${ROOT}/rw-restore-ok" ]

# ---------------------------------------------------------------------------
echo "== 3. Wrong passphrase is rejected"
run_restore restore-wrong "${ENC}" "${PASS_WRONG}"
check "restore with wrong passphrase exits non-zero" [ "$?" -ne 0 ]
check "error says authentication failed" grep -q "authentication failed" "${ROOT}/log-restore-wrong.txt"
check "no secrets written after a wrong passphrase" has_no_saved "${ROOT}/stub-restore-wrong"

# ---------------------------------------------------------------------------
echo "== 4. Modified or damaged backups are rejected"
python3 - "${ENC}" "${ROOT}" <<'PY'
import sys
src, root = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
def write(name, blob):
    open(f"{root}/{name}", "wb").write(blob)
for name, offset in [("tamper-body", 60), ("tamper-salt", 8), ("tamper-nonce", 25), ("tamper-tag", len(data) - 3)]:
    mutated = bytearray(data)
    mutated[offset] ^= 0x01
    write(name + ".enc", bytes(mutated))
write("truncated.enc", data[:40])
write("garbage.enc", b"this is not a backup at all, just text")
PY
for name in tamper-body tamper-salt tamper-nonce tamper-tag truncated garbage; do
  run_restore "tamper-${name}" "${ROOT}/${name}.enc" "${PASS_OK}"
  check "modified backup '${name}' is rejected" [ "$?" -ne 0 ]
  check "no secrets written for '${name}'" has_no_saved "${ROOT}/stub-tamper-${name}"
done

# ---------------------------------------------------------------------------
echo "== 5. Existing signing secrets prevent generation"
i=0
for existing in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  i=$((i + 1))
  EXIST="${existing}" run_setup backup "exist-${i}"
  check "backup refuses when ${existing} exists" [ "$?" -ne 0 ]
  check "refusal names ${existing} and says a key was not generated" \
    bash -c "grep -q '${existing} already exists' '${ROOT}/log-exist-${i}.txt' && grep -q 'No key was generated' '${ROOT}/log-exist-${i}.txt'"
  check "no backup file created when ${existing} exists" [ ! -e "${ROOT}/o-exist-${i}/mylife-android-signing-backup.enc" ]
  check "no scratch key material created when ${existing} exists" [ ! -e "${ROOT}/w-exist-${i}" ]
  check "no secret written when ${existing} exists" has_no_saved "${ROOT}/stub-exist-${i}"
done
APIFAIL=1 run_setup backup exist-api
check "backup refuses when the secret list cannot be read (fails closed)" [ "$?" -ne 0 ]
check "no backup created when the secret list cannot be read" [ ! -e "${ROOT}/o-exist-api/mylife-android-signing-backup.enc" ]
APIFAIL=0 EXIST="ANDROID_KEY_ALIAS" run_setup save exist-save
check "save phase also refuses when a signing secret exists" [ "$?" -ne 0 ]
check "save phase writes nothing when a signing secret exists" has_no_saved "${ROOT}/stub-exist-save"
PASSPHRASE_USED="short" run_setup backup short-pass
check "backup refuses a passphrase shorter than 16 characters" [ "$?" -ne 0 ]
check "no backup created with a short passphrase" [ ! -e "${ROOT}/o-short-pass/mylife-android-signing-backup.enc" ]

# ---------------------------------------------------------------------------
echo "== 6. Partial secret-save failure cannot cause a replacement key"
PASSPHRASE_USED="${PASS_OK}" EXIST="" FAILSET="" run_setup backup partial
check "backup for partial test exits 0" [ "$?" -eq 0 ]
PARTIAL_FP="$(fingerprint_in_log "${ROOT}/log-partial.txt")"
EXIST="" FAILSET="ANDROID_KEY_PASSWORD" run_setup save partial
check "save with a failing secret exits non-zero" [ "$?" -ne 0 ]
check "save reports the partial state and says not to rerun setup" \
  bash -c "grep -q '2 of 4 secrets were saved' '${ROOT}/log-partial.txt' && grep -q 'Do NOT run the setup workflow again' '${ROOT}/log-partial.txt'"
check "secrets are attempted in order and stop at the failure" bash -c "
  [ \"\$(cat '${ROOT}/stub-partial/calls.log')\" = \$'set ANDROID_KEY_ALIAS\nset ANDROID_KEYSTORE_PASSWORD\nset ANDROID_KEY_PASSWORD' ]"
check "the keystore secret was never written after the failure" [ ! -e "${ROOT}/stub-partial/saved-ANDROID_KEYSTORE_BASE64" ]
check "scratch folder removed after failed save" [ ! -e "${ROOT}/w-partial" ]

SAVED_BEFORE="$(cat "${ROOT}/stub-partial/saved-ANDROID_KEYSTORE_PASSWORD")"
PASSPHRASE_USED="${PASS_OK}" EXIST="ANDROID_KEY_ALIAS ANDROID_KEYSTORE_PASSWORD" run_setup backup partial-rerun
check "re-running setup after a partial save is refused" [ "$?" -ne 0 ]
check "the refused re-run created no new backup" [ ! -e "${ROOT}/o-partial-rerun/mylife-android-signing-backup.enc" ]
check "the refused re-run did not touch the saved password" \
  [ "$(cat "${ROOT}/stub-partial/saved-ANDROID_KEYSTORE_PASSWORD")" = "${SAVED_BEFORE}" ]

run_restore partial-recovery "${ROOT}/o-partial/mylife-android-signing-backup.enc" "${PASS_OK}"
check "restore recovers a partial save with exit 0" [ "$?" -eq 0 ]
check "recovery writes all four secrets" [ "$(saved_count "${ROOT}/stub-partial-recovery")" = "4" ]
check "recovered key fingerprint equals the original" \
  [ "$(fingerprint_of_saved "${ROOT}/stub-partial-recovery")" = "${PARTIAL_FP}" ]

# ---------------------------------------------------------------------------
echo "== 7. Restore never generates a key and checks the recorded fingerprint"
check "restore script contains no key-generation command" \
  bash -c "! grep -q 'genkeypair' '${HERE}/restore_key.sh'"
# Build a backup whose recorded fingerprint is wrong, using the real key from the first backup.
BACKUP_PASSPHRASE="${PASS_OK}" "${REAL_PYTHON}" "${HERE}/backup_crypto.py" unpack \
  --in "${ENC}" --dir "${ROOT}/mismatch-src" >/dev/null 2>&1
MISMATCH_PW="$(grep -m1 '^ANDROID_KEYSTORE_PASSWORD=' "${ROOT}/mismatch-src/credentials.env" | cut -d= -f2-)"
SIGN_PW="${MISMATCH_PW}" BACKUP_PASSPHRASE="${PASS_OK}" "${REAL_PYTHON}" "${HERE}/backup_crypto.py" pack \
  --p12 "${ROOT}/mismatch-src/mylife-upload.p12" --alias upload \
  --fingerprint "00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF" \
  --store-pass-env SIGN_PW --out "${ROOT}/wrong-record.enc" >/dev/null 2>&1
run_restore mismatch "${ROOT}/wrong-record.enc" "${PASS_OK}"
check "restore refuses when the certificate does not match the recorded fingerprint" [ "$?" -ne 0 ]
check "refused restore wrote no secrets" has_no_saved "${ROOT}/stub-mismatch"
check "refusal message says nothing was changed" grep -q "Nothing was changed" "${ROOT}/log-mismatch.txt"

# ---------------------------------------------------------------------------
echo "== 8. Temporary plaintext is removed even when a step fails"
FAILPACK=1 PASSPHRASE_USED="${PASS_OK}" EXIST="" run_setup backup failpack
check "backup fails when encryption fails" [ "$?" -ne 0 ]
check "scratch folder with the new key is removed after the failure" [ ! -e "${ROOT}/w-failpack" ]
check "no backup file left after the failure" [ ! -e "${ROOT}/o-failpack/mylife-android-signing-backup.enc" ]
check "no secrets written after the failure" has_no_saved "${ROOT}/stub-failpack"

# ---------------------------------------------------------------------------
echo "== 9. Passwords, tokens and key material never appear in output"
LEAK=0
STORE_VALUE="$(cat "${ROOT}/stub-first/saved-ANDROID_KEYSTORE_PASSWORD" 2>/dev/null || true)"
B64_PREFIX="$(head -c 60 "${ROOT}/stub-first/saved-ANDROID_KEYSTORE_BASE64" 2>/dev/null || true)"
# An empty needle would match every line, so the test first confirms the real values exist.
check "the real store password and key material were captured for the scan" \
  bash -c "[ -n '${STORE_VALUE}' ] && [ ${#B64_PREFIX} -eq 60 ]"
for log in "${ROOT}"/log-*.txt; do
  for needle in "${STORE_VALUE}" "${GH_TOKEN_VALUE}" "${PASS_OK}" "${PASS_WRONG}" "${B64_PREFIX}"; do
    [ -n "${needle}" ] || continue
    if grep -qF -- "${needle}" "${log}"; then
      echo "  leak in $(basename "${log}")"
      LEAK=1
    fi
  done
done
check "no logs contain the store password, token, passphrases or key material" [ "${LEAK}" = "0" ]

# ---------------------------------------------------------------------------
echo ""
echo "Results: ${PASSED} passed, ${FAILED} failed"
[ "${FAILED}" -eq 0 ]
