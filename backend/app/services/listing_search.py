"""Public listing search. Private addresses and ownership evidence are never indexed."""
import re
import unicodedata

from sqlalchemy import String, and_, case, cast, false, func, literal_column, or_, select
from sqlalchemy.dialects.postgresql import JSONB

from app.db.models import Listing
from app.services.categories import CATEGORIES


def words(query: str) -> list[str]:
    normalized = unicodedata.normalize('NFKC', query).casefold().replace('ё', 'е')
    return list(dict.fromkeys(re.findall(r'[^\W_]+', normalized, flags=re.UNICODE)))


def normalized_text(column):
    return func.replace(func.lower(func.coalesce(column, '')), 'ё', 'е')


def public_search_vector():
    config = literal_column("'russian'::regconfig")

    def text_vector(column, weight):
        return func.setweight(func.to_tsvector(config, normalized_text(column)), literal_column("'" + weight + "'"))

    def json_vector(column):
        # JSONB decoding preserves Cyrillic tags even when stored as \u escapes.
        value = func.coalesce(cast(column, JSONB), literal_column("'[]'::jsonb"))
        value = cast(func.replace(func.lower(cast(value, String)), 'ё', 'е'), JSONB)
        return func.setweight(func.to_tsvector(config, value), literal_column("'B'"))

    vector = text_vector(Listing.title, 'A').op('||')(text_vector(Listing.description, 'B'))
    vector = vector.op('||')(json_vector(Listing.tags)).op('||')(json_vector(Listing.public_features))
    category = case(CATEGORIES, value=Listing.category, else_=Listing.category)
    return vector.op('||')(text_vector(category, 'D')).op('||')(text_vector(Listing.public_region, 'D'))


def text_search(query: str, dialect: str):
    tokens = words(query)
    if not tokens:
        return false(), []
    if dialect == 'postgresql':
        # Only letters and digits reach tsquery; punctuation cannot become operators.
        tsquery = func.to_tsquery(literal_column("'russian'::regconfig"), ' & '.join(f'{token}:*' for token in tokens))
        vector = public_search_vector()
        phrase = ' '.join(tokens)
        rank = func.ts_rank_cd(vector, tsquery)
        title_match = normalized_text(Listing.title).contains(phrase, autoescape=True)
        return vector.bool_op('@@')(tsquery), [case((title_match, 1), else_=0).desc(), rank.desc()]

    # Lightweight SQLite development fallback; Russian morphology is tested on PostgreSQL.
    clauses = []
    for token in tokens:
        tag = func.json_each(Listing.tags).table_valued('value', joins_implicitly=True)
        feature = func.json_each(Listing.public_features).table_valued('value', joins_implicitly=True)
        clauses.append(or_(
            Listing.title.icontains(token, autoescape=True),
            Listing.description.icontains(token, autoescape=True),
            select(1).select_from(tag).where(tag.c.value.icontains(token, autoescape=True)).exists(),
            select(1).select_from(feature).where(feature.c.value.icontains(token, autoescape=True)).exists(),
        ))
    return and_(*clauses), []
