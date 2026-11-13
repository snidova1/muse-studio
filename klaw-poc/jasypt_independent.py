#!/usr/bin/env python3
"""
Independent PBEWithMD5AndDES implementation (no Jasypt code, no Java).
Reproduces Jasypt BasicTextEncryptor defaults:
  - algorithm PBEWithMD5AndDES (PKCS#5 v1.5 PBKDF1, MD5, 1000 iterations)
  - 8-byte random salt, output = Base64(salt || ciphertext), DES/CBC/PKCS5Padding
  - key derivation: T1 = MD5(pwd_bytes || salt); Ti = MD5(Ti-1); 1000 iterations
    DK = T1000 (16 bytes); DES key = DK[0:8], IV = DK[8:16]
  - password bytes = UTF-8 (all test values are ASCII, so no ambiguity)

Usage:
  python3 jasypt_independent.py decrypt <base64-ciphertext> [key]
  python3 jasypt_independent.py encrypt <plaintext> [key]
Default key = kw2021secretkey (Klaw's public default).
"""
import base64
import hashlib
import sys

from Crypto.Cipher import DES
from Crypto.Random import get_random_bytes

DEFAULT_KEY = "kw2021secretkey"
ITERATIONS = 1000


def _derive_key(password: str, salt: bytes) -> tuple[bytes, bytes]:
    data = password.encode("utf-8") + salt
    digest = hashlib.md5(data).digest()
    for _ in range(ITERATIONS - 1):
        digest = hashlib.md5(digest).digest()
    return digest[:8], digest[8:16]  # DES key, IV


def decrypt(ciphertext_b64: str, password: str = DEFAULT_KEY) -> str:
    raw = base64.b64decode(ciphertext_b64)
    salt, ct = raw[:8], raw[8:]
    key, iv = _derive_key(password, salt)
    pt = DES.new(key, DES.MODE_CBC, iv).decrypt(ct)
    pad = pt[-1]
    return pt[:-pad].decode("utf-8")


def encrypt(plaintext: str, password: str = DEFAULT_KEY) -> str:
    salt = get_random_bytes(8)
    key, iv = _derive_key(password, salt)
    data = plaintext.encode("utf-8")
    pad = 8 - (len(data) % 8)
    data += bytes([pad]) * pad
    ct = DES.new(key, DES.MODE_CBC, iv).encrypt(data)
    return base64.b64encode(salt + ct).decode("ascii")


if __name__ == "__main__":
    cmd = sys.argv[1]
    arg = sys.argv[2]
    key = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_KEY
    if cmd == "decrypt":
        print(decrypt(arg, key))
    elif cmd == "encrypt":
        print(encrypt(arg, key))
    else:
        raise SystemExit("usage: decrypt|encrypt <value> [key]")
