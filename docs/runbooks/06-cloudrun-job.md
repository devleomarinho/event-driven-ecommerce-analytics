# Runbook 07 — Cloud Run Job (Gerador de Eventos)

## Contexto

O Cloud Run Job `event-gen-job` containeriza o gerador de eventos
sinteticos (`ingestion/main.py`). Permite execucao manual sob demanda,
sem necessidade de manter ambiente Python local configurado.

## Arquitetura

gcloud run jobs execute  →  Container roda main.py
│
├─ gera 50 batches coerentes (3 eventos cada)
├─ NDJSON upload para gs://raw-events-qa/events/
└─ Pub/Sub notification → Snowpipe → Bronze

## Componentes

- **Imagem:** us-east4-docker.pkg.dev/event-driven-snowflake/event-gen/event-gen:vN
- **Service Account:** event-driven-snowflake@appspot.gserviceaccount.com
- **Variaveis:** TARGET_BUCKET, BATCH_COUNT
- **Memoria:** 512Mi
- **CPU:** 1

## Operacoes

### Build de nova versao da imagem

```powershell
cd ingestion/
gcloud builds submit `
    --tag us-east4-docker.pkg.dev/event-driven-snowflake/event-gen/event-gen:vN `
    .
```

### Atualizar Job para nova imagem

```powershell
gcloud run jobs update event-gen-job `
    --image=us-east4-docker.pkg.dev/event-driven-snowflake/event-gen/event-gen:vN `
    --region=us-east4
```

### Executar Job

```powershell
# Sincrono (aguarda completar)
gcloud run jobs execute event-gen-job --region=us-east4 --wait

# Assincrono (retorna imediatamente)
gcloud run jobs execute event-gen-job --region=us-east4
```

### Inspecionar logs de execucao

```powershell
# Lista execucoes recentes
gcloud run jobs executions list --job=event-gen-job --region=us-east4

# Logs de uma execucao especifica
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=event-gen-job" `
    --limit=50 `
    --format=json
```

## Trade-offs e decisoes

- **Cloud Run Job vs Cloud Function:** escolhemos Job porque o trabalho
  eh batch (gerar e completar), nao request-response.
- **Build via Cloud Build vs local:** Cloud Build evita necessidade de
  Docker local e eh mais rapido.
- **Imagem em Artifact Registry vs Docker Hub:** Artifact Registry eh
  o padrao GCP atual (Container Registry foi descontinuado em 2024).