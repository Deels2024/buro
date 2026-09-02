import json
import logging
from datetime import UTC, datetime, timedelta
from ipaddress import IPv4Address, IPv6Address, ip_address, ip_network
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from sqlalchemy import select

from app.api.deps import DB, CurrentUser
from app.core.config import settings
from app.core.security import (
    create_access_token,
    decrypt_json,
    encrypt_json,
    generate_otp,
    hash_secret,
    normalize_phone,
    phone_lookup_hash,
    random_token,
)
from app.core.totp import generate_totp_secret, provisioning_uri, verify_totp
from app.db.models import RefreshToken, User
from app.schemas import (
    MessageResponse,
    MFARequired,
    MFAVerifyRequest,
    PhoneCodeRequest,
    PhoneCodeRequested,
    PhoneCodeVerify,
    RefreshRequest,
    TokenPair,
    TOTPEnableRequest,
    TOTPSetupOut,
)
from app.services.cache import (
    OtpVerificationResult,
    rate_limit,
    redis,
    set_json,
    verify_and_consume_otp,
)
from app.services.sms import send_otp

router = APIRouter()
logger = logging.getLogger(__name__)

OTP_RESEND_COOLDOWN_SECONDS = 60
_TRUSTED_PROXY_NETWORKS = tuple(
    ip_network(network)
    for network in (
        "127.0.0.0/8",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
    )
)


def _parse_ip(value: str | None) -> IPv4Address | IPv6Address | None:
    if not value:
        return None
    try:
        return ip_address(value.strip())
    except ValueError:
        return None


def _client_ip(request: Request) -> str:
    """Return the real client address supplied by the private Docker gateway.

    The public Nginx gateway overwrites X-Real-IP with ``$remote_addr``. We only
    trust that value when the immediate peer is a loopback/private address, so
    a direct public caller cannot choose another rate-limit bucket.
    """

    peer = _parse_ip(request.client.host if request.client else None)
    if peer and any(peer in network for network in _TRUSTED_PROXY_NETWORKS):
        forwarded = _parse_ip(request.headers.get("x-real-ip"))
        if forwarded:
            return forwarded.compressed
    if peer:
        return peer.compressed
    return "unknown"


async def _otp_cooldown_remaining(key: str) -> int:
    remaining = await redis.ttl(key)
    return remaining if remaining > 0 else 0


async def _acquire_otp_cooldown(key: str) -> int:
    acquired = await redis.set(key, "1", ex=OTP_RESEND_COOLDOWN_SECONDS, nx=True)
    if acquired:
        return 0
    return max(await _otp_cooldown_remaining(key), 1)


def _raise_otp_cooldown(retry_after: int) -> None:
    raise HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=f"Новый код можно запросить через {retry_after} сек.",
        headers={"Retry-After": str(retry_after)},
    )


def _tokens(user: User, refresh_token: str, *, mfa: bool = False) -> TokenPair:
    return TokenPair(
        access_token=create_access_token(str(user.id), user.role, mfa=mfa),
        refresh_token=refresh_token,
        expires_in=settings.access_token_minutes * 60,
    )


async def _store_refresh(
    db: DB, user: User, device_name: str | None, *, mfa: bool = False
) -> tuple[str, RefreshToken]:
    raw = random_token(48)
    record = RefreshToken(
        user_id=user.id,
        token_hash=hash_secret(raw),
        expires_at=datetime.now(UTC) + timedelta(days=settings.refresh_token_days),
        device_name=device_name,
        mfa_verified=mfa,
    )
    db.add(record)
    await db.flush()
    return raw, record


@router.post("/request-code", response_model=PhoneCodeRequested)
async def request_code(payload: PhoneCodeRequest, request: Request) -> PhoneCodeRequested:
    try:
        phone = normalize_phone(payload.phone)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    phone_hash = phone_lookup_hash(phone)
    cooldown_key = f"otp:phone:cooldown:{phone_hash}"
    retry_after = await _otp_cooldown_remaining(cooldown_key)
    if retry_after:
        _raise_otp_cooldown(retry_after)

    client_key = hash_secret(_client_ip(request))[:24]
    if not await rate_limit(f"otp:phone:rate:{phone_hash}", 3, 600):
        raise HTTPException(status_code=429, detail="Слишком много кодов. Попробуйте позже")
    if not await rate_limit(f"otp:ip:rate:{client_key}", 12, 600):
        raise HTTPException(status_code=429, detail="Слишком много запросов")

    retry_after = await _acquire_otp_cooldown(cooldown_key)
    if retry_after:
        _raise_otp_cooldown(retry_after)

    code = generate_otp()
    otp_key = f"otp:{phone_hash}"
    try:
        await set_json(
            otp_key,
            {"hash": hash_secret(code), "attempts": 0},
            settings.otp_ttl_seconds,
        )
        await send_otp(phone, code)
    except Exception:
        # Do not leave a usable code behind if the user never received the SMS.
        await redis.delete(otp_key, cooldown_key)
        logger.exception("OTP delivery failed for phone ending in %s", phone[-4:])
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Не удалось отправить SMS. Попробуйте позже",
        ) from None
    return PhoneCodeRequested(
        expires_in=settings.otp_ttl_seconds,
        retry_after=OTP_RESEND_COOLDOWN_SECONDS,
        dev_code=code if not settings.is_production and not settings.smsc_is_configured else None,
    )


