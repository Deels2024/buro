from app.core.security import create_access_token, decode_access_token, normalize_phone


def test_phone_normalization() -> None:
    assert normalize_phone("8 (999) 123-45-67") == "+79991234567"
    assert normalize_phone("9991234567") == "+79991234567"


def test_access_token_round_trip() -> None:
    token = create_access_token("00000000-0000-0000-0000-000000000001", "user")
    payload = decode_access_token(token)
    assert payload["sub"] == "00000000-0000-0000-0000-000000000001"
    assert payload["role"] == "user"
