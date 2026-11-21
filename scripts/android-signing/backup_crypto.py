#!/usr/bin/env python3
"""Authenticated encryption for the Android release-signing backup.

The backup is a short ASCII-armored text file, so it can be saved in iCloud Drive and copied
on an iPhone without any converter. Inside the armor is a binary blob:

    magic     4 bytes   b"MLBK"
    version   1 byte    0x01
    salt      16 bytes  random, input to scrypt
    nonce     12 bytes  random, for AES-256-GCM
    body      n bytes   AES-256-GCM ciphertext followed by its 16-byte tag

    -----BEGIN MYLIFE SIGNING BACKUP v1-----
    <base64 of the blob, wrapped at 64 characters>
    -----END MYLIFE SIGNING BACKUP v1-----

The header is passed as associated data, so changing any header byte is detected too.
Key derivation: scrypt (N=2^17, r=8, p=1) from the passphrase and salt, producing 32 bytes.

The passphrase is read from the environment variable BACKUP_PASSPHRASE, never from the command line.

Commands:
    pack    --p12 FILE --alias NAME --fingerprint SHA256 --store-pass-env VAR --out FILE
    unpack  --in FILE --dir DIR
        unpack writes DIR/mylife-upload.p12, DIR/credentials.env and DIR/expected-sha256.txt.
        Exit code 2 means the file is invalid, the passphrase is wrong, or the file was modified.
"""

import argparse
import base64
import binascii
import json
import os
import sys

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt

MAGIC = b"MLBK"
VERSION = 1
SALT_LEN = 16
NONCE_LEN = 12
HEADER_LEN = len(MAGIC) + 1 + SALT_LEN + NONCE_LEN
SCRYPT_N = 2**17
SCRYPT_R = 8
SCRYPT_P = 1
KEYSTORE_NAME = "mylife-upload.p12"
PAYLOAD_FORMAT = 1
ARMOR_BEGIN = "-----BEGIN MYLIFE SIGNING BACKUP v1-----"
ARMOR_END = "-----END MYLIFE SIGNING BACKUP v1-----"
ARMOR_WIDTH = 64


class BackupError(Exception):
    """Raised for any failure that must stop the workflow."""


def read_passphrase():
    value = os.environ.get("BACKUP_PASSPHRASE", "")
    if len(value) < 16:
        raise BackupError("BACKUP_PASSPHRASE is missing or shorter than 16 characters")
    return value.encode("utf-8")


def derive_key(passphrase, salt):
    kdf = Scrypt(salt=salt, length=32, n=SCRYPT_N, r=SCRYPT_R, p=SCRYPT_P)
    return kdf.derive(passphrase)


def encrypt_bytes(plaintext, passphrase):
    salt = os.urandom(SALT_LEN)
    nonce = os.urandom(NONCE_LEN)
    header = MAGIC + bytes([VERSION]) + salt + nonce
    body = AESGCM(derive_key(passphrase, salt)).encrypt(nonce, plaintext, header)
    return header + body


def decrypt_bytes(blob, passphrase):
    if len(blob) < HEADER_LEN + 16 or blob[:4] != MAGIC or blob[4] != VERSION:
        raise BackupError("the text is not a valid signing backup")
    header = blob[:HEADER_LEN]
    salt = header[5:5 + SALT_LEN]
    nonce = header[5 + SALT_LEN:HEADER_LEN]
    try:
        return AESGCM(derive_key(passphrase, salt)).decrypt(nonce, blob[HEADER_LEN:], header)
    except InvalidTag:
        raise BackupError("authentication failed: wrong passphrase or the backup was modified")


def armor(blob):
    """Returns the ASCII-armored text for a binary blob."""
    body = base64.b64encode(blob).decode("ascii")
    lines = [body[i:i + ARMOR_WIDTH] for i in range(0, len(body), ARMOR_WIDTH)]
    return "\n".join([ARMOR_BEGIN, *lines, ARMOR_END]) + "\n"


