import ipaddress
import re
from urllib.parse import quote

from openai import AsyncOpenAI, DefaultAsyncHttpxClient

from app.core.config import Settings, settings


def openai_proxy_url(config: Settings) -> str | None:
    """Build the proxy URL without logging credentials or falling back on errors."""
    host = config.openai_proxy_address.strip()
    port = config.openai_proxy_port.strip()
    if not host:
        if port or config.openai_proxy_login or config.openai_proxy_password:
            raise ValueError("OpenAI proxy address is missing")
        return None
    scheme = config.openai_proxy_scheme.strip().lower().removesuffix("://")
    if scheme not in {"http", "https", "socks5", "socks5h"}:
        raise ValueError("OpenAI proxy scheme must be http, https, socks5 or socks5h")
    if not port.isascii() or not port.isdigit() or not 1 <= int(port) <= 65535:
        raise ValueError("OpenAI proxy port must be between 1 and 65535")
    if ":" in host:
        try:
            host = "[" + str(ipaddress.IPv6Address(host.strip("[]"))) + "]"
        except ValueError:
            raise ValueError("OpenAI proxy address must be a hostname or IP without a URL") from None
    elif not re.fullmatch(r"[A-Za-z0-9.-]+", host):
        raise ValueError("OpenAI proxy address must be a hostname or IP without a URL")
    login, password = config.openai_proxy_login, config.openai_proxy_password
    if bool(login) != bool(password):
        raise ValueError("OpenAI proxy login and password must both be set")
    auth = f"{quote(login, safe='')}:{quote(password, safe='')}@" if login else ""
    return f"{scheme}://{auth}{host}:{int(port)}"


def build_openai_client(api_key: str, *, timeout: float = 40, max_retries: int = 0) -> AsyncOpenAI:
    proxy = openai_proxy_url(settings)
    if proxy is None:
        return AsyncOpenAI(api_key=api_key, timeout=timeout, max_retries=max_retries)
    return AsyncOpenAI(
        api_key=api_key,
        timeout=timeout,
        max_retries=max_retries,
        http_client=DefaultAsyncHttpxClient(proxy=proxy, trust_env=False),
    )
