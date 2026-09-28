# Contribuindo para o dbt-firebird

Obrigado pelo interesse! Este documento descreve como preparar o ambiente,
rodar os testes e abrir contribuições.

## Requisitos

- Python 3.9+ (desenvolvido com 3.12)
- Servidor Firebird local (3.0+; desenvolvido e validado no 5.0) na porta 3050
- Usuário/senha de teste (por padrão `SYSDBA`/`masterkey`, configuráveis em `tests/conftest.py`)

## Ambiente

```bash
git clone https://github.com/flozer/dbt-firebird
cd dbt-firebird
python -m venv .venv
.venv/Scripts/pip install -e .[dev]   # Linux/macOS: .venv/bin/pip install -e .[dev]
```

> **Nota sobre instalação editável:** com `pip install -e`, o `dbt --version`
> e o `dbt init` podem **não listar** o adaptador — a enumeração do dbt-core
> usa varredura física de `dbt/adapters/*/__version__.py`, que instaladores
> editáveis modernos (finder) não expõem. Os testes `pytest` continuam
> funcionando (importam o adaptador diretamente). Para testar o `dbt init`
> ou o `dbt --version` com o código atual, instale não-editável:
> `pip install --force-reinstall --no-deps .`

## Testes

```bash
# suítes oficiais do dbt-tests-adapter (cria/limpa tests/db_test.fdb automaticamente)
.venv/Scripts/pytest tests/adapter -v

# projeto de exemplo contra um banco local (ajuste example/profiles.yml)
cd example
../.venv/Scripts/dbt seed --profiles-dir .
../.venv/Scripts/dbt run --profiles-dir .
```

O banco de testes (`tests/db_test.fdb`) é **limpo no início de cada sessão
pytest** — não aponte `FIREBIRD_TEST_DB_PATH` para uma base com dados reais.

## Regras do dialeto (importante para contribuir)

O Firebird tem restrições que o adaptador contorna — leia o README (seção
"Como o adaptador funciona") antes de alterar macros:

- DDL não é visível ao DML na mesma transação (snapshot de metadados):
  commitar entre CREATE e INSERT.
- Não existem: CTAS, `EXCEPT`/`INTERSECT`, `LIMIT`, `RENAME TABLE`,
  `DROP ... IF EXISTS`, `MD5()`, INSERT multi-row, `TRUNCATE`.
- Substituição de tabela atômica = staging commitada + `DELETE + INSERT` na
  mesma transação (MVCC).

## Abrindo contribuições

1. Abra uma issue descrevendo o problema/proposta (com SQL de reprodução).
2. Crie um branch descritivo (`feat/...`, `fix/...`).
3. Mantenha os testes verdes (`pytest tests/adapter`) e inclua testes para
   correções novas.
4. Abra o Pull Request referenciando a issue.
