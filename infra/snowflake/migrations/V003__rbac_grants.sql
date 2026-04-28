-- =====================================================================
-- V003__rbac_grants.sql
--
-- Objetivo: conceder privilégios nas roles para o database do ambiente.
-- 
-- Esta migration é Jinja-aware: {{ database_name }} resolve para 
-- ANALYTICS_DEV, ANALYTICS_QA ou ANALYTICS_PROD conforme o env.yml.
-- 
-- FUTURE GRANTS garantem que novos objetos criados depois herdem
-- permissões automaticamente (essencial para dbt que cria models).
-- =====================================================================

USE ROLE SECURITYADMIN;

-- =====================================================================
-- WAREHOUSES — acesso a compute
-- =====================================================================
-- Ingestão usa WH_LOAD_XS; dbt usa WH_TRANSFORM_S; analistas WH_REPORTING_XS.
-- Isolamento por workload (FinOps + performance).
GRANT USAGE ON WAREHOUSE WH_LOAD_XS      TO ROLE ROLE_INGESTION;
GRANT USAGE ON WAREHOUSE WH_TRANSFORM_S  TO ROLE ROLE_TRANSFORMER;
GRANT USAGE ON WAREHOUSE WH_REPORTING_XS TO ROLE ROLE_ANALYST;

-- =====================================================================
-- DATABASE — navegação no database do ambiente
-- =====================================================================
GRANT USAGE ON DATABASE {{ database_name }} TO ROLE ROLE_INGESTION;
GRANT USAGE ON DATABASE {{ database_name }} TO ROLE ROLE_TRANSFORMER;
GRANT USAGE ON DATABASE {{ database_name }} TO ROLE ROLE_ANALYST;

-- =====================================================================
-- BRONZE — ingestão escreve, transformer lê
-- =====================================================================
GRANT USAGE ON SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_INGESTION;
GRANT USAGE ON SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_TRANSFORMER;

-- Ingestion precisa criar tables/stages/pipes (Snowpipe)
GRANT CREATE TABLE, CREATE STAGE, CREATE PIPE, CREATE FILE FORMAT
    ON SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_INGESTION;

-- Privilégios nos objetos existentes (por enquanto vazio; V004+ cria tabelas)
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_INGESTION;
GRANT SELECT         ON ALL TABLES IN SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_TRANSFORMER;

-- FUTURE GRANTS — core do design.
-- Quando V004 criar RAW_EVENTS, esses grants aplicam-se AUTOMATICAMENTE.
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_INGESTION;
GRANT SELECT         ON FUTURE TABLES IN SCHEMA {{ database_name }}.BRONZE TO ROLE ROLE_TRANSFORMER;

-- =====================================================================
-- SILVER — transformer escreve Dynamic Tables, analyst lê
-- =====================================================================
GRANT USAGE ON SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;
GRANT USAGE ON SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_ANALYST;

GRANT CREATE DYNAMIC TABLE, CREATE VIEW
    ON SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;

-- Existing + future dynamic tables e views
GRANT SELECT ON ALL    DYNAMIC TABLES IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON ALL    DYNAMIC TABLES IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_ANALYST;

GRANT SELECT ON ALL    VIEWS IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON ALL    VIEWS IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ database_name }}.SILVER TO ROLE ROLE_ANALYST;

-- =====================================================================
-- GOLD — transformer escreve (dbt), analyst lê
-- =====================================================================
GRANT USAGE ON SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;
GRANT USAGE ON SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_ANALYST;

GRANT CREATE TABLE, CREATE VIEW, CREATE MATERIALIZED VIEW
    ON SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;

-- Existing + future tables (dbt cria models como tables)
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE 
    ON ALL    TABLES IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE 
    ON FUTURE TABLES IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;

GRANT SELECT ON ALL    TABLES IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_ANALYST;

-- Views (dbt também pode criar views para marts "leves")
GRANT SELECT ON ALL    VIEWS IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_TRANSFORMER;
GRANT SELECT ON ALL    VIEWS IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA {{ database_name }}.GOLD TO ROLE ROLE_ANALYST;