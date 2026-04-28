# Runbook 03: Setup do projeto GCP

Configura o projeto Google Cloud com os recursos necessários para a pipeline:
APIs habilitadas, buckets de armazenamento, tópicos Pub/Sub para notificações
GCS, e subscriptions PULL que serão consumidas pelo Snowpipe.

Os bindings IAM entre Snowflake e GCP estão em runbook separado
([Runbook 04](04-configure-gcs-iam.md)) porque dependem das Storage e Notification
Integrations já existirem no Snowflake.

## Pré-requisitos

- Conta Google Cloud com billing habilitado (free tier suficiente)
- `gcloud` CLI instalado e autenticado: `gcloud auth login`
- Decisão de em qual região operar — deve ser **a mesma região do Snowflake**
  para evitar custos de egress entre regiões

## Passo 1 — Criar projeto e habilitar billing

Via console GCP em https://console.cloud.google.com:

1. Criar projeto novo (anotar o `project_id`, ele será referenciado em todos
   os comandos seguintes — neste projeto: `event-driven-snowflake`)
2. Linkar o projeto a uma billing account ativa

Definir como projeto default no `gcloud`:

```bash
gcloud config set project event-driven-snowflake
```

## Passo 2 — Habilitar APIs

```bash
gcloud services enable \
    storage.googleapis.com \
    pubsub.googleapis.com \
    cloudfunctions.googleapis.com \
    cloudbuild.googleapis.com \
    eventarc.googleapis.com \
    iam.googleapis.com
```

Aguardar 1-2 minutos para a habilitação propagar antes do próximo passo.

Validação:

```bash
gcloud services list --enabled --filter="name:(storage OR pubsub OR cloudfunctions OR iam)"
```

## Passo 3 — Criar buckets GCS

Dois buckets — um por ambiente que ingere dados (DEV é populado via clone, não
tem ingestão própria):

```bash
gcloud storage buckets create gs://raw-events-qa \
    --location=us-east4 \
    --uniform-bucket-level-access \
    --default-storage-class=STANDARD

gcloud storage buckets create gs://raw-events-prod \
    --location=us-east4 \
    --uniform-bucket-level-access \
    --default-storage-class=STANDARD
```

Notas:

- `--location=us-east4`: deve bater com a região do Snowflake. Verificar com
  `SELECT CURRENT_REGION()` no Snowsight; ajustar se diferente.
- `--uniform-bucket-level-access`: simplifica IAM. Sem isso, cada objeto pode
  ter ACL própria (legacy, evitar).
- Nomes de bucket são **globalmente únicos** no GCP. Se algum estiver tomado,
  prefixar com algo distintivo (ex: `<seu-prefixo>-raw-events-qa`) e ajustar
  todas as referências em V004 e nos scripts.

## Passo 4 — Criar tópicos Pub/Sub

Os tópicos recebem notificações `OBJECT_FINALIZE` do GCS:

```bash
gcloud pubsub topics create gcs-notify-events-qa
gcloud pubsub topics create gcs-notify-events-prod
```

Validação:

```bash
gcloud pubsub topics list
```

## Passo 5 — Criar subscriptions PULL

Subscriptions são criadas como tipo PULL — Snowflake consome via polling, não
recebe POST HTTP. Não usar `--push-endpoint`.

```bash
gcloud pubsub subscriptions create gcs-notify-events-qa-snowflake \
    --topic=gcs-notify-events-qa \
    --ack-deadline=600 \
    --message-retention-duration=7d

gcloud pubsub subscriptions create gcs-notify-events-prod-snowflake \
    --topic=gcs-notify-events-prod \
    --ack-deadline=600 \
    --message-retention-duration=7d
```

Notas:

- `--ack-deadline=600`: 10 minutos é o recomendado pela Snowflake. O default
  de 10s causa re-entrega em casos onde o COPY demora mais.
- `--message-retention-duration=7d`: backlog em caso de outage do Snowflake.

## Passo 6 — Configurar GCS notification

Liga eventos do bucket ao tópico Pub/Sub. Filtra para `OBJECT_FINALIZE` (upload
completo) sob o prefixo `events/`:

