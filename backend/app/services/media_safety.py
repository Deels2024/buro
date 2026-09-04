"""Decode and re-encode public photographs without EXIF/GPS or opaque metadata."""
import io
import warnings

from PIL import Image, ImageOps

FORMATS = {"image/jpeg": "JPEG", "image/png": "PNG", "image/webp": "WEBP"}


def clean_photo(content: bytes, mime_type: str) -> tuple[bytes, int, int]:
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        with Image.open(io.BytesIO(content)) as source:
            if source.format != FORMATS.get(mime_type):
                raise ValueError("image_type_mismatch")
            if source.width * source.height > 25_000_000:
                raise ValueError("image_dimensions_exceeded")
            source.load()
            oriented = ImageOps.exif_transpose(source)
            oriented.thumbnail((2560, 2560))
            mode = "RGBA" if mime_type != "image/jpeg" and "A" in oriented.getbands() else "RGB"
            clean = Image.new(mode, oriented.size)
            clean.paste(oriented.convert(mode))
            output = io.BytesIO()
            clean.save(output, format=FORMATS[mime_type], quality=88)
            return output.getvalue(), clean.width, clean.height
