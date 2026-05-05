# Event-Driven Pipeline for E-commerce: GCP + Snowflake + dbt

[![GitHub Actions](https://github.com/devleomarinho/event-driven-ecommerce-analytics/actions/workflows/schemachange.yml/badge.svg)](https://github.com/devleomarinho/event-driven-ecommerce-analytics/actions)
![Snowflake](https://img.shields.io/badge/Snowflake-Enterprise-29B5E8)
![dbt](https://img.shields.io/badge/dbt-1.9-FF694B)
![Python](https://img.shields.io/badge/Python-3.13-3776AB)

A complete **event-driven** analytics pipeline integrating Google Cloud Platform and Snowflake. The project demonstrates near-real-time ingestion, dimensional modeling on top of a medallion architecture (Bronze/Silver/Gold), and versioned IaC (Infrastructure as Code) deployment.

> 🇧🇷 Para versão em português, veja [README.md](README.md).

---

## Why event-driven architecture?

Traditional analytics pipelines run on **scheduled batch**: every N minutes/hours, a job checks for new data and processes it. This model has three well-known problems:

1. **Fixed latency tied to the schedule.** Even if data arrives in seconds, consumers only see it after the next scheduled run.
2. **Wasted polling.** Most executions find no new data, but still pay the cost of starting up and querying.
3. **Invisible backpressure.** If the producer speeds up, the scheduled consumer may fall behind, silently increasing the lag.

Event-driven architecture inverts this logic: each component reacts to notifications from the previous one, with no scheduled load. Latency is proportional to actual processing time, not to the schedule frequency. Compute cost is proportional to event volume, not to elapsed time.

In this project, **no stage uses polling**:

- The producer (Cloud Run Job) writes directly to GCS when it executes.
- GCS emits a Pub/Sub notification at write time.
- Snowflake (via Snowpipe + Notification Integration) consumes the queue and ingests the file.
- Bronze → Silver via Dynamic Tables with `TARGET_LAG = 5 minutes` (declarative, optimized by Snowflake).
- Gold via dbt, executed on demand inside Snowsight Workspace.

Typical end-to-end latency (from GCS upload to data available in Bronze) is **less than 1 minute**.

---

## Use case: e-commerce

The project models a fictional e-commerce operation that produces four types of domain events:

| Event | Meaning |
|---|---|
| `customer_registered` | Initial customer registration |
| `customer_updated` | Change to a customer attribute (email, state) |
| `order_created` | Order creation |
| `order_status_changed` | Order status transition (paid, shipped, delivered) |

These events arrive as NDJSON in GCS, are typed and deduplicated in Silver (Dynamic Tables), and modeled as a star schema in Gold (dbt). The final tables answer common analytical questions:

- What is daily revenue by state?
- Where are pending orders (by status)?
- How long does it take, on average, between creation and delivery?
- What is the average order value by region?

---

## Architecture

```text
                  GCP                                            Snowflake

  ┌──────────────────────────────┐               ┌──────────────────────────────────┐
  │                              │               │                                  │
  │    Cloud Run Job (Python)    │               │   Bronze (RAW_EVENTS)            │
  │    └─ Faker + coherent       │               │   └─ raw_data: VARIANT (NDJSON)  │
  │       batch logic            │               │      _source_file, _ingested_at  │
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
  │    PULL Subscription ────────┼──── auto ────▶│   Gold (dbt models)              │
  │                              │    ingest     │   ├─ Staging (4 views)           │
  │                              │               │   ├─ Dimensions (3 tables)       │
  └──────────────────────────────┘               │   ├─ Facts (2 tables)            │
                                                 │   └─ Marts (2 tables)            │
                                                 │                                  │
                                                 └──────────────────────────────────┘
```

### Key features

- **Event-driven end-to-end**: no component polls. Each one reacts to the previous notification.
- **Three isolated environments** (`DEV`, `QA`, `PROD`): each with its own database, schemas, and dedicated `CHANGE_HISTORY`.
- **Infrastructure as Code**: schemachange for Snowflake (versioned DDL), idempotent PowerShell scripts for GCP.
- **Schemachange CI/CD via GitHub Actions**: branches mapped to environments, with manual approval for PROD.
- **Least-privilege RBAC**: 3 functional roles + ROLE_DEPLOY for automation.

---

## Technology stack

| Layer | Technology | Rationale |
|---|---|---|
| Cloud | Google Cloud Platform | Selected stack; native integration with Snowflake via Storage and Notification Integrations |
| Messaging | Pub/Sub | Notification between GCS and Snowflake |
| Event storage | GCS | Persistence and replay layer; immutable files |
| Compute (generation) | Cloud Run Job | On-demand batch execution |
| Data Warehouse | Snowflake (Enterprise edition) | Support for Dynamic Tables, Snowpipe, dbt Projects on Snowflake |
| DDL Migrations | schemachange | Versioned SQL; idempotent; lightweight alternative to Terraform |
| Analytical transformations | dbt (via Snowsight Workspace) | Industry standard; native Snowflake support |
| Language | Python 3.13 | Cloud Run Job (Faker) |
| Container | Docker (build via GCP Artifact) | Cloud Run Job image |
| CI/CD | GitHub Actions | Automated schemachange deployment |
| Synthetic data generation | Faker (pt_BR) | Realistic Portuguese-language events in NDJSON format |

---

## Repository structure

```text
.
├── infra/
│   └── snowflake/
│       ├── environments/                # schemachange configs per environment
│       │   ├── dev.yml
│       │   ├── qa.yml
│       │   └── prod.yml
│       ├── migrations/                  # versioned SQL V001...V007
│
├── ingestion/                           # event generator (Cloud Run Job)
│   ├── main.py                          # CLI + Cloud Run Job entry point
│   ├── schemas.py                       # event dataclasses
│   ├── generator.py                     # generation with Faker + coherent batches
│   ├── publisher.py                     # NDJSON upload to GCS
│   ├── Dockerfile
│   ├── requirements.txt
│   └── pyproject.toml
├── dbt_project/                         # dbt project (Gold layer)
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── models/
│   │   ├── staging/                     # views over Silver
│   │   └── marts/                       # dims, facts, marts
│   ├── macros/
│   │   └── generate_schema_name.sql     # custom macro to avoid GOLD_GOLD
│   └── seeds/
│       └── dim_products.csv             # static seed
├── scripts/                             # local automation
│   ├── load-env.ps1
│   ├── generate-keypair.sh
│   └── setup-gcp-pubsub.ps1
├── docs/
│   ├── runbooks/                        # 09 operational runbooks
│
└── .github/
    └── workflows/
        └── schemachange.yml             # schemachange CI/CD
```

---

## Data warehouse layers

### Bronze — `ANALYTICS_<env>.BRONZE.RAW_EVENTS`

Immutable persistence layer for raw events. Minimalist structure:

```sql
RAW_EVENTS (
    raw_data        VARIANT       NOT NULL,    -- full event JSON
    _source_file    STRING        NOT NULL,    -- source file name
    _ingested_at    TIMESTAMP_NTZ NOT NULL     -- when it landed in Snowflake
)
```

Philosophy: **schema-on-read**. The entire event structure (event_id, event_type, payload) lives inside VARIANT — typed extraction happens in Silver. Advantage: Bronze never breaks due to producer schema changes; it is the source of truth for reprocessing.

### Silver — `ANALYTICS_<env>.SILVER.*`

Four Dynamic Tables (one per event type), with `TARGET_LAG = 5 minutes`:

- `DT_ORDERS_CREATED`
- `DT_ORDERS_STATUS_CHANGED`
- `DT_CUSTOMERS_REGISTERED`
- `DT_CUSTOMERS_UPDATED`

Each DT extracts payload fields with explicit typing (DECIMAL for amounts, TIMESTAMP_NTZ for timestamps, etc.) and deduplicates by `event_id` (protection against Pub/Sub at-least-once delivery):

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1
```

### Gold — `ANALYTICS_<env>.GOLD.*` (via dbt)

Star-schema dimensional modeling:

**Staging (views — light abstraction over Silver):**
- `STG_ORDERS_CREATED`, `STG_ORDERS_STATUS_CHANGED`
- `STG_CUSTOMERS_REGISTERED`, `STG_CUSTOMERS_UPDATED`

**Dimensions:**
- `DIM_CUSTOMERS` — SCD1 (current state with most recent email/state via updates). MD5 surrogate key.
- `DIM_DATE` — 2024-2027 calendar generated via `GENERATOR(ROWCOUNT)`. Date key in YYYYMMDD format.
- `DIM_PRODUCTS` — CSV seed with 20 products (static catalog to demonstrate `dbt seed`).

**Facts:**
- `FCT_ORDERS` — snapshot fact (1 row per order with current state).
- `FCT_ORDER_LIFECYCLE` — transactional fact (1 row per status_change).

**Marts:**
- `MART_DAILY_REVENUE` — daily revenue by state, with conversion rates and average order value.
- `MART_ORDER_FUNNEL` — distribution of orders by current status.

---

## Synthetic data generation

The generator (`ingestion/`) produces coherent batches of related events, simulating natural e-commerce behavior:

- **70% happy_path**: customer_registered → order_created → order_status_changed
- **20% with_update**: customer_registered → customer_updated → order_created
- **10% multiple_orders**: customer_registered → order_created → order_created (same customer)

Each batch produces **1 NDJSON file with 3 coherent events** (same customer_id when applicable). A standard run generates 50 batches ≈ 150 events with preserved identity correlation.

---

## CI/CD

### Schemachange via GitHub Actions

Migration deployment is fully automated:

```text
git push to feature/*  →  GitHub Actions  →  schemachange deploy DEV
git push to develop    →  GitHub Actions  →  schemachange deploy QA
git push to main       →  GitHub Actions  →  schemachange deploy PROD (with approval)
```

**Branch → environment mapping**: implemented inside the workflow (no need for `dev`, `qa`, or `prod` branches in Git; only `feature/*`, `develop`, and `main`).

**Environment Protection**: the `prod` environment in GitHub requires manual approval before deployment (a second check after merge to main).

**Idempotency**: schemachange compares migration checksums with the environment's `CHANGE_HISTORY`. Migrations already applied automatically become no-ops.

### Manual dbt development

dbt is **not in CI/CD** in this project, by deliberate choice. Cause: the current Snowflake account is trial, which **does not allow External Access Integration**. Since `dbt deps` (and some `EXECUTE DBT PROJECT` operations) may require external access, the automated pipeline is unavailable.

Current workflow: dbt is edited and executed **directly in the Snowsight Workspace** (connected to the repo via Git Integration). Commits made through the Workspace UI are pushed to the repo; repo changes appear in the Workspace via "Sync changes".

On a Standard+ account, the automated pattern would be:

```yaml
- run: |
    snow sql -q "ALTER GIT REPOSITORY ... FETCH;"
    snow dbt deploy DBT_EVENT_DRIVEN_ANALYTICS
    snow dbt execute DBT_EVENT_DRIVEN_ANALYTICS --args "build --target qa"
```

### Manual Cloud Run Job

The Cloud Run Job is deployed manually via `gcloud` commands documented in Runbook 06. In real production, it would be automated following the same pattern as schemachange (GitHub Actions with `gcloud builds submit` + `gcloud run jobs deploy`).

---

## Architectural decisions

This section documents the project's most relevant technical choices and the reasoning behind each one.

### ADR-001: Pure Bronze (3 columns) instead of structured schema

**Decision.** The `RAW_EVENTS` table has only 3 columns: `raw_data` (VARIANT), `_source_file`, and `_ingested_at`. The entire event structure (event_id, event_type, payload, etc.) lives inside VARIANT.

**Alternative considered.** "Minimally structured" Bronze with typed columns for event_id, event_type, event_timestamp, and VARIANT only for the variable payload.

**Reasons.**

- Schema-on-read removes coupling with the producer. Changes to event schemas don't break Bronze.
- Bronze stays conceptually clear: "literal copy of what arrived". Typing and validation happen in Silver, where they make sense for downstream queries.
- In real production, the event validator at the producer (which could be Pydantic, Avro Schema Registry, etc.) is the first line of defense. Bronze is the second — it preserves everything, even if the validator fails.

### ADR-002: Dynamic Tables instead of Streams + Tasks

**Decision.** The Silver layer uses Dynamic Tables with `TARGET_LAG = 5 minutes`.

**Alternative considered.** The classic Snowflake pattern is Streams (CDC over tables) + Tasks (scheduled jobs that consume the stream and run MERGE/INSERT). This pattern is mature but requires significant procedural code.

**Reasons.**

- Dynamic Tables are **declarative**: you describe the desired result in SQL and Snowflake decides when to re-process. No orchestration code.
- Incremental refresh is automatic when possible (our case, since Bronze is insert-only).
- TARGET_LAG is an SLA, not a schedule. Snowflake optimizes when to run based on when data arrives.

### ADR-003: dbt Projects on Snowflake instead of local dbt Core

**Decision.** The Gold layer uses dbt Projects on Snowflake, executed via Snowsight Workspace.

**Alternative considered.** dbt Core installed locally, connecting to Snowflake via `profiles.yml` (traditional pattern).

**Reasons.**

- New Snowflake feature (GA in 2024). Demonstrates technical currency and exploration of releases.
- Reduces operational surface: dbt runs inside Snowflake, with no need for external credentials, local Python environment, or separate scheduling.
- Integrated Workspace provides web IDE, bidirectional Git sync, and command execution (run, test, build) without extra tooling.

**Trade-off.** Stronger lock-in with Snowflake. In a multi-cloud project or one requiring adapter portability, dbt Core would be the right choice.

### ADR-004: Cloud Run Job instead of Cloud Function

**Decision.** The event generator is containerized as a Cloud Run Job, executed on demand via `gcloud run jobs execute`.

**Alternative considered.** HTTP-triggered Cloud Function.

**Reasons.**

- Cloud Run Job is the correct abstraction for **batch jobs**. Cloud Function is optimized for request-response and requires an HTTP wrapper that adds no value to the task.
- For the use case (manually executing whenever data needs to be generated), there is no need for a running HTTP server.
- Scheduling, if needed, can be added via Cloud Scheduler with the same simplicity.

### ADR-005: Lean RBAC (3 functional roles)

**Decision.** The project uses 3 functional roles (`ROLE_INGESTION`, `ROLE_TRANSFORMER`, `ROLE_ANALYST`) + 1 automation role (`ROLE_DEPLOY`).

**Alternative considered.** Full hierarchy of Access Roles (read/write per schema) + Functional Roles, the pattern recommended by Snowflake for large organizations.

**Reasons.**

- 3 functional roles already demonstrate the least-privilege concept: each role has a specific purpose (ingestion, transformation, analytical reads).
- ROLE_DEPLOY assumes other roles via grant (`GRANT ROLE ROLE_INGESTION TO ROLE ROLE_DEPLOY`), allowing objects created in deploy to have semantically correct ownership (ROLE_INGESTION for Bronze, ROLE_TRANSFORMER for Silver/Gold).

**Known trade-off.** Simplicity comes at a cost: during development, ownership conflicts were observed when objects were created manually in sandbox (with role X) and later recreated via migration (with role Y). In real production, a more formal hierarchy prevents this.

---

## Setup and operation

Initial configuration involves manual steps (Snowflake key-pair, GCP IAM, GitHub secrets). Each is documented as a runbook in `docs/runbooks/`:

| # | Runbook | Content |
|---|---|---|
| 01 | Snowflake Bootstrap | Service account, key-pair, deploy role |
| 02 | Local environment configuration | schemachange, Snowflake CLI, environment variables |
| 03 | GCP project setup | APIs, buckets, Pub/Sub topics, subscriptions |
| 04 | GCP IAM for Snowflake | Bindings between Snowflake service accounts and GCP resources |
| 05 | Migration deployment | Using schemachange against DEV, QA, and PROD |
| 06 | Cloud Run Job | Image build, deploy, manual execution |
| 07 | dbt Projects on Snowflake setup | Prerequisites, API Integration, Git Repository, Workspace |
| 08 | Operating dbt in the Workspace | Development workflow, useful commands, troubleshooting |
| 09 | CI/CD with GitHub Actions | Secrets configuration, environments, workflow |

---

## How to reproduce

To reproduce the project:

1. Configure Snowflake account — [Runbook 01](docs/runbooks/01-bootstrap-snowflake.md)
2. Configure local environment — [Runbook 02](docs/runbooks/02-configure-local-environment.md)
3. Configure GCP project with APIs enabled — [Runbook 03](docs/runbooks/03-configure-gcp-project.md)
4. Configure cross-cloud IAM — [Runbook 04](docs/runbooks/04-configure-gcs-iam.md)
5. Deploy migrations V001-V007 via schemachange — [Runbook 05](docs/runbooks/05-deploy-migrations.md)
6. Build and deploy the Cloud Run Job — [Runbook 06](docs/runbooks/06-cloud-run-job.md)
7. dbt Workspace setup — [Runbook 07](docs/runbooks/07-setup-dbt-projects-snowflake.md)
8. Running dbt build — [Runbook 08](docs/runbooks/08-operating-dbt-workspace.md)
9. GitHub Actions configuration (optional) — [Runbook 09](docs/runbooks/09-cicd-github-actions.md)


---

## About

Project developed by **Leonardo Marinho**.
[LinkedIn](https://www.linkedin.com/in/devleomarinho/) | [Email](mailto:dev.leomarinho@gmail.com)
