select
    tag as unidade_tag,
    descricao as unidade_descricao
from ENG_UNIDADE
where tag is not null and tag <> ''