def dearmor(text):
    """Returns the binary blob from armored text. Tolerates CRLF line endings, indentation,
    blank lines and a missing final newline, which copy-paste on a phone can introduce."""
    lines = [line.strip() for line in text.replace("\r", "").split("\n")]
    lines = [line for line in lines if line]
    try:
        begin = lines.index(ARMOR_BEGIN)
        end = lines.index(ARMOR_END, begin + 1)
    except ValueError:
        raise BackupError("the text is not a valid signing backup (BEGIN/END lines missing)")
    body = "".join(lines[begin + 1:end])
    if not body:
        raise BackupError("the signing backup text is empty")
    try:
        return base64.b64decode(body, validate=True)
    except (ValueError, binascii.Error):
        raise BackupError("the signing backup text is damaged (invalid characters)")


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)


def cmd_pack(args):
    passphrase = read_passphrase()
    store_password = os.environ.get(args.store_pass_env, "")
    if not store_password:
        raise BackupError(f"environment variable {args.store_pass_env} is empty")
    with open(args.p12, "rb") as handle:
        p12 = handle.read()
    payload = {
        "format": PAYLOAD_FORMAT,
        "alias": args.alias,
        "store_password": store_password,
        "key_password": store_password,
        "sha256": args.fingerprint,
        "p12_base64": base64.b64encode(p12).decode("ascii"),
    }
    text = armor(encrypt_bytes(json.dumps(payload).encode("utf-8"), passphrase))
    write_private(args.out, text.encode("ascii"))
    print(f"Encrypted backup written ({len(text)} characters).")


def cmd_unpack(args):
    passphrase = read_passphrase()
    with open(args.infile, "rb") as handle:
        text = handle.read().decode("utf-8", errors="strict")
    plaintext = decrypt_bytes(dearmor(text), passphrase)
    try:
        payload = json.loads(plaintext.decode("utf-8"))
        if payload.get("format") != PAYLOAD_FORMAT:
            raise BackupError("unsupported backup payload format")
        p12 = base64.b64decode(payload["p12_base64"], validate=True)
        alias = payload["alias"]
        store_password = payload["store_password"]
        key_password = payload["key_password"]
        fingerprint = payload["sha256"]
    except (KeyError, ValueError, TypeError, UnicodeDecodeError) as exc:
        raise BackupError(f"backup payload is malformed: {exc.__class__.__name__}")
    os.makedirs(args.dir, mode=0o700, exist_ok=True)
    write_private(os.path.join(args.dir, KEYSTORE_NAME), p12)
    credentials = (
        f"ANDROID_KEYSTORE_BASE64={base64.b64encode(p12).decode('ascii')}\n"
        f"ANDROID_KEYSTORE_PASSWORD={store_password}\n"
        f"ANDROID_KEY_PASSWORD={key_password}\n"
        f"ANDROID_KEY_ALIAS={alias}\n"
    )
    write_private(os.path.join(args.dir, "credentials.env"), credentials.encode("utf-8"))
    write_private(os.path.join(args.dir, "expected-sha256.txt"), (fingerprint + "\n").encode("utf-8"))
    print("Backup authenticated and unpacked.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    pack = sub.add_parser("pack")
    pack.add_argument("--p12", required=True)
    pack.add_argument("--alias", required=True)
    pack.add_argument("--fingerprint", required=True)
    pack.add_argument("--store-pass-env", required=True)
    pack.add_argument("--out", required=True)
    pack.set_defaults(func=cmd_pack)

    unpack = sub.add_parser("unpack")
    unpack.add_argument("--in", dest="infile", required=True)
    unpack.add_argument("--dir", required=True)
    unpack.set_defaults(func=cmd_unpack)

    args = parser.parse_args(argv)
    try:
        args.func(args)
    except BackupError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    except (OSError, UnicodeDecodeError) as exc:
        print(f"ERROR: file error ({exc.__class__.__name__})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
