-- =====================================================================
-- V002__rbac_roles.sql
--
-- Objetivo: criar as roles funcionais do projeto.
-- 
-- Roles são objetos da conta (globais), não do database. Esta migration
-- é deployada em todos os ambientes, mas CREATE ROLE IF NOT EXISTS 
-- garante idempotência — roles nascem no primeiro ambiente deployado

-- =====================================================================

USE ROLE USERADMIN;  -- role padrão para gerenciar roles/usuários

-- ---------------------------------------------------------------------
-- ROLE_INGESTION — service account do Snowpipe / ingestão
-- Least privilege: só escreve em Bronze, zero acesso a Silver/Gold.
-- Se a chave vazar, blast radius = reescrita de Bronze apenas.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ROLE_INGESTION
    COMMENT = 'Service account: Snowpipe + Cloud Functions. Escreve em Bronze apenas.';

-- ---------------------------------------------------------------------
-- ROLE_TRANSFORMER — service account do dbt
-- Lê Bronze/Silver, escreve Silver/Gold. Roda as transformações.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ROLE_TRANSFORMER
    COMMENT = 'Service account: dbt. Transforma Bronze/Silver → Gold.';

-- ---------------------------------------------------------------------
-- ROLE_ANALYST — consumo (você + BI + ad-hoc)
-- Read-only em Gold. Não acessa Bronze/Silver.
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS ROLE_ANALYST
    COMMENT = 'Consumo: analistas, BI, ad-hoc. Read-only em Gold.';

-- ---------------------------------------------------------------------
-- Hierarquia: toda role funcional sobe para SYSADMIN.
-- Padrão Snowflake — garante que SYSADMIN mantém visibilidade sobre
-- todos os objetos criados por essas roles.
-- ---------------------------------------------------------------------
USE ROLE SECURITYADMIN;

GRANT ROLE ROLE_INGESTION    TO ROLE SYSADMIN;
GRANT ROLE ROLE_TRANSFORMER  TO ROLE SYSADMIN;
GRANT ROLE ROLE_ANALYST      TO ROLE SYSADMIN;