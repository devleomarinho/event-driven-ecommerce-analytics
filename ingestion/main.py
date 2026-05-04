"""
Entry point do gerador de eventos sinteticos.

Executavel localmente ou como Cloud Run Job (mesmo binario).
Configuracao via:
- Argumentos CLI (modo local)
- Variaveis de ambiente (modo Cloud Run Job)
"""

import argparse
import logging
import os
import sys

from generator import gerar_batch_coerente
from publisher import publicar

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def gerar_e_publicar_batches(bucket_name: str, batch_count: int = 50) -> dict:
    """
    Gera N batches coerentes, publica 1 arquivo NDJSON por batch.

    Cada batch tem 3 eventos correlacionados. Resultado:
    - batch_count arquivos no GCS
    - ~3 * batch_count eventos no total
    """
    if batch_count < 1:
        raise ValueError(f"batch_count deve ser >= 1, recebido: {batch_count}")

    arquivos_publicados = []
    total_eventos = 0

    for i in range(batch_count):
        eventos = gerar_batch_coerente()
        gcs_path = publicar(eventos, bucket_name)
        arquivos_publicados.append(gcs_path)
        total_eventos += len(eventos)

        if (i + 1) % 10 == 0:
            logger.info("progresso: %d/%d batches publicados", i + 1, batch_count)

    return {
        "status": "ok",
        "batch_count": batch_count,
        "event_count_total": total_eventos,
        "files_count": len(arquivos_publicados),
    }


def main():
    """Entry point unificado: detecta modo (CLI vs Cloud Run) via env var."""
    is_cloud_run = os.environ.get("TARGET_BUCKET") is not None

    if is_cloud_run:
        bucket_name = os.environ["TARGET_BUCKET"]
        batch_count = int(os.environ.get("BATCH_COUNT", "50"))
        logger.info(
            "modo Cloud Run Job — bucket=%s batches=%d",
            bucket_name,
            batch_count,
        )
    else:
        parser = argparse.ArgumentParser(
            description="Gera batches coerentes de eventos e publica no GCS"
        )
        parser.add_argument("--bucket", required=True, help="Bucket GCS")
        parser.add_argument(
            "--batches",
            type=int,
            default=50,
            help="Numero de batches a gerar (default: 50)",
        )
        args = parser.parse_args()
        bucket_name = args.bucket
        batch_count = args.batches

    try:
        result = gerar_e_publicar_batches(bucket_name, batch_count)
        logger.info("sucesso: %s", result)
        sys.exit(0)
    except Exception:
        logger.exception("falha")
        sys.exit(1)


if __name__ == "__main__":
    main()