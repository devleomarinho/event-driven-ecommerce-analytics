{{ config(materialized='view') }}

with source as (
    select * from {{ source('silver', 'dt_customers_updated') }}
),

renamed as (
    select
        -- Identificadores
        event_id,
        customer_id,

        -- Tempo
        event_timestamp as updated_at,

        -- O que mudou
        field_changed,
        old_value,
        new_value,

        -- Auditoria
        _ingested_at as ingested_at
    from source
)

select * from renamed