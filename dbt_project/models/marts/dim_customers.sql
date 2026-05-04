{{ config(materialized='table') }}

with registered as (
    select * from {{ ref('stg_customers_registered') }}
),

updates as (
    select * from {{ ref('stg_customers_updated') }}
),

-- ---------------------------------------------------------------------
-- Pega o ultimo valor de cada campo que pode mudar
-- (email, state) por customer_id
-- ---------------------------------------------------------------------
latest_email as (
    select
        customer_id,
        new_value as email,
        updated_at
    from updates
    where field_changed = 'email'
    qualify row_number() over (
        partition by customer_id 
        order by updated_at desc
    ) = 1
),

latest_state as (
    select
        customer_id,
        new_value as state,
        updated_at
    from updates
    where field_changed = 'state'
    qualify row_number() over (
        partition by customer_id 
        order by updated_at desc
    ) = 1
),

-- ---------------------------------------------------------------------
-- Combina registered + ultimas mudancas para reconstruir estado atual
-- ---------------------------------------------------------------------
final as (
    select
        -- Surrogate key (chave substituta tecnica)
        -- Em dimensoes, e boa pratica ter SK alem da NK (natural key).
        -- MD5 garante chave estavel mesmo se source mudar.
        md5(r.customer_id) as customer_sk,

        -- Natural key
        r.customer_id,

        -- Atributos atuais (com COALESCE = pega update se houver, senao original)
        r.customer_name,
        coalesce(le.email, r.email) as email,
        coalesce(ls.state, r.state) as state,

        -- Atributos temporais
        r.registered_at,
        greatest(
            r.registered_at,
            coalesce(le.updated_at, r.registered_at),
            coalesce(ls.updated_at, r.registered_at)
        ) as last_updated_at,

        -- Flags utilitarias
        case 
            when le.customer_id is not null or ls.customer_id is not null 
            then true 
            else false 
        end as has_been_updated

    from registered r
    left join latest_email le on r.customer_id = le.customer_id
    left join latest_state ls on r.customer_id = ls.customer_id
)

select * from final