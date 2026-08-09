import io
import os
from functools import lru_cache
from urllib.parse import urlparse

import httpx
import open_clip
import torch
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel, Field

app = FastAPI(title="Бюро находок OpenCLIP", docs_url=None, redoc_url=None)
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
MODEL_NAME = os.getenv("OPENCLIP_MODEL", "ViT-B-32")
PRETRAINED = os.getenv("OPENCLIP_PRETRAINED", "laion2b_s34b_b79k")
ALLOWED_HOSTS = {
    host.strip().lower()
    for host in os.getenv("OPENCLIP_ALLOWED_IMAGE_HOSTS", "minio,localhost").split(",")
    if host.strip()
}


class ImageRequest(BaseModel):
    image_url: str = Field(max_length=4000)


class TextRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


class EmbeddingOut(BaseModel):
    model: str
    dimensions: int
    embedding: list[float]


@lru_cache
def model_bundle():
    model, _, preprocess = open_clip.create_model_and_transforms(MODEL_NAME, pretrained=PRETRAINED)
    tokenizer = open_clip.get_tokenizer(MODEL_NAME)
    model = model.to(DEVICE).eval()
    return model, preprocess, tokenizer


def output(vector: torch.Tensor) -> EmbeddingOut:
    values = vector.detach().cpu().float().tolist()[0]
    return EmbeddingOut(model=f"{MODEL_NAME}:{PRETRAINED}", dimensions=len(values), embedding=values)


@app.get("/health/live")
async def live() -> dict[str, str]:
    return {"status": "ok", "device": DEVICE}


@app.post("/v1/embed/image", response_model=EmbeddingOut)
async def embed_image(payload: ImageRequest) -> EmbeddingOut:
    parsed = urlparse(payload.image_url)
    if parsed.scheme not in {"http", "https"} or (parsed.hostname or "").lower() not in ALLOWED_HOSTS:
        raise HTTPException(status_code=422, detail="Image host is not allowed")
    async with httpx.AsyncClient(timeout=20, follow_redirects=False) as client:
        response = await client.get(payload.image_url)
        response.raise_for_status()
        if len(response.content) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Image is too large")
    try:
        image = Image.open(io.BytesIO(response.content)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=422, detail="Invalid image") from exc
    model, preprocess, _ = model_bundle()
    tensor = preprocess(image).unsqueeze(0).to(DEVICE)
    with torch.inference_mode():
        vector = model.encode_image(tensor)
        vector /= vector.norm(dim=-1, keepdim=True)
    return output(vector)


@app.post("/v1/embed/text", response_model=EmbeddingOut)
async def embed_text(payload: TextRequest) -> EmbeddingOut:
    model, _, tokenizer = model_bundle()
    tokens = tokenizer([payload.text]).to(DEVICE)
    with torch.inference_mode():
        vector = model.encode_text(tokens)
        vector /= vector.norm(dim=-1, keepdim=True)
    return output(vector)
