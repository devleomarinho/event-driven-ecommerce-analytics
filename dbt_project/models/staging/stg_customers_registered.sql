{{ config(materialized='view') }}

with source as (
    select * from {{ source('silver', 'dt_customers_registered') }}
),

renamed as (
    select
        -- Identificadores
        event_id,
        customer_id,

        -- Tempo
        event_timestamp as registered_at,

        -- Atributos do customer
        customer_name,
        email,
        state,

        -- Auditoria
        _ingested_at as ingested_at
    from source
)

select * from renamed