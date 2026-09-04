import hashlib
import re
from pathlib import Path
from uuid import UUID, uuid4

import boto3
from botocore.config import Config

from app.core.config import settings

ALLOWED_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
}


class ObjectStorage:
    def __init__(self) -> None:
        common = {
            "service_name": "s3",
            "region_name": settings.s3_region,
            "aws_access_key_id": settings.s3_access_key,
            "aws_secret_access_key": settings.s3_secret_key,
            "config": Config(
                signature_version="s3v4",
                s3={"addressing_style": "path"},
                connect_timeout=2,
                read_timeout=5,
                retries={"max_attempts": 1},
            ),
        }
        self.client = boto3.client(
            endpoint_url=settings.s3_endpoint,
            **common,
        )
        self.public_client = boto3.client(
            endpoint_url=settings.s3_public_endpoint,
            **common,
        )

    def ensure_bucket(self) -> None:
        try:
            self.client.head_bucket(Bucket=settings.s3_bucket)
        except Exception:
            self.client.create_bucket(Bucket=settings.s3_bucket)

    def make_key(self, owner_id: UUID, filename: str, mime_type: str, purpose: str) -> str:
        extension = ALLOWED_EXTENSIONS[mime_type]
        safe_stem = re.sub(r"[^a-zA-Z0-9_-]", "-", Path(filename).stem)[:40].strip("-") or "media"
        return f"{purpose}/{owner_id}/{uuid4()}-{safe_stem}{extension}"

    def presign_upload(self, object_key: str, mime_type: str, size_bytes: int) -> str:
        return self.public_client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.s3_bucket,
                "Key": object_key,
                "ContentType": mime_type,
                "ContentLength": size_bytes,
            },
            ExpiresIn=settings.s3_presign_ttl_seconds,
        )

    def presign_download(self, object_key: str, *, internal: bool = False) -> str:
        client = self.client if internal else self.public_client
        return client.generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket, "Key": object_key},
            ExpiresIn=settings.s3_presign_ttl_seconds,
        )

    def head(self, object_key: str) -> dict:
        return self.client.head_object(Bucket=settings.s3_bucket, Key=object_key)

    def read_bytes(self, object_key: str) -> bytes:
        response = self.client.get_object(Bucket=settings.s3_bucket, Key=object_key)
        try:
            content = response["Body"].read(settings.max_upload_bytes + 1)
            if len(content) > settings.max_upload_bytes:
                raise ValueError("upload_size_exceeded")
            return content
        finally:
            response["Body"].close()

    def write_bytes(self, key: str, content: bytes, mime_type: str) -> None:
        self.client.put_object(Bucket=settings.s3_bucket, Key=key, Body=content, ContentType=mime_type)

    def delete(self, key: str) -> None:
        self.client.delete_object(Bucket=settings.s3_bucket, Key=key)

    def sha256(self, object_key: str) -> str:
        digest = hashlib.sha256()
        response = self.client.get_object(Bucket=settings.s3_bucket, Key=object_key)
        for chunk in response["Body"].iter_chunks(chunk_size=1024 * 1024):
            digest.update(chunk)
        return digest.hexdigest()


storage = ObjectStorage()
