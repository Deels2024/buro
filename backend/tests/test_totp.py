from app.core.totp import generate_totp_secret, totp_code, verify_totp


def test_totp_round_trip() -> None:
    secret = generate_totp_secret()
    code = totp_code(secret)
    assert verify_totp(secret, code)
    assert not verify_totp(secret, "000000" if code != "000000" else "111111")
