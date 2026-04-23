-- =====================================================================
-- V001__warehouses_databases_schemas.sql
--
-- Objetivo: provisionar compute e topologia lógica para um ambiente.
-- Este arquivo é executado UMA VEZ por ambiente (DEV, QA, PROD).
--
-- Jinja vars esperadas:
--   - {{ env }}            ex: 'dev', 'qa', 'prod'
--   - {{ database_name }}  ex: 'ANALYTICS_DEV'
--   - {{ project_name }}   ex: 'event-driven-ecommerce'
-- =====================================================================

USE ROLE SYSADMIN;

-- ---------------------------------------------------------------------
-- WAREHOUSES — compartilhados entre ambientes.
-- CREATE IF NOT EXISTS: idempotente quando V001 roda para o 2º ambiente.

CREATE WAREHOUSE IF NOT EXISTS WH_LOAD_XS
    WITH WAREHOUSE_SIZE = 'XSMALL'
         AUTO_SUSPEND   = 60
         AUTO_RESUME    = TRUE
         INITIALLY_SUSPENDED = TRUE
         STATEMENT_TIMEOUT_IN_SECONDS = 1800
         COMMENT = 'Ingestão (Snowpipe REST/backfills) — {{ project_name }}';

CREATE WAREHOUSE IF NOT EXISTS WH_TRANSFORM_S
    WITH WAREHOUSE_SIZE = 'SMALL'
         AUTO_SUSPEND   = 60
         AUTO_RESUME    = TRUE
         INITIALLY_SUSPENDED = TRUE
         STATEMENT_TIMEOUT_IN_SECONDS = 3600
         COMMENT = 'Transformações dbt + Dynamic Tables — {{ project_name }}';

CREATE WAREHOUSE IF NOT EXISTS WH_REPORTING_XS
    WITH WAREHOUSE_SIZE = 'XSMALL'
         AUTO_SUSPEND   = 60
         AUTO_RESUME    = TRUE
         INITIALLY_SUSPENDED = TRUE
         STATEMENT_TIMEOUT_IN_SECONDS = 600
         COMMENT = 'BI / ad-hoc — {{ project_name }}';

-- ---------------------------------------------------------------------
-- DATABASE — um por ambiente. Nome parametrizado via Jinja.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS {{ database_name }}
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Analytics database — env={{ env }} project={{ project_name }}';

USE DATABASE {{ database_name }};

-- ---------------------------------------------------------------------
-- SCHEMAS — arquitetura medalhão
-- ---------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS BRONZE
    COMMENT = 'Raw events (VARIANT) — imutável, ingestão Snowpipe';

CREATE SCHEMA IF NOT EXISTS SILVER
    WITH MANAGED ACCESS
    COMMENT = 'Dynamic Tables — deduplicadas, tipadas, latest-state';

CREATE SCHEMA IF NOT EXISTS GOLD
    WITH MANAGED ACCESS
    COMMENT = 'Modelo dimensional (dbt) — fatos e dimensões';

-- ---------------------------------------------------------------------
-- Hardening: remove schema PUBLIC default.
-- PUBLIC vem com grants implícitos para a role PUBLIC — vetor de leak.
-- DROP IF EXISTS é idempotente.
-- ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS {{ database_name }}.PUBLIC;