@router.post("/verify-code", response_model=TokenPair | MFARequired)
async def verify_code(payload: PhoneCodeVerify, db: DB) -> TokenPair | MFARequired:
    try:
        phone = normalize_phone(payload.phone)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    phone_hash = phone_lookup_hash(phone)
    key = f"otp:{phone_hash}"
    verification = await verify_and_consume_otp(
        key,
        hash_secret(payload.code),
        settings.otp_max_attempts,
    )
    if verification == OtpVerificationResult.EXPIRED:
        raise HTTPException(status_code=400, detail="Код истёк")
    if verification == OtpVerificationResult.ATTEMPTS_EXCEEDED:
        raise HTTPException(status_code=429, detail="Превышено число попыток")
    if verification == OtpVerificationResult.INVALID:
        raise HTTPException(status_code=400, detail="Неверный код")

    user = await db.scalar(select(User).where(User.phone_hash == phone_hash))
    if not user:
        role = "admin" if phone == normalize_phone(settings.bootstrap_admin_phone) else "user"
        user = User(
            phone_hash=phone_hash,
            phone_cipher=encrypt_json({"phone": phone}),
            role=role,
            verified_at=datetime.now(UTC),
            last_seen_at=datetime.now(UTC),
        )
        db.add(user)
        await db.flush()
    else:
        if user.status == "invited":
            user.status = "active"
            user.verified_at = datetime.now(UTC)
        user.last_seen_at = datetime.now(UTC)

    if user.role in {"admin", "moderator"} and user.admin_2fa_enabled:
        ticket = random_token(32)
        await set_json(
            f"admin-mfa:{ticket}",
            {"user_id": str(user.id), "device_name": payload.device_name},
            300,
        )
        await db.commit()
        return MFARequired(mfa_ticket=ticket)

    raw_refresh, _ = await _store_refresh(db, user, payload.device_name)
    await db.commit()
    return _tokens(user, raw_refresh)


@router.post("/verify-admin-2fa", response_model=TokenPair)
async def verify_admin_2fa(payload: MFAVerifyRequest, db: DB) -> TokenPair:
    raw = await redis.getdel(f"admin-mfa:{payload.mfa_ticket}")
    if not raw:
        raise HTTPException(status_code=400, detail="Проверка истекла")
    ticket = json.loads(raw)
    user = await db.get(User, UUID(ticket["user_id"]))
    if not user or user.role not in {"admin", "moderator"} or not user.admin_totp_secret_cipher:
        raise HTTPException(status_code=403, detail="Двухфакторная авторизация не настроена")
    secret = decrypt_json(user.admin_totp_secret_cipher)["secret"]
    if not verify_totp(secret, payload.code):
        raise HTTPException(status_code=400, detail="Неверный одноразовый код")
    raw_refresh, _ = await _store_refresh(
        db, user, payload.device_name or ticket.get("device_name"), mfa=True
    )
    await db.commit()
    return _tokens(user, raw_refresh, mfa=True)


@router.post("/admin-2fa/setup", response_model=TOTPSetupOut)
async def setup_admin_2fa(user: CurrentUser, db: DB) -> TOTPSetupOut:
    if user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=403, detail="Настройка доступна только администраторам")
    secret = generate_totp_secret()
    user.admin_totp_secret_cipher = encrypt_json({"secret": secret})
    user.admin_2fa_enabled = False
    await db.commit()
    return TOTPSetupOut(
        secret=secret,
        provisioning_uri=provisioning_uri(secret, str(user.id), settings.admin_2fa_issuer),
    )


@router.post("/admin-2fa/enable", response_model=MessageResponse)
async def enable_admin_2fa(payload: TOTPEnableRequest, user: CurrentUser, db: DB) -> MessageResponse:
    if user.role not in {"admin", "moderator"} or not user.admin_totp_secret_cipher:
        raise HTTPException(status_code=409, detail="Сначала создайте секрет 2FA")
    secret = decrypt_json(user.admin_totp_secret_cipher)["secret"]
    if not verify_totp(secret, payload.code):
        raise HTTPException(status_code=400, detail="Неверный одноразовый код")
    user.admin_2fa_enabled = True
    await db.commit()
    return MessageResponse(message="Двухфакторная авторизация включена")


@router.post("/admin-2fa/disable", response_model=MessageResponse)
async def disable_admin_2fa(payload: TOTPEnableRequest, user: CurrentUser, db: DB) -> MessageResponse:
    if not user.admin_2fa_enabled or not user.admin_totp_secret_cipher:
        raise HTTPException(status_code=409, detail="Двухфакторная авторизация не включена")
    secret = decrypt_json(user.admin_totp_secret_cipher)["secret"]
    if not verify_totp(secret, payload.code):
        raise HTTPException(status_code=400, detail="Неверный одноразовый код")
    user.admin_2fa_enabled = False
    user.admin_totp_secret_cipher = None
    await db.commit()
    return MessageResponse(message="Двухфакторная авторизация отключена")


@router.post("/refresh", response_model=TokenPair)
async def refresh(payload: RefreshRequest, db: DB) -> TokenPair:
    token_hash = hash_secret(payload.refresh_token)
    record = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    now = datetime.now(UTC)
    if not record or record.revoked_at or record.expires_at <= now:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Недействительная сессия")
    user = await db.get(User, record.user_id)
    if not user or user.status != "active":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Аккаунт недоступен")
    record.revoked_at = now
    raw_refresh, _ = await _store_refresh(
        db, user, payload.device_name or record.device_name, mfa=record.mfa_verified
    )
    await db.commit()
    return _tokens(user, raw_refresh, mfa=record.mfa_verified)


@router.post("/logout", response_model=MessageResponse)
async def logout(payload: RefreshRequest, db: DB, user: CurrentUser) -> MessageResponse:
    record = await db.scalar(
        select(RefreshToken).where(
            RefreshToken.token_hash == hash_secret(payload.refresh_token),
            RefreshToken.user_id == user.id,
        )
    )
    if record:
        record.revoked_at = datetime.now(UTC)
        await db.commit()
    return MessageResponse(message="Сессия завершена")
