import base64
import hashlib
import hmac
import secrets
import struct
import time
from urllib.parse import quote


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def _counter_code(secret: str, counter: int, digits: int = 6) -> str:
    padded = secret + "=" * (-len(secret) % 8)
    key = base64.b32decode(padded.upper())
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % (10**digits)
    return f"{value:0{digits}d}"


def totp_code(secret: str, *, timestamp: int | None = None, period: int = 30) -> str:
    current = int(time.time() if timestamp is None else timestamp)
    return _counter_code(secret, current // period)


def verify_totp(secret: str, code: str, *, window: int = 1, period: int = 30) -> bool:
    if len(code) != 6 or not code.isdigit():
        return False
    counter = int(time.time()) // period
    return any(hmac.compare_digest(_counter_code(secret, counter + shift), code) for shift in range(-window, window + 1))


def provisioning_uri(secret: str, account: str, issuer: str) -> str:
    return (
        f"otpauth://totp/{quote(issuer)}:{quote(account)}"
        f"?secret={secret}&issuer={quote(issuer)}&algorithm=SHA1&digits=6&period=30"
    )
