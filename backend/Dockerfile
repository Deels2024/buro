FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app
RUN pip install --upgrade pip && pip install .

COPY alembic.ini ./
COPY alembic ./alembic
COPY scripts ./scripts

RUN addgroup --system --gid 10001 bureau \
    && adduser --system --uid 10001 --ingroup bureau --no-create-home bureau \
    && chown -R bureau:bureau /app
USER bureau

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-proxy-headers"]
