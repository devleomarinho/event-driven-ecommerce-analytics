-- =====================================================================
-- V005__notification_integrations.sql
--
-- Objetivo: bridge Pub/Sub <-> Snowpipe (auto-ingest).
--
-- ROLE: roda com ROLE_DEPLOY (default), que tem CREATE INTEGRATION
-- ON ACCOUNT. Ver ADR-008.
--
-- PRE-REQUISITO IAM: ver docs/runbooks/configure-gcs-iam.md.
-- =====================================================================

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS GCS_NOTIF_RAW_EVENTS_QA
    TYPE                          = QUEUE
    NOTIFICATION_PROVIDER         = GCP_PUBSUB
    ENABLED                       = TRUE
    GCP_PUBSUB_SUBSCRIPTION_NAME  = 'projects/event-driven-snowflake/subscriptions/gcs-notify-events-qa-snowflake'
    COMMENT                       = 'Pub/Sub subscription for Snowpipe auto-ingest (QA)';

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS GCS_NOTIF_RAW_EVENTS_PROD
    TYPE                          = QUEUE
    NOTIFICATION_PROVIDER         = GCP_PUBSUB
    ENABLED                       = TRUE
    GCP_PUBSUB_SUBSCRIPTION_NAME  = 'projects/event-driven-snowflake/subscriptions/gcs-notify-events-prod-snowflake'
    COMMENT                       = 'Pub/Sub subscription for Snowpipe auto-ingest (PROD)';

GRANT USAGE ON INTEGRATION GCS_NOTIF_RAW_EVENTS_QA   TO ROLE ROLE_INGESTION;
GRANT USAGE ON INTEGRATION GCS_NOTIF_RAW_EVENTS_PROD TO ROLE ROLE_INGESTION;