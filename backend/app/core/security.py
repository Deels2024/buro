import base64
import hashlib
import hmac
import json
import re
import secrets
import time
from datetime import UTC, datetime, timedelta
from typing import Any

from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings


class TokenError(ValueError):
    pass


def normalize_phone(value: str) -> str:
    digits = re.sub(r"\D", "", value)
    if len(digits) == 11 and digits.startswith("8"):
        digits = "7" + digits[1:]
    if len(digits) == 10:
        digits = "7" + digits
    if len(digits) != 11 or not digits.startswith("7"):
        raise ValueError("Нужен российский номер телефона")
    return "+" + digits


def phone_lookup_hash(phone: str) -> str:
    pepper = settings.lookup_pepper or settings.app_secret
    return hmac.new(pepper.encode(), normalize_phone(phone).encode(), hashlib.sha256).hexdigest()


def mask_phone(phone: str) -> str:
    normalized = normalize_phone(phone)
    return f"{normalized[:2]} {normalized[2:5]} •••-••-{normalized[-2:]}"


def _fernet() -> Fernet:
    if settings.pii_fernet_key:
        key = settings.pii_fernet_key.encode()
    else:
        key = base64.urlsafe_b64encode(hashlib.sha256(settings.app_secret.encode()).digest())
    return Fernet(key)


def encrypt_json(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
    return _fernet().encrypt(payload).decode()


def decrypt_json(value: str) -> Any:
    try:
        payload = _fernet().decrypt(value.encode())
    except InvalidToken as exc:
        raise ValueError("Не удалось расшифровать защищённые данные") from exc
    return json.loads(payload)


def hash_secret(value: str) -> str:
    return hmac.new(settings.app_secret.encode(), value.encode(), hashlib.sha256).hexdigest()


def random_token(size: int = 32) -> str:
    return secrets.token_urlsafe(size)


def generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _b64encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _b64decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def create_access_token(subject: str, role: str, *, mfa: bool = False) -> str:
    now = datetime.now(UTC)
    payload = {
        "sub": subject,
        "role": role,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.access_token_minutes)).timestamp()),
        "iss": "bureau-nakhodok",
        "aud": "bureau-app",
        "jti": random_token(12),
        "mfa": mfa,
    }
    header = {"alg": "HS256", "typ": "JWT"}
    unsigned = f"{_b64encode(json.dumps(header, separators=(',', ':')).encode())}.{_b64encode(json.dumps(payload, separators=(',', ':')).encode())}"
    signature = hmac.new(settings.app_secret.encode(), unsigned.encode(), hashlib.sha256).digest()
    return f"{unsigned}.{_b64encode(signature)}"


def decode_access_token(token: str) -> dict[str, Any]:
    try:
        encoded_header, encoded_payload, encoded_signature = token.split(".")
        unsigned = f"{encoded_header}.{encoded_payload}"
        expected = hmac.new(settings.app_secret.encode(), unsigned.encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64decode(encoded_signature)):
            raise TokenError("Неверная подпись токена")
        payload = json.loads(_b64decode(encoded_payload))
    except (ValueError, json.JSONDecodeError) as exc:
        raise TokenError("Повреждённый токен") from exc
    if payload.get("iss") != "bureau-nakhodok" or payload.get("aud") != "bureau-app":
        raise TokenError("Неверный издатель токена")
    if int(payload.get("exp", 0)) <= int(time.time()):
        raise TokenError("Токен истёк")
    return payload
