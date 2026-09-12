# Mobile artwork and typography

The mobile UI uses two small decorative illustrations on the home, welcome and
sign-in screens. Listing cards always use the user's own photos. Both assets have
an icon fallback, and decorative images are excluded from screen-reader semantics.

## Font

`BureauSans` is the app family alias for locally bundled Manrope, with Cyrillic,
Latin, punctuation and Russian currency/number signs. The four static instances
are weights 400, 500, 600 and 700. Fonts require no third-party request at runtime.

- Source: [Google Fonts / Manrope](https://github.com/google/fonts/tree/main/ofl/manrope).
- Source file: `Manrope[wght].ttf`, Git blob `23dcf5e05a97f19a3567d40ebb3765580a4325f7`.
- License: SIL Open Font License 1.1; the original copyright and full license are
  included in `fonts/OFL.txt` and bundled with the application.
- Instances generated with fontTools 4.61.1 (`varLib.instancer`), then subset to
  U+0020–024F, U+0400–052F, U+2000–206F, ₽, €, №, → and −. Name records retained.
- Files: `fonts/BureauSans-{400,500,600,700}.ttf`, about 247 KB combined.

## Illustrations

Created with the built-in image-generation tool. Generated PNG masters were
converted to 512 × 512 WebP using ImageMagick, `-resize 512x512 -strip -quality 82`.
The application images total about 19 KB. There are no runtime image-generation
calls, external stock services or additional API credentials.

### `illustrations/belongings.webp`

Original generation prompt:

> Use case: stylized-concept. Create one polished editorial illustration asset for an existing Russian lost-and-found mobile app called Bureau. Square canvas 1024x1024, no text at all. A small thoughtful still life of an elegant cobalt-blue everyday backpack, a pair of warm ivory over-ear headphones, and two silver house keys attached to a soft mint-green loop. All objects belong to one carefully composed scene, floating very slightly above a pale cool off-white background #F0F5F8 with soft realistic contact shadows. Premium matte tactile 3D / paper sculpture illustration, soft rounded but precise shapes, believable proportions, restrained materials, sophisticated adult aesthetic, reassuring and approachable. Blue #245EE8, deep navy accents, quiet mint #DDEFE8, silver, cream. Large clean silhouette readable when displayed at 120px wide. Backpack is dominant, headphones tucked beside it, keys in front. Keep all objects fully inside the image with about 10 percent breathing room. Orthographic three-quarter view, soft daylight from upper left. No people, no faces, no labels, no letters, no logos, no badges, no UI, no phone mockup, no watermark, no decorative sparkles. This is a decorative app illustration, not a photograph of an actual listing.

### `illustrations/return.webp`

Original generation prompt:

> Use case: stylized-concept. Create one understated premium editorial 3D illustration for a trustworthy lost-and-found mobile app. Square canvas 1024x1024, no text. Close-up of a gentle handover: a hand entering from the upper left holds a small mint-green loop with two silver house keys, while an open receiving palm enters from lower right. Each hand has natural five-finger anatomy with simplified smooth matte ceramic-like styling, not realistic human photography. One sleeve is cobalt blue #245EE8, the other is warm ivory. A small portion of wrist and sleeve visible on each side, no arms beyond the crop, no faces or bodies. The keys and hands form one graceful centered composition, readable as a small illustration. Soft neutral off-white background #F0F5F8, soft daylight from upper left, delicate shadows and restrained depth. Palette cobalt blue, pale mint, warm sand skin tones and ivory, silver keys. Sophisticated adult app aesthetic, caring, calm, useful. Plenty of space around the silhouette, no scattered objects. No checkmarks, no shields, no sparkles, no badges, no logos, no words, no UI, no frame, no watermark. This is decorative artwork about returning a found thing, not evidence of a real return.

## Review

`test/mobile_design_test.dart` loads the real fonts and artwork and exercises
320–430 px phone widths, 200% text, the SMS button with the keyboard open, and
navigation into search and creation. The optional `BUREAU_CAPTURE_DESIGN=true`
test define emits PNG previews from Flutter's renderer using synthetic fixtures.
It has no effect on the production build and contains no real account data.