```bash
gcloud storage buckets notifications create gs://raw-events-qa \
    --topic=gcs-notify-events-qa \
    --event-types=OBJECT_FINALIZE \
    --payload-format=json \
    --object-prefix=events/

gcloud storage buckets notifications create gs://raw-events-prod \
    --topic=gcs-notify-events-prod \
    --event-types=OBJECT_FINALIZE \
    --payload-format=json \
    --object-prefix=events/
```

Validação:

```bash
gcloud storage buckets notifications list gs://raw-events-qa
```

Saída esperada deve incluir o tópico `gcs-notify-events-qa` com
`event_types: [OBJECT_FINALIZE]`, `payload_format: JSON_API_V1`, e
`object_name_prefix: events/`.

## Validação end-to-end

Confirmar que a cadeia GCS → Pub/Sub → Subscription está fluindo, antes de
configurar o lado Snowflake.

```powershell
# Cria arquivo de teste local
"test event" | Out-File -FilePath test-notification.json -Encoding utf8

# Sobe para o bucket sob a pasta /events/
gcloud storage cp test-notification.json gs://raw-events-qa/events/test-notification.json

# Imediatamente puxa mensagens da subscription
gcloud pubsub subscriptions pull gcs-notify-events-qa-snowflake `
    --auto-ack `
    --limit=5

# Limpeza
gcloud storage rm gs://raw-events-qa/events/test-notification.json
Remove-Item test-notification.json
```

Saída esperada do `pull`: pelo menos uma mensagem com atributos:

```
bucketId         = raw-events-qa
eventType        = OBJECT_FINALIZE
objectId         = events/test-notification.json
payloadFormat    = JSON_API_V1
```

Se essa mensagem aparece, a cadeia GCP está funcionando. Repetir o procedimento
para PROD trocando `qa` por `prod`.

## Automação opcional

Os passos 5 e 6 estão consolidados em `scripts/setup-gcp-pubsub.ps1`. Permite
re-executar com idempotência e cobre QA e PROD parametrizados:

```powershell
.\scripts\setup-gcp-pubsub.ps1 -Environment qa
.\scripts\setup-gcp-pubsub.ps1 -Environment prod
```

## Troubleshooting

**Erro: `bucket already exists in another project`**

Causa: nome de bucket é globalmente único; alguém já tomou.

Fix: prefixar com algo distintivo do projeto e ajustar referências em V004.

**Erro: `failed to create notification: 412 Precondition Failed`**

Causa: GCS exige que o tópico Pub/Sub exista **antes** de criar a notification,
e que o service account do GCS tenha permissão de publicar nele. Esse último
geralmente é configurado automaticamente, mas pode falhar em projetos novos.

Fix: aguardar 1-2 minutos após criar o tópico antes de criar a notification.
Se persistir, verificar com:

```bash
gcloud projects get-iam-policy event-driven-snowflake \
    --flatten="bindings[].members" \
    --filter="bindings.role:roles/pubsub.publisher AND bindings.members:serviceAccount" \
    --format="value(bindings.members)"
```

Deve listar um service account `service-<NUMBER>@gs-project-accounts.iam.gserviceaccount.com`.
Se não listar, conceder manualmente:

```bash
gcloud projects add-iam-policy-binding event-driven-snowflake \
    --member="serviceAccount:service-<NUMBER>@gs-project-accounts.iam.gserviceaccount.com" \
    --role="roles/pubsub.publisher"
```

**`pubsub subscriptions pull` retorna vazio mesmo após upload**

Causa mais comum: filtro `--object-prefix=events/` da notification não bate com
o caminho do upload. Verificar que o arquivo foi uploaded **dentro de** `events/`
e não na raiz do bucket.

Outra causa: latência da notificação. GCS pode levar alguns segundos. Tentar
o `pull` 2-3 vezes com intervalo.

## Próximos passos

- [Runbook 04 — IAM GCP para Snowflake](04-configure-gcs-iam.md)
- [Runbook 05 — Deploy de migrations](05-deploy-migrations.md)