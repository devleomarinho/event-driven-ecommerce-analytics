# Runbook 04: Configurar IAM GCP para Storage e Notification Integrations

Concede ao service account da Snowflake (gerado automaticamente quando as
integrations são criadas) acesso aos recursos GCP correspondentes: leitura
nos buckets GCS e consumo das subscriptions Pub/Sub.

## Quando executar

Após o primeiro deploy bem-sucedido das migrations V004 e V005, e sempre que
uma nova Storage ou Notification Integration for criada.

## Pré-requisitos

- `gcloud` CLI autenticado: `gcloud auth login`
- Acesso de proprietário/editor ao projeto GCP
- Acesso ao Snowsight como `ACCOUNTADMIN`
- Migrations V004 e V005 já aplicadas (ver [Runbook 05](05-deploy-migrations.md))

## Passo 1 — Obter os Service Accounts gerados pela Snowflake

No Snowsight:

```sql
USE ROLE ACCOUNTADMIN;

DESC STORAGE INTEGRATION GCS_INT_RAW_EVENTS_QA;
DESC STORAGE INTEGRATION GCS_INT_RAW_EVENTS_PROD;
DESC NOTIFICATION INTEGRATION GCS_NOTIF_RAW_EVENTS_QA;
DESC NOTIFICATION INTEGRATION GCS_NOTIF_RAW_EVENTS_PROD;
```

Anotar:

- `STORAGE_GCP_SERVICE_ACCOUNT` das duas Storage Integrations
- `GCP_PUBSUB_SERVICE_ACCOUNT` das duas Notification Integrations

Observação: o SA pode ser o **mesmo** entre QA e PROD do mesmo tipo. Isso é
esperado — a Snowflake aloca um SA por combinação `(conta, região, tipo de
integration)`. O isolamento entre ambientes vem de outras camadas:
`STORAGE_ALLOWED_LOCATIONS` na Storage Integration e
`GCP_PUBSUB_SUBSCRIPTION_NAME` na Notification Integration.

## Passo 2 — Aplicar bindings IAM

```powershell
$SA_STORAGE = "<valor-do-DESC>"
$SA_NOTIF   = "<valor-do-DESC>"
$Project    = "event-driven-snowflake"

# Buckets — Snowflake lê os arquivos
gcloud storage buckets add-iam-policy-binding gs://raw-events-qa `
    --member="serviceAccount:$SA_STORAGE" `
    --role="roles/storage.objectViewer"

gcloud storage buckets add-iam-policy-binding gs://raw-events-prod `
    --member="serviceAccount:$SA_STORAGE" `
    --role="roles/storage.objectViewer"

# Subscriptions — Snowflake consome notificações
gcloud pubsub subscriptions add-iam-policy-binding gcs-notify-events-qa-snowflake `
    --project=$Project `
    --member="serviceAccount:$SA_NOTIF" `
    --role="roles/pubsub.subscriber"

gcloud pubsub subscriptions add-iam-policy-binding gcs-notify-events-prod-snowflake `
    --project=$Project `
    --member="serviceAccount:$SA_NOTIF" `
    --role="roles/pubsub.subscriber"

# Projeto — necessário para o handshake inicial do Snowflake
# (pouco documentado, mas crítico)
gcloud projects add-iam-policy-binding $Project `
    --member="serviceAccount:$SA_NOTIF" `
    --role="roles/pubsub.viewer"
```

## Passo 3 — Validar

No Snowsight, criar um stage temporário usando a Storage Integration e
listar arquivos do bucket:

```sql
USE ROLE ROLE_INGESTION;
USE WAREHOUSE WH_LOAD_XS;
USE DATABASE ANALYTICS_QA;
USE SCHEMA BRONZE;

CREATE OR REPLACE TEMPORARY STAGE TEST_STG
    STORAGE_INTEGRATION = GCS_INT_RAW_EVENTS_QA
    URL = 'gcs://raw-events-qa/events/';

LIST @TEST_STG;
-- Esperado: 0 rows (bucket vazio) ou lista de arquivos.
-- NÃO deve dar erro 403.

DROP STAGE TEST_STG;
```

Repetir para PROD substituindo `QA` por `PROD` e o nome do bucket.

A validação completa do auto-ingest (Pipe consumindo notificações) acontece
após a V006, quando o Pipe estiver criado.

## Troubleshooting

| Erro | Causa | Fix |
|---|---|---|
| `403 Permission denied` no `LIST` | IAM não aplicado no bucket, ou aplicado no SA errado | Refazer Passo 2, conferir que `$SA_STORAGE` é o valor exato do `DESC` |
| `404 Bucket not found` | Nome do bucket errado em `STORAGE_ALLOWED_LOCATIONS` | Verificar V004 e o bucket real no GCP (`gcloud storage buckets list`) |
| Auto-ingest não dispara mesmo com notification chegando no Pub/Sub | Faltou `pubsub.viewer` no projeto | Reexecutar último comando do Passo 2 |
| `Integration is not enabled` | Integration foi criada com `ENABLED = FALSE` | `ALTER STORAGE INTEGRATION <nome> SET ENABLED = TRUE` |

## Próximos passos

- [Runbook 05 — Deploy de migrations](05-deploy-migrations.md)
- [Runbook 06 — Troubleshooting](06-troubleshooting.md)