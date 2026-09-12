"""Index public text for Russian word and prefix search."""
from alembic import op

revision = "0003_public_search"
down_revision = "0002_integration_ready"
branch_labels = None
depends_on = None


def upgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.execute("""CREATE INDEX IF NOT EXISTS ix_listings_public_text ON listings USING gin ((((((setweight(to_tsvector('russian'::regconfig, replace(lower(coalesce(title, '')), 'ё', 'е')), 'A') || setweight(to_tsvector('russian'::regconfig, replace(lower(coalesce(description, '')), 'ё', 'е')), 'B')) || setweight(to_tsvector('russian'::regconfig, CAST(replace(lower(CAST(coalesce(CAST(tags AS JSONB), '[]'::jsonb) AS VARCHAR)), 'ё', 'е') AS JSONB)), 'B')) || setweight(to_tsvector('russian'::regconfig, CAST(replace(lower(CAST(coalesce(CAST(public_features AS JSONB), '[]'::jsonb) AS VARCHAR)), 'ё', 'е') AS JSONB)), 'B')) || setweight(to_tsvector('russian'::regconfig, replace(lower(coalesce(CASE category WHEN 'bags' THEN 'Сумки и рюкзаки' WHEN 'documents' THEN 'Документы' WHEN 'keys' THEN 'Ключи' WHEN 'electronics' THEN 'Электроника' WHEN 'clothing' THEN 'Одежда' WHEN 'jewelry' THEN 'Украшения' WHEN 'pets' THEN 'Животные' WHEN 'toys' THEN 'Игрушки' WHEN 'sport' THEN 'Спорт' WHEN 'other' THEN 'Другое' ELSE category END, '')), 'ё', 'е')), 'D')) || setweight(to_tsvector('russian'::regconfig, replace(lower(coalesce(public_region, '')), 'ё', 'е')), 'D')))
            WHERE status = 'active' AND moderation_status IN ('approved', 'auto_approved')""")


def downgrade() -> None:
    if op.get_bind().dialect.name == "postgresql":
        op.execute("DROP INDEX IF EXISTS ix_listings_public_text")
