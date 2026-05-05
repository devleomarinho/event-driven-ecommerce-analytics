# Pipeline Event-Driven para E-commerce: GCP + Snowflake + dbt 

[![GitHub Actions](https://github.com/devleomarinho/event-driven-ecommerce-analytics/actions/workflows/schemachange.yml/badge.svg)](https://github.com/devleomarinho/event-driven-ecommerce-analytics/actions)
![Snowflake](https://img.shields.io/badge/Snowflake-Enterprise-29B5E8)
![dbt](https://img.shields.io/badge/dbt-1.9-FF694B)
![Python](https://img.shields.io/badge/Python-3.13-3776AB)

Pipeline analítica completa, **orientada a eventos**, integrando Google Cloud Platform e Snowflake. O projeto demonstra ingestão em near-real-time, modelagem dimensional sobre arquitetura medalhão (Bronze/Silver/Gold) e deploy versionado de IaC (infraestrutura como código).

> 🇺🇸 For the English version, read at [README.en.md](README.en.md).
---

## Por que arquitetura event-driven?

Pipelines tradicionais de analytics operam em **batch agendado**: a cada N minutos/horas, um job verifica se há dados novos e os processa. Esse modelo tem três problemas conhecidos:

1. **Latência fixa pelo schedule.** Mesmo que dados cheguem em segundos, o consumidor só vê após o próximo run agendado.
2. **Polling desperdiçado.** A maioria das execuções não encontra dados novos, mas paga o custo de inicializar e consultar mesmo assim.
3. **Backpressure invisível.** Se o produtor acelera, o consumidor agendado pode não acompanhar, aumentando a defasagem silenciosamente.

A arquitetura event-driven inverte essa lógica: cada componente reage a notificações do anterior, sem carga agendada. Latência é proporcional ao tempo de processamento real, não à frequência do schedule. O custo computacional é proporcional ao volume de eventos, não ao tempo decorrido.

Neste projeto, **nenhuma etapa usa polling**:

- O produtor (Cloud Run Job) escreve direto em GCS quando executa.
- GCS emite notificação Pub/Sub no momento da escrita.
- Snowflake (via Snowpipe + Notification Integration) consome a fila e ingere o arquivo.
- Bronze → Silver via Dynamic Tables com `TARGET_LAG = 5 minutes` (declarativo, otimizado pelo Snowflake).
- Gold via dbt, executado sob demanda no Snowsight Workspace.

A latência típica end-to-end (do upload em GCS até dado disponível em Bronze) é **menor que 1 minuto**.

---

## Caso de uso: e-commerce

O projeto modela uma operação fictícia de e-commerce que produz quatro tipos de evento de domínio:

| Evento | Significado |
|---|---|
| `customer_registered` | Cadastro inicial de cliente |
| `customer_updated` | Mudança em atributo do cliente (email, estado) |
| `order_created` | Criação de pedido |
| `order_status_changed` | Transição de status do pedido (paid, shipped, delivered) |

Esses eventos chegam como NDJSON no GCS, são tipados e deduplicados em Silver (Dynamic Tables) e modelados em estrela em Gold (dbt). As tabelas finais respondem perguntas analíticas comuns:

- Qual a receita diária por estado?
- Onde estão os pedidos pendentes (por status)?
- Quanto tempo leva, em média, entre criação e entrega?
- Qual o ticket médio por região?

---

## Arquitetura

```text
                  GCP                                            Snowflake

  ┌──────────────────────────────┐               ┌──────────────────────────────────┐
  │                              │               │                                  │
  │    Cloud Run Job (Python)    │               │   Bronze (RAW_EVENTS)            │
  │    └─ Faker + lógica de      │               │   └─ raw_data: VARIANT (NDJSON)  │
  │       batch coerente         │               │      _source_file, _ingested_at  │
  │                              │               │              │                   │
  │              │               │               │              ▼                   │
  │              ▼               │               │   Silver (Dynamic Tables)        │
  │    GCS bucket /events/       │               │   ├─ DT_ORDERS_CREATED           │
  │    └─ NDJSON files           │               │   ├─ DT_ORDERS_STATUS_CHANGED    │
  │              │               │               │   ├─ DT_CUSTOMERS_REGISTERED     │
  │              ▼               │               │   └─ DT_CUSTOMERS_UPDATED        │
  │    Pub/Sub (notification)    │               │      (TARGET_LAG = 5min)         │
  │              │               │               │              │                   │
  │              ▼               │               │              ▼                   │
  │    Subscription PULL ────────┼──── auto ────▶│   Gold (dbt models)              │
  │                              │    ingest     │   ├─ Staging (4 views)           │
  │                              │               │   ├─ Dimensions (3 tables)       │
  └──────────────────────────────┘               │   ├─ Facts (2 tables)            │
                                                 │   └─ Marts (2 tables)            │
                                                 │                                  │
                                                 └──────────────────────────────────┘
```

### Características principais

- **Event-driven end-to-end**: nenhum componente faz polling. Cada um reage à notificação anterior.
- **Três ambientes isolados** (`DEV`, `QA`, `PROD`): cada um com sua database, schemas, e `CHANGE_HISTORY` própria.
- **Infraestrutura como código**: schemachange para Snowflake (DDL versionado), scripts PowerShell idempotentes para GCP.
- **CI/CD do schemachange via GitHub Actions**: branches mapeadas para ambientes, com approval manual em PROD.
- **RBAC com least privilege**: 3 roles funcionais + ROLE_DEPLOY para automação.

---

## Stack tecnológica

| Camada | Tecnologia | Justificativa |
|---|---|---|
| Cloud | Google Cloud Platform | Stack escolhida; integração nativa com Snowflake via Storage e Notification Integrations |
| Mensageria | Pub/Sub | Notification entre GCS e Snowflake; |
| Storage de eventos | GCS | Camada de persistência e replay; arquivos imutáveis |
| Compute (geração) | Cloud Run Job | Execução batch sob demanda |
| Data Warehouse | Snowflake (Enterprise edition) | Suporte a Dynamic Tables, Snowpipe, dbt Projects on Snowflake |
| Migrations DDL | schemachange | Versionamento de SQL; idempotente; alternativa leve a Terraform |
| Transformações analíticas | dbt (via Snowsight Workspace) | Padrão de mercado; suporte nativo do Snowflake |
| Linguagem | Python 3.13 | Cloud Run Job (Faker) |
| Container | Docker (build via GCP Artifact) | Imagem do Cloud Run Job |
| CI/CD | GitHub Actions | Deploy automatizado de schemachange |
| Geração de dados sintéticos | Faker (pt_BR) | Eventos realistas em português em formato NDJSON |

---

## Estrutura do repositório

```text
.
├── infra/
│   └── snowflake/
│       ├── environments/                # configs schemachange por ambiente
│       │   ├── dev.yml
│       │   ├── qa.yml
│       │   └── prod.yml
│       ├── migrations/                  # SQL versionado V001...V007
│                       
├── ingestion/                           # gerador de eventos (Cloud Run Job)
│   ├── main.py                          # entry point CLI + Cloud Run Job
│   ├── schemas.py                       # dataclasses dos eventos
│   ├── generator.py                     # geração com Faker + batches coerentes
│   ├── publisher.py                     # upload NDJSON para GCS
│   ├── Dockerfile
│   ├── requirements.txt
│   └── pyproject.toml
├── dbt_project/                         # projeto dbt (camada Gold)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── staging/                     # views sobre Silver
│   │   └── marts/                       # dims, facts, marts
│   ├── macros/
│   │   └── generate_schema_name.sql     # custom para evitar GOLD_GOLD
│   └── seeds/
│       └── dim_products.csv             # seed estático
├── scripts/                             # automação local
│   ├── load-env.ps1                  
│   ├── generate-keypair.sh
│   └── setup-gcp-pubsub.ps1
├── docs/
│   ├── runbooks/                        # 09 runbooks operacionais
│   
└── .github/
    └── workflows/
        └── schemachange.yml             # CI/CD do schemachange
```

---

## Camadas do data warehouse

### Bronze — `ANALYTICS_<env>.BRONZE.RAW_EVENTS`

Camada de persistência imutável dos eventos brutos. Estrutura minimalista:

```sql
RAW_EVENTS (
    raw_data        VARIANT       NOT NULL,    -- JSON inteiro do evento
    _source_file    STRING        NOT NULL,    -- nome do arquivo de origem
    _ingested_at    TIMESTAMP_NTZ NOT NULL     -- quando entrou no Snowflake
)
```

Filosofia: **schema-on-read**. Toda a estrutura do evento (event_id, event_type, payload) está em VARIANT — extração tipada acontece em Silver. Vantagem: Bronze nunca quebra por mudança de schema do produtor; é a fonte de verdade para reprocessamento.

### Silver — `ANALYTICS_<env>.SILVER.*`

Quatro Dynamic Tables (uma por tipo de evento), com `TARGET_LAG = 5 minutes`:

- `DT_ORDERS_CREATED`
- `DT_ORDERS_STATUS_CHANGED`
- `DT_CUSTOMERS_REGISTERED`
- `DT_CUSTOMERS_UPDATED`

Cada DT extrai os campos do payload com tipagem explícita (DECIMAL para amounts, TIMESTAMP_NTZ para timestamps, etc.) e deduplica por `event_id` (proteção contra at-least-once delivery do Pub/Sub):

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1
```

### Gold — `ANALYTICS_<env>.GOLD.*` (via dbt)

Modelagem dimensional em estrela:

**Staging (views — abstração leve sobre Silver):**
- `STG_ORDERS_CREATED`, `STG_ORDERS_STATUS_CHANGED`
- `STG_CUSTOMERS_REGISTERED`, `STG_CUSTOMERS_UPDATED`

**Dimensions:**
- `DIM_CUSTOMERS` — SCD1 (estado atual com email/state mais recentes via update). Surrogate key MD5.
- `DIM_DATE` — calendário 2024-2027 gerado via `GENERATOR(ROWCOUNT)`. Date key formato YYYYMMDD.
- `DIM_PRODUCTS` — seed CSV com 20 produtos (catálogo estático para demonstrar `dbt seed`).

**Facts:**
- `FCT_ORDERS` — snapshot fact (1 linha por pedido com estado atual).
- `FCT_ORDER_LIFECYCLE` — transactional fact (1 linha por status_change).

**Marts:**
- `MART_DAILY_REVENUE` — receita diária por estado, com taxas de conversão e ticket médio.
- `MART_ORDER_FUNNEL` — distribuição de pedidos por status atual.

---

## Geração de dados sintéticos

O gerador (`ingestion/`) produz batches coerentes de eventos relacionados, simulando o comportamento natural de um e-commerce:

- **70% happy_path**: customer_registered → order_created → order_status_changed
- **20% with_update**: customer_registered → customer_updated → order_created
- **10% multiple_orders**: customer_registered → order_created → order_created (mesmo cliente)

Cada batch resulta em **1 arquivo NDJSON com 3 eventos coerentes** (mesmo customer_id quando aplicável). Uma execução padrão gera 50 batches ≈ 150 eventos com correlação de identidade preservada.

---

## CI/CD

### Schemachange via GitHub Actions

O deploy de migrations é totalmente automatizado:

```text
git push em feature/*  →  GitHub Actions  →  schemachange deploy DEV
git push em develop    →  GitHub Actions  →  schemachange deploy QA
git push em main       →  GitHub Actions  →  schemachange deploy PROD (com approval)
```

**Mapeamento branch → ambiente**: implementado dentro do workflow (não há necessidade de branches `dev`, `qa`, `prod` no Git; apenas `feature/*`, `develop` e `main`).

**Environment Protection**: o ambiente `prod` no GitHub exige approval manual antes do deploy (dupla checagem após merge em main).

**Idempotência**: schemachange compara checksum das migrations com `CHANGE_HISTORY` do ambiente. Migrations já aplicadas viram no-op automaticamente.

### dbt em desenvolvimento manual

dbt **não está em CI/CD** neste projeto, por escolha consciente. Causa: a conta Snowflake atual é trial, que **não permite External Access Integration**. Como `dbt deps` (e algumas operações de `EXECUTE DBT PROJECT`) podem precisar de external access, o pipeline automatizado fica indisponível.

Workflow atual: dbt é editado e executado **direto no Snowsight Workspace** (conectado ao repo via Git Integration). Commits feitos pela UI do Workspace são push para o repo; mudanças no repo aparecem no Workspace via "Sync changes".

Em conta Standard+, o pattern automatizado seria:

```yaml
- run: |
    snow sql -q "ALTER GIT REPOSITORY ... FETCH;"
    snow dbt deploy DBT_EVENT_DRIVEN_ANALYTICS
    snow dbt execute DBT_EVENT_DRIVEN_ANALYTICS --args "build --target qa"
```

### Cloud Run Job manual

O Cloud Run Job é deployado manualmente via comandos `gcloud` documentados no Runbook 07. Em produção real, seria automatizado seguindo o mesmo padrão do schemachange (GitHub Actions com `gcloud builds submit` + `gcloud run jobs deploy`).

---

## Decisões arquiteturais

Esta seção documenta as escolhas técnicas mais relevantes do projeto e o raciocínio por trás de cada uma.

### ADR-001: Bronze pura (3 colunas) em vez de schema estruturado

**Decisão.** A tabela `RAW_EVENTS` tem apenas 3 colunas: `raw_data` (VARIANT), `_source_file` e `_ingested_at`. Toda a estrutura do evento (event_id, event_type, payload, etc.) fica dentro do VARIANT.

**Alternativa considerada.** Bronze "minimamente estruturada" com colunas tipadas para event_id, event_type, event_timestamp e VARIANT apenas para o payload variável.

**Razões.**

- Schema-on-read elimina acoplamento com o produtor. Mudanças no schema dos eventos não quebram Bronze.
- Bronze fica conceitualmente clara: "cópia literal do que veio". Tipagem e validação acontecem em Silver, onde já fazem sentido para queries downstream.
- Em produção real, o validador de eventos no produtor (que poderia ser Pydantic, Avro Schema Registry, etc.) é a primeira linha de defesa. Bronze é a segunda — preserva tudo, mesmo que o validador falhe.

### ADR-002: Dynamic Tables em vez de Streams + Tasks

**Decisão.** A camada Silver usa Dynamic Tables com `TARGET_LAG = 5 minutes`.

**Alternativa considerada.** O padrão clássico de Snowflake é Streams (CDC sobre tabelas) + Tasks (jobs agendados que consomem o stream e fazem MERGE/INSERT). Esse padrão é maduro mas exige código procedural significativo.

**Razões.**

- Dynamic Tables são **declarativas**: você descreve o resultado desejado em SQL e o Snowflake decide quando re-processar. Sem código de orquestração.
- Refresh incremental é automático quando possível (caso o nosso, já que Bronze é insert-only).
- TARGET_LAG é um SLA, não um schedule. Snowflake otimiza quando rodar baseado em quando dados chegam.

### ADR-003: dbt Projects on Snowflake em vez de dbt Core local

**Decisão.** A camada Gold usa dbt Projects on Snowflake, executado via Snowsight Workspace.

**Alternativa considerada.** dbt Core instalado localmente, conectando ao Snowflake via `profiles.yml` (padrão tradicional).

**Razões.**

- Recurso novo da Snowflake (GA em 2024). Demonstra atualização técnica e exploração de releases.
- Reduz superfície operacional: dbt roda dentro do Snowflake, sem necessidade de credentials externas, ambiente Python local, ou agendamento separado.
- Workspace integrado fornece IDE web, sync bidirecional com Git e execução de comandos (run, test, build) sem ferramenta extra.

**Trade-off.** Lock-in maior com Snowflake. Em projeto multi-cloud ou com necessidade de portabilidade de adapter, dbt Core seria escolha correta.

### ADR-004: Cloud Run Job em vez de Cloud Function

**Decisão.** O gerador de eventos é containerizado como Cloud Run Job, executado sob demanda via `gcloud run jobs execute`.

**Alternativa considerada.** Cloud Function HTTP-triggered.

**Razões.**

- Cloud Run Job é a abstração correta para **batch jobs**. Cloud Function é otimizada para request-response e exige um wrapper HTTP que não agrega valor para a tarefa.
- Para o caso de uso (executar manualmente quando quiser gerar dados), não há necessidade de servidor HTTP rodando.
- Schedule, se necessário, pode ser adicionado via Cloud Scheduler com a mesma simplicidade.

### ADR-005: RBAC enxuto (3 roles funcionais)

**Decisão.** O projeto usa 3 roles funcionais (`ROLE_INGESTION`, `ROLE_TRANSFORMER`, `ROLE_ANALYST`) + 1 role de automação (`ROLE_DEPLOY`).

**Alternativa considerada.** Hierarquia completa de Access Roles (read/write por schema) + Functional Roles, padrão recomendado pela Snowflake para grandes organizações.

**Razões.**

- 3 roles funcionais já demonstram o conceito de least privilege: cada role tem propósito específico (ingestão, transformação, leitura analítica).
- ROLE_DEPLOY assume outras roles via grant (`GRANT ROLE ROLE_INGESTION TO ROLE ROLE_DEPLOY`), permitindo que objetos criados em deploy tenham owner semanticamente correto (ROLE_INGESTION para Bronze, ROLE_TRANSFORMER para Silver/Gold).

**Trade-off conhecido.** A simplicidade tem custo: durante o desenvolvimento, foram observados conflitos de ownership quando objetos eram criados manualmente em sandbox (com role X) e depois recriados via migration (com role Y). Em produção real, hierarquia mais formal previne isso.

---

## Setup e operação

A configuração inicial envolve passos manuais (key-pair Snowflake, IAM no GCP, secrets no GitHub). Cada um está documentado como runbook em `docs/runbooks/`:

| # | Runbook | Conteúdo |
|---|---|---|
| 01 | Bootstrap do Snowflake | Service account, key-pair, role de deploy |
| 02 | Configuração do ambiente local | schemachange, Snowflake CLI, variáveis de ambiente |
| 03 | Setup do projeto GCP | APIs, buckets, tópicos Pub/Sub, subscriptions |
| 04 | IAM GCP para Snowflake | Bindings entre service accounts da Snowflake e recursos GCP |
| 05 | Deploy de migrations | Uso do schemachange contra DEV, QA e PROD |
| 06 | Cloud Run Job | Build de imagem, deploy, execução manual |
| 07 | Setup do dbt Projects on Snowflake | Pré-requisitos, API Integration, Git Repository, Workspace |
| 08 | Operação do dbt no Workspace | Workflow de desenvolvimento, comandos úteis, troubleshooting |
| 09 | CI/CD com GitHub Actions | Configuração de secrets, environments, workflow |

---

## Como reproduzir

Para reproduzir o projeto:

1. Configura conta Snowflake — [Runbook 01](docs/runbooks/01-bootstrap-snowflake.md)
2. Configura ambiente local — [Runbook 02](docs/runbooks/02-configure-local-environment.md)
3. Configura projeto GCP com APIs habilitadas — [Runbook 03](docs/runbooks/03-configure-gcp-project.md)
4. Configura IAM cross-cloud — [Runbook 04](docs/runbooks/04-configure-gcs-iam.md)
5. Deploya migrations V001-V007 via schemachange — [Runbook 05](docs/runbooks/05-deploy-migrations.md)
6. Build e deploy do Cloud Run Job — [Runbook 06](docs/runbooks/06-cloud-run-job.md)
7. Setup do dbt Workspace — [Runbook 07](docs/runbooks/07-setup-dbt-projects-snowflake.md)
8. Execução do dbt build — [Runbook 08](docs/runbooks/08-operating-dbt-workspace.md)
9. Configuração do GitHub Actions (opcional) — [Runbook 09](docs/runbooks/09-cicd-github-actions.md)


---

## Sobre

Projeto desenvolvido por **Leonardo Marinho**.
[LinkedIn](https://www.linkedin.com/in/devleomarinho/) | [Email](mailto:dev.leomarinho@gmail.com)
