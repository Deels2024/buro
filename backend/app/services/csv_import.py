import csv
import io

from fastapi import HTTPException
from pydantic import ValidationError

from app.schemas import BulkListingItem


def parse_inventory_csv(value: str) -> list[BulkListingItem]:
    value = value.lstrip('\ufeff')
    first = value.splitlines()[0] if value.strip() else ''
    delimiter = ';' if first.count(';') > first.count(',') else ','
    reader = csv.DictReader(io.StringIO(value), delimiter=delimiter)
    required = {'title', 'description', 'category', 'region', 'event_at'}
    if not required.issubset(reader.fieldnames or []):
        raise HTTPException(422, 'Нужны колонки: title, description, category, region, event_at; необязательно storage_code и branch_id')
    items = []
    for index, row in enumerate(reader, start=2):
        if index > 1001:
            raise HTTPException(422, 'За один импорт допускается не более 1000 строк')
        if not any(row.values()):
            continue
        data = {key: val.strip() for key, val in row.items() if key and isinstance(val, str) and val.strip()}
        data['tags'] = [tag.strip() for tag in data.get('tags', '').split('|') if tag.strip()]
        try:
            items.append(BulkListingItem.model_validate(data))
        except ValidationError as exc:
            fields = ', '.join(str(e['loc'][0]) for e in exc.errors())
            raise HTTPException(422, f'Строка {index}: проверьте поля {fields}. Дата — в формате 2026-09-04T12:00:00+03:00') from None
    if not items:
        raise HTTPException(422, 'В файле нет записей')
    return items
