# =====================================================================
# Cloud Run Job — gerador de eventos sinteticos.
#
# Imagem base: python slim (menor footprint).
# =====================================================================

FROM python:3.11-slim

# Variaveis Python essenciais para containers
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Instala dependencias antes de copiar codigo (cache de layer)
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copia codigo
COPY *.py ./

CMD ["python", "main.py"]