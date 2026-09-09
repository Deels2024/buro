import asyncio
import base64

import pytest
from openai import APIConnectionError

from app.core.config import Settings
from app.services import openai_client


def config(**values):
    return Settings.model_construct(**values)


def test_existing_proxy_credentials_are_url_encoded():
    value = openai_client.openai_proxy_url(config(
        openai_proxy_address="proxy.example", openai_proxy_port="3128",
        openai_proxy_login="user@domain", openai_proxy_password="p:a/s?#%",
    ))
    assert value == "http://user%40domain:p%3Aa%2Fs%3F%23%25@proxy.example:3128"


def test_empty_config_preserves_direct_connection():
    assert openai_client.openai_proxy_url(config()) is None


@pytest.mark.parametrize("values", [
    {"openai_proxy_port": "1234"},
    {"openai_proxy_address": "proxy.example", "openai_proxy_port": "99999"},
    {"openai_proxy_address": "http://proxy.example", "openai_proxy_port": "80"},
    {"openai_proxy_address": "proxy.example", "openai_proxy_port": "80", "openai_proxy_scheme": "ftp"},
    {"openai_proxy_address": "proxy.example", "openai_proxy_port": "80", "openai_proxy_login": "private-login"},
])
def test_incomplete_proxy_fails_without_disclosing_values(values):
    with pytest.raises(ValueError) as error:
        openai_client.openai_proxy_url(config(**values))
    assert "private-login" not in str(error.value)


@pytest.mark.parametrize("scheme", ["http", "https", "socks5", "socks5h"])
async def test_supported_transports_construct_and_close(monkeypatch, scheme):
    monkeypatch.setattr(openai_client, "settings", config(
        openai_proxy_address="127.0.0.1", openai_proxy_port="12345", openai_proxy_scheme=scheme,
    ))
    client = openai_client.build_openai_client("test-key")
    await client.close()


async def test_openai_uses_authenticated_connect_and_does_not_fall_back(monkeypatch):
    # A local proxy rejects CONNECT. No request can reach OpenAI or leave CI.
    captured = []
    async def reject(reader, writer):
        headers = await reader.readuntil(b"\r\n\r\n")
        captured.append(headers)
        writer.write(b"HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    server = await asyncio.start_server(reject, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    monkeypatch.setattr(openai_client, "settings", config(
        openai_proxy_address="127.0.0.1", openai_proxy_port=str(port),
        openai_proxy_login="test-user", openai_proxy_password="test-password",
    ))
    client = openai_client.build_openai_client("test-key", timeout=3, max_retries=0)
    try:
        async with server:
            with pytest.raises(APIConnectionError):
                await client.responses.create(model="test-model", input="test")
    finally:
        await client.close()
        server.close()
        await server.wait_closed()
    assert len(captured) == 1
    assert captured[0].startswith(b"CONNECT api.openai.com:443 HTTP/1.1")
    expected = base64.b64encode(b"test-user:test-password")
    assert b"Proxy-Authorization: Basic " + expected in captured[0]
    assert b"test-key" not in captured[0]
