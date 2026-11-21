#!/usr/bin/env python3
"""Non-production self-test of the backup cryptography on a GitHub-hosted runner.

Uses the same scrypt parameters and AES-256-GCM code as the real backup. It creates a random
test passphrase and random test data in memory only. It never touches repository secrets,
never generates a signing key and never publishes anything. It prints only timings, sizes,
memory use and PASS/FAIL results. No passphrase, key or backup text is printed.
"""

import os
import platform
import resource
import secrets
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))

import cryptography  # noqa: E402
import backup_crypto as b  # noqa: E402

failures = []


def check(name, condition):
    print(("PASS: " if condition else "FAIL: ") + name)
    if not condition:
        failures.append(name)


def expect_rejected(name, fn):
    try:
        fn()
    except b.BackupError:
        check(name, True)
        return
    except Exception as exc:  # any other error is also a failure of the check
        check(f"{name} (unexpected {exc.__class__.__name__})", False)
        return
    check(name, False)


def peak_memory_mb():
    # ru_maxrss is kilobytes on Linux.
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024.0


print("== Environment")
print(f"Python {platform.python_version()} on {platform.platform()}")
print(f"cryptography {cryptography.__version__}")
print(f"scrypt parameters: N=2^17 (131072), r={b.SCRYPT_R}, p={b.SCRYPT_P}, 32-byte key")
print(f"AES-256-GCM, 12-byte nonce, 16-byte tag, 16-byte salt")
check("cryptography imports and reports a version", bool(cryptography.__version__))
mem_before = peak_memory_mb()
print(f"Peak memory before crypto: {mem_before:.1f} MB")

print("== Round trip with a realistic payload size")
passphrase = secrets.token_urlsafe(24).encode("utf-8")  # random, never printed
payload = secrets.token_bytes(3072)  # same order of size as the real JSON payload

t0 = time.perf_counter()
blob = b.encrypt_bytes(payload, passphrase)
t_enc = time.perf_counter() - t0
text = b.armor(blob)
print(f"Encrypt (scrypt + AES-256-GCM): {t_enc:.2f} s; armored size {len(text)} characters")

t0 = time.perf_counter()
restored = b.decrypt_bytes(b.dearmor(text), passphrase)
t_dec = time.perf_counter() - t0
print(f"Decrypt (scrypt + AES-256-GCM): {t_dec:.2f} s")
check("decrypted data equals the original", restored == payload)
check("armored text is printable ASCII", all(32 <= ord(c) < 127 or c in "\r\n" for c in text))

print("== Authentication: wrong passphrase and any modification are rejected")
expect_rejected("wrong passphrase is rejected", lambda: b.decrypt_bytes(b.dearmor(text), passphrase + b"x"))
for label, offset in [("ciphertext body", 60), ("salt", 8), ("nonce", 25), ("GCM tag", len(blob) - 3)]:
    mutated = bytearray(blob)
    mutated[offset] ^= 0x01
    expect_rejected(f"modified {label} is rejected", lambda m=bytes(mutated): b.decrypt_bytes(m, passphrase))
expect_rejected("truncated backup is rejected", lambda: b.decrypt_bytes(blob[:40], passphrase))

print("== Copy-paste tolerance")
crlf = "\r\n".join("   " + line + "  " for line in text.strip().split("\n"))
check("CRLF, indented, unterminated text decodes to the same blob", b.dearmor(crlf) == blob)

peak_after = peak_memory_mb()
print(f"Peak memory after crypto: {peak_after:.1f} MB (process peak, includes Python runtime)")
check("peak memory stays below 512 MB", peak_after < 512)
check("encryption and decryption finish within 60 seconds each", t_enc < 60 and t_dec < 60)

print("")
if failures:
    print(f"SELFTEST FAILED: {len(failures)} check(s) failed")
    sys.exit(1)
print("SELFTEST PASSED: all checks passed")
