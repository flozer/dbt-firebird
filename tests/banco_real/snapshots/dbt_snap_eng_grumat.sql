{% snapshot dbt_snap_eng_grumat %}

{{
    config(
        target_schema=schema,
        unique_key='grupo_tag',
        strategy='check',
        check_cols=['grupo_descricao'],
        invalidate_hard_deletes=True
    )
}}

-- Snapshot de leitura sobre a tabela REAL ENG_GRUMAT.
-- Execuções repetidas sem mudança nos dados devem executar o MERGE
-- e não alterar nenhuma linha (operação somente leitura na base do cliente).
--
-- Nota: o snapshot inicial foi apontado para ENG_UNIDADE e expôs um problema
-- real da base (TAG declarada VARCHAR(3) com valores de até 6 caracteres —
-- overfill). ENG_GRUMAT foi escolhida por ser íntegra.
select
    tag as grupo_tag,
    descricao as grupo_descricao
from ENG_GRUMAT

{% endsnapshot %}
