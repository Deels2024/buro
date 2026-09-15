import asyncio
import io
import os
from contextlib import asynccontextmanager
from functools import lru_cache
from threading import Lock
from urllib.parse import urlparse

import httpx
import open_clip
import torch
from fastapi import FastAPI, HTTPException
from PIL import Image
from pydantic import BaseModel, Field


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Download/load the model once, before admitting search requests. The first
    # user must not pay the cold-start delay inside the API's 20-second timeout.
    await asyncio.to_thread(encode_image, Image.new("RGB", (224, 224), "blue"))
    app.state.ready = True
    yield
    app.state.ready = False


app = FastAPI(title="Бюро находок OpenCLIP", docs_url=None, redoc_url=None, lifespan=lifespan)
app.state.ready = False
INFERENCE_LOCK = Lock()
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
    if len(values) != 512 or not torch.isfinite(vector).all().item():
        raise RuntimeError("OpenCLIP model must produce 512 finite dimensions")
    return EmbeddingOut(model=f"{MODEL_NAME}:{PRETRAINED}", dimensions=len(values), embedding=values)


def encode_image(image: Image.Image) -> EmbeddingOut:
    with INFERENCE_LOCK:
        model, preprocess, _ = model_bundle()
        tensor = preprocess(image).unsqueeze(0).to(DEVICE)
        with torch.inference_mode():
            vector = model.encode_image(tensor)
            vector /= vector.norm(dim=-1, keepdim=True)
        return output(vector)


def encode_text(text: str) -> EmbeddingOut:
    with INFERENCE_LOCK:
        model, _, tokenizer = model_bundle()
        tokens = tokenizer([text]).to(DEVICE)
        with torch.inference_mode():
            vector = model.encode_text(tokens)
            vector /= vector.norm(dim=-1, keepdim=True)
        return output(vector)


@app.get("/health/live")
async def live() -> dict[str, str]:
    return {"status": "ok", "device": DEVICE}


@app.get("/health/ready")
async def ready() -> dict[str, str]:
    if not app.state.ready:
        raise HTTPException(503, "Visual model is warming up")
    return {"status": "ready", "model": f"{MODEL_NAME}:{PRETRAINED}"}


@app.post("/v1/embed/image", response_model=EmbeddingOut)
async def embed_image(payload: ImageRequest) -> EmbeddingOut:
    parsed = urlparse(payload.image_url)
    if parsed.scheme not in {"http", "https"} or (parsed.hostname or "").lower() not in ALLOWED_HOSTS:
        raise HTTPException(status_code=422, detail="Image host is not allowed")
    async with httpx.AsyncClient(timeout=20, follow_redirects=False, trust_env=False) as client:
        response = await client.get(payload.image_url)
        response.raise_for_status()
        if len(response.content) > 25 * 1024 * 1024:
            raise HTTPException(status_code=413, detail="Image is too large")
    try:
        image = Image.open(io.BytesIO(response.content)).convert("RGB")
    except Exception as exc:
        raise HTTPException(status_code=422, detail="Invalid image") from exc
    return await asyncio.to_thread(encode_image, image)


@app.post("/v1/embed/text", response_model=EmbeddingOut)
async def embed_text(payload: TextRequest) -> EmbeddingOut:
    return await asyncio.to_thread(encode_text, payload.text)
