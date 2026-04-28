# Pipeline Event-Driven para E-commerce: GCP + Snowflake

Pipeline de analytics event-driven sobre dados de e-commerce, integrando Google
Cloud Platform e Snowflake. O projeto cobre ingestão em tempo real via Pub/Sub e
Snowpipe, modelagem dimensional em camadas (arquitetura medalhão), e versionamento completo
de infraestrutura como código com schemachange e Github Actions.

## Visão de alto nível

```text
       GCP                               Snowflake

  Cloud Function                    Bronze (raw VARIANT)
  (gera eventos)                            |
       |                                    v
       v                            Silver (Dynamic Tables)
  GCS bucket /events/                       |
       |                                    v
       v                            Gold (dbt — fact, dim)
  Pub/Sub notification                      |
       |                                    v
       v                            Marts (analytics-ready)
  Subscription PULL ----> Snowpipe -----+
                          (auto-ingest)
```




## Características

- **Event-driven end-to-end**: nenhuma etapa por polling. Cada componente reage
  a notificações da etapa anterior — Cloud Function trigger, GCS object create,
  Pub/Sub message, Snowpipe auto-ingest.
- **Três ambientes isolados**: DEV, QA e PROD, cada um com sua própria
  CHANGE_HISTORY de migrations. PROD é construído via promoção de QA, com testes
  integrados em ambiente real antes de produção.
- **Infraestrutura como código**: schemachange para Snowflake, scripts PowerShell
  para GCP. 
- **CI/CD com GitHub Actions**: pull requests rodam validação, merge na branch
  `main` deploya em produção.
- **RBAC com least privilege**: três roles funcionais (ingestão, transformação,
  consumo), service accounts isolados por workload, deploy automatizado sem
  ACCOUNTADMIN.

## Stack técnica

| Camada | Tecnologia |
|---|---|
| Cloud | Google Cloud Platform (GCP) |
| Mensageria | Pub/Sub |
| Storage | GCS |
| Compute (eventos) | Cloud Functions |
| Data Warehouse | Snowflake (Enterprise edition) |
| Migrations | schemachange |
| Transformações | dbt |
| Validação de eventos | Pydantic |
| Linguagem | Python |
| CI/CD | GitHub Actions |
| Testes de qualidade | dbt tests, dbt_artifacts |

## Arquitetura detalhada

```text
.
├── infra/
│   └── snowflake/
│       ├── environments/        # configs schemachange por ambiente
│       │   ├── dev.yml
│       │   ├── qa.yml
│       │   └── prod.yml
│       ├── migrations/          # SQL versionado (V001, V002, ...)
│       └── repeatable/          # scripts repeatable (R__*.sql)
├── ingestion/                   # Cloud Functions (produtor de eventos)
├── dbt/                         # projeto dbt (camada Gold)
├── scripts/                     # automação local (setup, deploy, key-pair)
├── docs/
│   ├── runbooks/                # passos manuais documentados
│   └── adr/                     # decisões arquiteturais
└── .github/workflows/           # CI/CD pipelines
```

## Modelagem dimensional

A camada Gold segue modelagem em estrela com fatos e dimensões orientadas
ao domínio de e-commerce:

**Fatos**
- `fct_orders`: granularidade por pedido
- `fct_order_items`: granularidade por item de pedido
- `fct_order_lifecycle`: eventos do ciclo de vida (created → paid → shipped → delivered)

**Dimensões**
- `dim_customers`: SCD Type 2 via dbt snapshots
- `dim_products`: dimensão estática (seed)
- `dim_date`: dimensão temporal pré-populada

**Marts**
- `mart_daily_revenue`: receita por dia, categoria, região
- `mart_customer_cohort`: análise de coorte de retenção
- `mart_order_funnel`: funil de conversão de pedidos

## Estrutura do repositório

```text
.
├── infra/
│   └── snowflake/
│       ├── environments/        # configs schemachange por ambiente
│       │   ├── dev.yml
│       │   ├── qa.yml
│       │   └── prod.yml
│       ├── migrations/          # SQL versionado (V001, V002, ...)
│       └── repeatable/          # scripts repeatable (R__*.sql)
├── ingestion/                   # Cloud Functions (produtor de eventos)
├── dbt/                         # projeto dbt (camada Gold)
├── scripts/                     # automação local (setup, deploy, key-pair)
├── docs/
│   ├── runbooks/                # passos manuais documentados
│   └── adr/                     # decisões arquiteturais
└── .github/workflows/           # CI/CD pipelines
```

## Decisões de arquitetura

Decisões importantes documentadas em `docs/adr/`. Entre elas:

- **schemachange sobre Terraform**: separação clara entre DDL (migrations) e
  state management. 
- **Três ambientes em conta única**: isolamento via databases distintos,
  com CHANGE_HISTORY separada por ambiente. 
- **Ingestão sem broker de eventos intermediário**: GCS atua como camada de
  persistência e replay; Pub/Sub serve apenas para notificação, não como
  event bus de domínio.
- **SVC_DEPLOY com privilégios mínimos**: service account de CI/CD recebe
  apenas SYSADMIN + SECURITYADMIN + CREATE INTEGRATION ON ACCOUNT. Operações
  que exigem ACCOUNTADMIN são executadas manualmente com acesso seguro via MFA.

## Setup e operação

A configuração inicial envolve passos manuais (key-pair Snowflake, IAM no GCP,
cadastro de secrets no GitHub). Cada um está documentado como runbook em
`docs/runbooks/`:

1. [Bootstrap do Snowflake](docs/runbooks/01-bootstrap-snowflake.md) —
   service account, key-pair, role de deploy
2. [Configuração do ambiente local](docs/runbooks/02-configure-local-environment.md) —
   schemachange, Snowflake CLI, variáveis de ambiente
3. [Setup do projeto GCP](docs/runbooks/03-configure-gcp-project.md) —
   APIs, buckets, tópicos Pub/Sub, subscriptions
4. [IAM GCP para Snowflake](docs/runbooks/04-configure-gcs-iam.md) —
   bindings entre service accounts da Snowflake e recursos GCP
5. [Deploy de migrations](docs/runbooks/05-deploy-migrations.md) —
   uso do schemachange contra DEV, QA e PROD
6. [Troubleshooting](docs/runbooks/06-troubleshooting.md) —
   erros comuns e diagnóstico

## CI/CD

GitHub Actions roda dois workflows principais:

- **Em pull requests**: validação SQL (lint), `schemachange deploy --dry-run`
  contra DEV, verificação de hashes (drift de migrations).
- **Em merge na `main`**: deploy automático em PROD, com aprovação manual via
  Environment Protection (uma camada de "change review" mesmo após merge).

Branch QA é promovida via merge de feature branches para `develop`, com deploy
automático em QA. Promoção QA → PROD via PR `develop → main`.

## Estado atual

Em desenvolvimento ativo. Componentes prontos:

- Bootstrap Snowflake e GCP
- Migrations V001 a V005 (warehouses, databases, schemas, RBAC, integrations)
- Validação end-to-end da ponte GCP ↔ Snowflake

Em construção:

- V006 (tabela RAW_EVENTS, Snowpipe, file formats)
- Cloud Function para geração de eventos sintéticos
- Camada Silver com Dynamic Tables
- Camada Gold com dbt
- Workflows de GitHub Actions

