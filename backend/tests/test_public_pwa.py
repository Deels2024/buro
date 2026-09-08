"""Public pages must advertise the same installed app as the Flutter shell."""
from app.api.public_site import page


def test_public_page_advertises_app_and_legacy_launch_recovery():
    response = page("Test", "Description", "/", "<h1>Public content</h1>")
    html = response.body.decode()
    assert '<link rel="manifest" href="/site.webmanifest">' in html
    assert '<link rel="apple-touch-icon" href="/icons/icon-180.png">' in html
    assert '<script src="/pwa-launch.js" defer></script>' in html
    assert '<meta name="apple-mobile-web-app-capable" content="yes">' in html
    assert "<h1>Public content</h1>" in html
