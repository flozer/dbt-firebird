# AGENTS.md — Guia para agentes de IA e novos desenvolvedores

Instruções para trabalhar neste repositório (adaptador `dbt-firebird`) de
qualquer máquina. Leia este arquivo inteiro antes de alterar código.

## O que é este projeto

Adaptador [dbt-core](https://github.com/dbt-labs/dbt-core) (v1.8+, Python) para
bancos [Firebird](https://firebirdsql.org/) 3.0/4.0/5.0, sobre o pacote
`firebird-driver`. Publicado no PyPI como `dbt-firebird` (publicação **somente
manual**, com autorização do mantenedor — ver [RELEASE.md](RELEASE.md), que é
local-only e gitignored).

- **Repo:** https://github.com/flozer/dbt-firebird (público)
- **PyPI:** https://pypi.org/project/dbt-firebird/
- **Linguagem dos commits/docs do projeto:** português (BR)

## Estrutura

```
dbt/adapters/firebird/      # Credentials, ConnectionManager, Relation, Column, Adapter
dbt/include/firebird/       # macros do dialeto + materializations + profile_template
tests/adapter/              # suítes dbt-tests-adapter
tests/conftest.py           # fixtures (cria/limpa o banco de teste sozinho)
tests/banco_real/           # projeto dbt para validar contra base real (profiles local-only)
example/                    # projeto dbt de exemplo
.github/workflows/ci.yml    # CI: bandit + matriz Firebird 3/4/5 × Python 3.9/3.12
.github/workflows/publish.yml  # publish ao PyPI — SOMENTE manual (workflow_dispatch)
```

## Setup de ambiente

```bash
python -m venv .venv
.venv/Scripts/pip install -e .[dev]    # Linux/macOS: .venv/bin/pip install -e .[dev]
```

Requisito: um servidor Firebird local na porta 3050 (usuário/senha de teste:
`SYSDBA`/`masterkey`). Os testes criam e limpam `tests/db_test.fdb`
sozinhos — **não aponte `FIREBIRD_TEST_DB_PATH` para uma base com dados reais**.

### Armadilhas conhecidas

1. **Instalação editável (`pip install -e`) NÃO aparece no `dbt --version` nem
   no `dbt init`** — a enumeração do dbt-core é um glob físico de
   `dbt/adapters/*/__version__.py`. `pytest` funciona com `-e` (import direto).
   Para testar o dbt CLI com código novo:
   `pip install --force-reinstall --no-deps .`
2. **Partial parsing do dbt não detecta mudanças nos macros internos do
   adaptador** — ao testar um projeto após editar macros, rode `rm -rf target`
   no projeto.
3. **`gh` com múltiplas contas**: se push retornar 403, a conta ativa pode ter
   mudado — rode `gh auth switch --user flozer`.
4. `RELEASE.md` e `tests/banco_real/profiles.yml` são **locais** (gitignored).
   Não commitar caminhos/credenciais reais.

## Rodar os testes

```bash
.venv/Scripts/pytest tests/adapter -v        # suítes oficiais (6 passed, 7 skipped esperado)
.venv/Scripts/bandit -r dbt/adapters/firebird/ --skip B608   # análise estática
```

- A sessão pytest limpa o banco de teste no início; cada rodada leva ~1–4 min.
- Skips documentados em `tests/adapter/test_firebird.py` são limitações
  reais (FB3 31 chars, CTE `__dbt__cte__`, comparador de catálogo) — não
  "desperte" sem resolver a causa.
- O CI (`.github/workflows/ci.yml`) é `workflow_dispatch` (manual):
  `gh workflow run ci.yml --ref main`. Verifique a conta ativa do `gh`
  antes (item 3 acima).

## Regras do dialeto Firebird (CRÍTICO)

O dialeto tem restrições que ditam o design das materializations
(`dbt/include/firebird/macros/`). Resumo — detalhes completos no README:

- **DML não enxerga DDL da mesma transação** (snapshot de metadados):
  commitar entre CREATE e INSERT — as materializations fazem
  `adapter.commit()` explicitamente entre statements.
- **Não existem**: `CREATE TABLE AS SELECT`, `EXCEPT`/`INTERSECT`, `LIMIT`,
  `RENAME TABLE`, `DROP ... IF EXISTS`, `TRUNCATE`, `MD5()`, INSERT
  multi-row (`VALUES (..),(..)`), `ADD/DROP COLUMN` com keyword, e
  `select *, expr` (use `alias.*`).
- **Swap atômico de tabela**: staging commitada + `DELETE + INSERT` na mesma
  transação (MVCC dá consistência aos leitores).
- Transações usam **READ COMMITTED** com `lock_timeout` (profile, padrão 10s)
  e **retry automático (3x)** para conflitos de lock.
- Describe de colunas via **PREPARE** (`cursor.prepare` não executa);
  larguras de string vindas de UNION/CTE são imprecisas — o código aplica
  piso de 256 e `pad_columns_to_target`.
- `cursor.rowcount` lança erro após DDL — `get_response` trata.
- firebird-driver: commit invalida cursores abertos (fetch antes do commit);
  rollback/commit em transação inativa dispara assert.
- Valores válidos de `on_schema_change`: `ignore`, `fail`,
  `append_new_columns`, `sync_all_columns` (inválidos caem em `ignore`
  silenciosamente).

## Análise estática

`bandit` roda no CI com `--skip B608` (construção de SQL é a função de um
adaptador; valores são parametrizados `?` e identificadores quotados pelo
dbt). Achados B105/B110 legítimos recebem `# nosec Bxxx` em linha própria
**com comentário de justificativa separado** (bandit interpreta palavras
após o ID como nomes de teste).

## Publicar release

Procedimento em [RELEASE.md](RELEASE.md) (local-only) e resumo no
[CHANGELOG.md](CHANGELOG.md). Resumo: bump de versão (`pyproject.toml` +
`__version__.py` + CHANGELOG) → commit → tag → `gh workflow run
publish.yml --ref main` (requer Trusted Publisher configurado no PyPI —
já está). **Não publique sem autorização explícita do mantenedor.**

## Issues/PRs externos

- Responda issues no GitHub; contribuições seguem [CONTRIBUTING.md](CONTRIBUTING.md).
- Página oficial do adaptador: `docs.getdbt.com` →
  `connect-data-platform/firebird-setup` (mergeada; mudanças futuras de docs
  oficiais seguem o mesmo fluxo de PR na branch `current` daquele repo).
