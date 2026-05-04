-- =====================================================================
-- V006__bronze_raw_events_layer.sql
--
-- Objetivo: criar a camada Bronze — tabela RAW_EVENTS + objetos de
-- ingestao (file format, stage, pipe).
--
-- Filosofia Bronze pura:
-- A tabela armazena o JSON original em VARIANT, sem extracao de campos.
-- Toda transformacao acontece em Silver via Dynamic Tables.
--
-- Topologia de ambientes:
-- - DEV nao recebe eventos via Pub/Sub (populado via clone de QA).
--   Criamos apenas FILE FORMAT e TABLE; STAGE e PIPE sao pulados.
-- - QA e PROD recebem eventos reais.
--
-- Role:
-- Esta migration assume ROLE_INGESTION para que ela seja owner dos
-- objetos criados (semanticamente correto em producao).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Pre-requisito: permitir que ROLE_DEPLOY assuma ROLE_INGESTION
-- ---------------------------------------------------------------------
GRANT ROLE ROLE_INGESTION TO ROLE ROLE_DEPLOY;

USE ROLE ROLE_INGESTION;
USE WAREHOUSE WH_LOAD_XS;
USE DATABASE {{ database_name }};
USE SCHEMA BRONZE;

-- ---------------------------------------------------------------------
-- File Format: NDJSON
-- ---------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS FF_JSON_EVENTS
    TYPE                = JSON
    STRIP_OUTER_ARRAY   = FALSE
    COMPRESSION         = AUTO
    IGNORE_UTF8_ERRORS  = FALSE
    ALLOW_DUPLICATE     = FALSE
    DATE_FORMAT         = AUTO
    TIMESTAMP_FORMAT    = AUTO
    COMMENT             = 'NDJSON events from Cloud Function -> GCS -> Snowpipe';

-- ---------------------------------------------------------------------
-- Tabela RAW_EVENTS — Bronze pura (3 colunas)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW_EVENTS (
    raw_data        VARIANT       NOT NULL,
    _source_file    STRING        NOT NULL,
    _ingested_at    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Bronze raw events. Imutavel. Source of truth para reprocessamento.';

{% if env != 'dev' %}
-- ---------------------------------------------------------------------
-- Stage permanente — apontando para o bucket do ambiente
-- (Pulado em DEV)
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS STG_RAW_EVENTS_{{ env | upper }}
    STORAGE_INTEGRATION = GCS_INT_RAW_EVENTS_{{ env | upper }}
    URL                 = 'gcs://raw-events-{{ env }}/events/'
    FILE_FORMAT         = FF_JSON_EVENTS
    COMMENT             = 'External stage: raw events do bucket GCS ({{ env | upper }})';

-- ---------------------------------------------------------------------
-- Pipe — auto-ingest via notification integration
-- (Pulado em DEV)
-- ---------------------------------------------------------------------
CREATE PIPE IF NOT EXISTS PIPE_RAW_EVENTS_{{ env | upper }}
    AUTO_INGEST = TRUE
    INTEGRATION = 'GCS_NOTIF_RAW_EVENTS_{{ env | upper }}'
    COMMENT     = 'Auto-ingest raw events from GCS to RAW_EVENTS ({{ env | upper }})'
AS
COPY INTO BRONZE.RAW_EVENTS (raw_data, _source_file)
FROM (
    SELECT
        $1                AS raw_data,
        METADATA$FILENAME AS _source_file
    FROM @STG_RAW_EVENTS_{{ env | upper }}
)
FILE_FORMAT = (FORMAT_NAME = FF_JSON_EVENTS)
ON_ERROR    = 'SKIP_FILE_10%';
{% endif %}