"""Stable category codes shared by search, imports and AI suggestions."""

CATEGORIES = {
    "bags": "Сумки и рюкзаки",
    "documents": "Документы",
    "keys": "Ключи",
    "electronics": "Электроника",
    "clothing": "Одежда",
    "jewelry": "Украшения",
    "pets": "Животные",
    "toys": "Игрушки",
    "sport": "Спорт",
    "other": "Другое",
}
ALIASES = {
    "bags": ["сумки", "рюкзак", "рюкзаки", "сумка", "сумки и рюкзаки", "bag", "backpack"],
    "documents": ["документы", "документ", "паспорт", "document"],
    "keys": ["ключи", "ключ", "key"],
    "electronics": ["электроника", "телефоны", "телефон", "гаджеты", "phone", "phones", "телефоны и электроника"],
    "clothing": ["одежда", "одежда и обувь", "обувь", "clothes"],
    "jewelry": ["украшения", "драгоценности", "часы", "jewellery"],
    "pets": ["животные", "питомцы"],
    "toys": ["игрушки", "игрушка"],
    "sport": ["спорт", "спортинвентарь"],
    "other": ["другое", "прочее", "вещь"],
}


def normalize_category(value: str) -> str:
    value = value.strip().lower()
    for code, aliases in ALIASES.items():
        if value == code or value in aliases:
            return code
    return "other"


def category_values(value: str) -> list[str]:
    code = normalize_category(value)
    return [code, *ALIASES[code]]
