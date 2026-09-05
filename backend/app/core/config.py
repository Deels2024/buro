from functools import lru_cache
from pathlib import Path
from urllib.parse import urlparse

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="BN_", extra="ignore")

    environment: str = "development"
    release_sha: str = "local"
    seed_demo_data: bool = False
    api_host: str = "127.0.0.1"
    api_port: int = 8080
    app_secret: str = Field(min_length=32, default="development-secret-change-me-00000000")
    lookup_pepper: str = ""
    pii_fernet_key: str = ""
    database_url: str = "postgresql+asyncpg://bureau:bureau@localhost:5432/bureau"
    redis_url: str = "redis://localhost:6379/0"
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8080"]

    s3_endpoint: str = "http://localhost:9000"
    s3_public_endpoint: str = "http://localhost:9000"
    s3_region: str = "ru-central1"
    s3_bucket: str = "bureau-media"
    s3_access_key: str = "bureau"
    s3_secret_key: str = ""
    s3_presign_ttl_seconds: int = 900
    max_upload_bytes: int = 100 * 1024 * 1024

    openai_api_key: str = ""
    openai_api_key_file: str = ""
    openai_model: str = "gpt-5.6"
    openclip_url: str = "http://localhost:8090"
    openclip_timeout_seconds: int = 20

    smsc_url: str = "https://smsc.ru/sys/send.php"
    smsc_login: str = ""
    smsc_password: str = ""
    smsc_sender: str = ""
    bootstrap_admin_phone: str = "+79990000000"
    log_level: str = "INFO"
    public_api_url: str = "http://localhost:8080/v1"
    support_email: str = "support@bureau.local"
    min_ios_version: str = "1.0.0"
    min_android_version: str = "1.0.0"
    admin_2fa_issuer: str = "Бюро находок"
    webhook_timeout_seconds: int = 10
    webhook_max_attempts: int = 6
    request_id_header: str = "X-Request-ID"

    access_token_minutes: int = 15
    refresh_token_days: int = 30
    otp_ttl_seconds: int = 300
    otp_max_attempts: int = 5

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @property
    def smsc_is_configured(self) -> bool:
        return bool(self.smsc_login and self.smsc_password)

    @property
    def smsc_url_is_secure(self) -> bool:
        parsed = urlparse(self.smsc_url)
        return parsed.scheme == "https" and bool(parsed.netloc)

    @model_validator(mode="after")
    def load_image_release(self) -> "Settings":
        # Older forced deploy commands do not export BN_RELEASE_SHA. The image
        # contains the checkout SHA, independently of runtime environment values.
        release_file = Path(__file__).resolve().parents[2] / "release-sha.txt"
        if release_file.is_file():
            image_release = release_file.read_text(encoding="ascii").strip()
            if len(image_release) != 40 or any(c not in "0123456789abcdef" for c in image_release):
                raise ValueError("Invalid image release metadata")
            if self.release_sha not in ("local", image_release):
                raise ValueError("BN_RELEASE_SHA does not match the image")
            self.release_sha = image_release
        return self

    @model_validator(mode="after")
    def load_openai_api_key_file(self) -> "Settings":
        if not self.openai_api_key_file:
            return self
        try:
            openai_key = Path(self.openai_api_key_file).read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            return self
        except OSError as exc:
            raise ValueError("BN_OPENAI_API_KEY_FILE cannot be read") from exc
        if openai_key:
            self.openai_api_key = openai_key
        return self

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if not self.is_production:
            return self
        problems = []
        if self.app_secret.startswith("development-"):
            problems.append("BN_APP_SECRET")
        if len(self.lookup_pepper) < 32:
            problems.append("BN_LOOKUP_PEPPER")
        if len(self.pii_fernet_key) != 44:
            problems.append("BN_PII_FERNET_KEY")
        if not self.smsc_is_configured:
            problems.append("BN_SMSC_LOGIN and BN_SMSC_PASSWORD")
        if not self.smsc_url_is_secure:
            problems.append("BN_SMSC_URL (HTTPS)")
        if len(self.s3_secret_key) < 16:
            problems.append("BN_S3_SECRET_KEY")
        if not self.public_api_url.startswith("https://"):
            problems.append("BN_PUBLIC_API_URL")
        if problems:
            raise ValueError(f"Production secrets are not configured: {', '.join(problems)}")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
