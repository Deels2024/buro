import io

import pytest
from fastapi import HTTPException
from PIL import Image

from app.services.csv_import import parse_inventory_csv
from app.services.media_safety import clean_photo


def test_public_photo_removes_metadata_and_rejects_disguised_type():
    source = Image.new('RGB', (40, 30), color='red')
    exif = Image.Exif()
    exif[270] = 'private camera location'
    original = io.BytesIO()
    source.save(original, format='JPEG', exif=exif)
    clean,width,height = clean_photo(original.getvalue(),'image/jpeg')
    assert (width,height)==(40,30)
    with Image.open(io.BytesIO(clean)) as decoded:
        assert not decoded.getexif()
    assert b'private camera location' not in clean
    with pytest.raises(ValueError,match='image_type_mismatch'):
        clean_photo(original.getvalue(),'image/png')


def test_csv_quotes_and_validation_before_import():
    csv = '\ufefftitle;description;category;region;event_at\n"Чёрный; зонт";"Описание с; точкой";other;Москва;2026-09-04T12:00:00Z\n'
    items = parse_inventory_csv(csv)
    assert len(items)==1 and items[0].title=='Чёрный; зонт'
    with pytest.raises(HTTPException) as e:
        parse_inventory_csv(csv+'Ошибочная строка;\n')
    assert e.value.status_code==422 and 'Строка 3' in e.value.detail
