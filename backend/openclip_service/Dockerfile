FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu 'torch>=2.7,<3' 'torchvision>=0.22,<1' \
    && pip install --no-cache-dir -r requirements.txt
COPY main.py ./

RUN groupadd --gid 10002 openclip \
    && useradd --uid 10002 --gid openclip --create-home --home-dir /home/openclip openclip \
    && mkdir -p /home/openclip/.cache \
    && chown -R openclip:openclip /app /home/openclip
USER openclip

EXPOSE 8090
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8090"]
