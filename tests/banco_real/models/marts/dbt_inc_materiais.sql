{{
  config(
    materialized='incremental',
    unique_key='material_id'
  )
}}

-- Modelo incremental sobre o seed próprio (dados controlados): a segunda
-- execução, após adicionar linhas ao seed, deve APENAS anexar as novas.
select
    material_id,
    material_nome,
    valor
from {{ ref('dbt_seed_materiais') }}

{% if is_incremental() %}
where material_id > (select coalesce(max(material_id), 0) from {{ this }})
{% endif %}
