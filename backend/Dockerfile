FROM alpine:3.20 AS version
COPY .git/ /git/
COPY scripts/read-release-sha.sh /read-release-sha.sh
RUN test ! -e /git/config && test ! -d /git/objects && \
    sh /read-release-sha.sh /git > /release-sha.txt

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY backend/pyproject.toml ./
COPY backend/app ./app
RUN pip install --upgrade pip && pip install .

COPY backend/alembic.ini ./
COPY backend/alembic ./alembic
COPY backend/scripts ./scripts
COPY --from=version /release-sha.txt ./release-sha.txt

RUN addgroup --system --gid 10001 bureau \
    && adduser --system --uid 10001 --ingroup bureau --no-create-home bureau \
    && chown -R bureau:bureau /app
USER bureau

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-proxy-headers"]
