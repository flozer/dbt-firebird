{{
  config(materialized='table')
}}

-- Agregação sobre a tabela REAL ENG_MATERIAL (leitura limitada a 5000 linhas
-- para manter o teste rápido no banco de 66 GB), com join na tabela real de grupos.
select
    m.codgrumat,
    g.descricao as grupo_descricao,
    count(*) as qt_materiais,
    count(m.custo) as qt_com_custo,
    max(m.custo) as maior_custo
from (
    select first 5000 codgrumat, custo from ENG_MATERIAL
) m
left join ENG_GRUMAT g on g.tag = m.codgrumat
group by m.codgrumat, g.descricao
