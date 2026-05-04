"""
Publica eventos no Google Cloud Storage como NDJSON.

Cada chamada de `publicar` gera um arquivo NDJSON com os eventos
fornecidos e faz upload para o bucket configurado. O nome do
arquivo eh prefixado por timestamp para ordem natural e unicidade.
"""

import json
import logging
import os
from dataclasses import asdict
from datetime import datetime, timezone

from google.cloud import storage

from schemas import Event

logger = logging.getLogger(__name__)


def _gerar_nome_arquivo() -> str:
    """
    Nome do arquivo no GCS.

    Padrao: events-YYYYMMDD-HHMMSS-<random>.ndjson
    - Prefixo de timestamp facilita ordenacao e debugging
    - Sufixo random evita colisao em chamadas concorrentes
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    random_suffix = os.urandom(4).hex()
    return f"events-{timestamp}-{random_suffix}.ndjson"


def _eventos_para_ndjson(eventos: list[Event]) -> str:
    """Converte lista de Events em string NDJSON (um JSON por linha)."""
    linhas = [json.dumps(asdict(e), separators=(",", ":")) for e in eventos]
    return "\n".join(linhas)


def publicar(eventos: list[Event], bucket_name: str, prefix: str = "events/") -> str:
    """
    Publica lista de eventos como NDJSON no bucket GCS.

    Args:
        eventos: lista de Event a serem publicados
        bucket_name: nome do bucket GCS (ex: "raw-events-qa")
        prefix: pasta dentro do bucket (default: "events/")

    Returns:
        Caminho completo do objeto criado no GCS.
    """
    if not eventos:
        raise ValueError("Lista de eventos vazia — nada a publicar")

    # Conteudo NDJSON
    ndjson_content = _eventos_para_ndjson(eventos)

    # Nome do objeto no bucket
    filename = _gerar_nome_arquivo()
    object_path = f"{prefix}{filename}"

    # Upload via SDK
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_path)

    blob.upload_from_string(
        ndjson_content,
        content_type="application/x-ndjson",
    )

    full_path = f"gs://{bucket_name}/{object_path}"
    logger.info(
        "publicado %d eventos em %s",
        len(eventos),
        full_path,
        extra={"event_count": len(eventos), "gcs_path": full_path},
    )

    return full_path