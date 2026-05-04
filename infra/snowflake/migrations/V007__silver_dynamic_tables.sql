-- =====================================================================
-- V007__silver_dynamic_tables.sql
--
-- Objetivo: criar as Dynamic Tables da camada Silver.
--
-- 4 DTs, uma por tipo de evento:
-- - DT_ORDERS_CREATED
-- - DT_ORDERS_STATUS_CHANGED
-- - DT_CUSTOMERS_REGISTERED
-- - DT_CUSTOMERS_UPDATED
--
-- Cada DT:
-- - Le de Bronze.RAW_EVENTS filtrando por event_type
-- - Extrai campos do payload com tipagem explicita
-- - Deduplica por event_id (proteção ao at-least-once delivery)
-- - Refresh automatico via TARGET_LAG = '5 minutes'
--
-- Filosofia: Bronze e cru e imutavel; Silver e tipado, deduplicado e
-- pronto para consumo de Gold.
--
-- Idempotencia: usamos CREATE OR REPLACE. Diferente de Storage
-- Integrations, recriar Dynamic Tables nao quebra nada externo —
-- elas sao re-populadas no proximo refresh.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Pre-requisito: ROLE_DEPLOY pode assumir ROLE_TRANSFORMER
-- (Idempotente: no-op se ja existe)
-- ---------------------------------------------------------------------
GRANT ROLE ROLE_TRANSFORMER TO ROLE ROLE_DEPLOY;

USE ROLE ROLE_TRANSFORMER;
USE WAREHOUSE WH_TRANSFORM_S;
USE DATABASE {{ database_name }};
USE SCHEMA SILVER;

-- =====================================================================
-- DT_ORDERS_CREATED
-- =====================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_ORDERS_CREATED
    TARGET_LAG    = '5 minutes'
    WAREHOUSE     = WH_TRANSFORM_S
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    COMMENT       = 'Eventos order_created tipados e deduplicados (Silver)'
AS
SELECT
    raw_data:event_id::STRING                       AS event_id,
    raw_data:event_timestamp::TIMESTAMP_NTZ         AS event_timestamp,
    raw_data:event_version::STRING                  AS event_version,

    raw_data:payload:order_id::STRING               AS order_id,
    raw_data:payload:customer_id::STRING            AS customer_id,
    raw_data:payload:amount::DECIMAL(10, 2)         AS amount,
    raw_data:payload:currency::STRING               AS currency,
    raw_data:payload:item_count::INT                AS item_count,

    _source_file,
    _ingested_at
FROM {{ database_name }}.BRONZE.RAW_EVENTS
WHERE raw_data:event_type::STRING = 'order_created'

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1;

-- =====================================================================
-- DT_ORDERS_STATUS_CHANGED
-- =====================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_ORDERS_STATUS_CHANGED
    TARGET_LAG    = '5 minutes'
    WAREHOUSE     = WH_TRANSFORM_S
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    COMMENT       = 'Eventos order_status_changed tipados e deduplicados (Silver)'
AS
SELECT
    raw_data:event_id::STRING                       AS event_id,
    raw_data:event_timestamp::TIMESTAMP_NTZ         AS event_timestamp,
    raw_data:event_version::STRING                  AS event_version,

    raw_data:payload:order_id::STRING               AS order_id,
    raw_data:payload:old_status::STRING             AS old_status,
    raw_data:payload:new_status::STRING             AS new_status,

    _source_file,
    _ingested_at
FROM {{ database_name }}.BRONZE.RAW_EVENTS
WHERE raw_data:event_type::STRING = 'order_status_changed'

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1;

-- =====================================================================
-- DT_CUSTOMERS_REGISTERED
-- =====================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_CUSTOMERS_REGISTERED
    TARGET_LAG    = '5 minutes'
    WAREHOUSE     = WH_TRANSFORM_S
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    COMMENT       = 'Eventos customer_registered tipados e deduplicados (Silver)'
AS
SELECT
    raw_data:event_id::STRING                       AS event_id,
    raw_data:event_timestamp::TIMESTAMP_NTZ         AS event_timestamp,
    raw_data:event_version::STRING                  AS event_version,

    raw_data:payload:customer_id::STRING            AS customer_id,
    raw_data:payload:name::STRING                   AS customer_name,
    raw_data:payload:email::STRING                  AS email,
    raw_data:payload:state::STRING                  AS state,

    _source_file,
    _ingested_at
FROM {{ database_name }}.BRONZE.RAW_EVENTS
WHERE raw_data:event_type::STRING = 'customer_registered'

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1;

-- =====================================================================
-- DT_CUSTOMERS_UPDATED
-- =====================================================================
CREATE OR REPLACE DYNAMIC TABLE DT_CUSTOMERS_UPDATED
    TARGET_LAG    = '5 minutes'
    WAREHOUSE     = WH_TRANSFORM_S
    REFRESH_MODE  = AUTO
    INITIALIZE    = ON_CREATE
    COMMENT       = 'Eventos customer_updated tipados e deduplicados (Silver)'
AS
SELECT
    raw_data:event_id::STRING                       AS event_id,
    raw_data:event_timestamp::TIMESTAMP_NTZ         AS event_timestamp,
    raw_data:event_version::STRING                  AS event_version,

    raw_data:payload:customer_id::STRING            AS customer_id,
    raw_data:payload:field_changed::STRING          AS field_changed,
    raw_data:payload:old_value::STRING              AS old_value,
    raw_data:payload:new_value::STRING              AS new_value,

    _source_file,
    _ingested_at
FROM {{ database_name }}.BRONZE.RAW_EVENTS
WHERE raw_data:event_type::STRING = 'customer_updated'

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY raw_data:event_id::STRING
    ORDER BY _ingested_at
) = 1;