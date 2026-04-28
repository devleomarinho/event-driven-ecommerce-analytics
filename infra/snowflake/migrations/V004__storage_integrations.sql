-- =====================================================================
-- V004__storage_integrations.sql
--
-- Objetivo: criar Storage Integrations Snowflake <-> GCS para QA e PROD.
--
-- Storage Integration eh o mecanismo SEGURO da Snowflake para acessar
-- buckets GCS sem credenciais de longo prazo. A Snowflake gera um
-- service account GCP cuja chave NUNCA fica exposta. O acesso ao
-- bucket eh concedido via IAM no GCP (passo manual, ver runbook).
--
-- IDEMPOTENCIA: usamos IF NOT EXISTS (e nao CREATE OR REPLACE) porque
-- recriar a integration invalidaria o service account gerado, quebrando
-- a configuracao de IAM no GCP.
--
-- ROLE: esta migration roda com ROLE_DEPLOY (role default do SVC_DEPLOY).
-- ROLE_DEPLOY recebeu GRANT CREATE INTEGRATION ON ACCOUNT no bootstrap,
-- privilegio minimo necessario sem dar ACCOUNTADMIN ao service account
-- de deploy. 
--
-- PRE-REQUISITO: passo manual em docs/runbooks/configure-gcs-iam.md
-- precisa ser executado APOS o primeiro deploy desta migration.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Storage Integration — QA
-- ---------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS GCS_INT_RAW_EVENTS_QA
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'GCS'
    ENABLED                   = TRUE
    STORAGE_ALLOWED_LOCATIONS = ('gcs://raw-events-qa/events/')
    COMMENT                   = 'GCS access for Bronze raw events ingestion (QA)';

-- ---------------------------------------------------------------------
-- Storage Integration — PROD
-- ---------------------------------------------------------------------
CREATE STORAGE INTEGRATION IF NOT EXISTS GCS_INT_RAW_EVENTS_PROD
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'GCS'
    ENABLED                   = TRUE
    STORAGE_ALLOWED_LOCATIONS = ('gcs://raw-events-prod/events/')
    COMMENT                   = 'GCS access for Bronze raw events ingestion (PROD)';

-- ---------------------------------------------------------------------
-- Grants: ROLE_INGESTION usa as integrations para criar stages
-- ---------------------------------------------------------------------
GRANT USAGE ON INTEGRATION GCS_INT_RAW_EVENTS_QA   TO ROLE ROLE_INGESTION;
GRANT USAGE ON INTEGRATION GCS_INT_RAW_EVENTS_PROD TO ROLE ROLE_INGESTION;