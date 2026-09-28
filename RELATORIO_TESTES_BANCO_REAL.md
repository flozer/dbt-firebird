# Relatório de Testes — Banco Firebird Real

**Data:** 26/09/2026
**Ambiente:** máquina local (DEV), Windows, Firebird 5.0.3 (serviço na porta 3050)
**Base testada:** `C:\bases\restaurado.fdb` (caminho de teste; ~66 GB, 3.144 tabelas/views de usuário, charset `NONE`, dados em WIN1252)
**Credenciais:** SYSDBA / masterkey
**Software:** dbt-core 1.12.5 + dbt-firebird 0.1.0 instalados no Python do sistema (3.12) a partir do código-fonte local

Projeto de teste: [`tests/banco_real/`](tests/banco_real/) — os perfis apontam diretamente para a base real.

> **Escopo de escrita:** todos os objetos criados pelos testes usam o prefixo `dbt_`.
> As tabelas reais do cliente foram **apenas lidas**. A integridade foi conferida
> antes e depois dos testes (T10).

## Perfil de conexão validado

```yaml
type: firebird
host: localhost
port: 3050
path: C:/bases/restaurado.fdb
user: SYSDBA
password: masterkey
charset: WIN1252     # IMPORTANTE: base com charset NONE e dados em WIN1252
threads: 1
```

**Achado de configuração:** com `charset: UTF8` (padrão do adaptador), a leitura
desta base falha com `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe1`
(texto em WIN1252: 'á', 'Ç'). Usando `charset: WIN1252` no profile, todo o
pipeline funciona com acentuação correta. Bases 100% ASCII funcionam com UTF8.

## Matriz de testes

| # | Teste | Comando | Resultado | Tempo |
|---|-------|---------|-----------|-------|
| T1 | Verificação de conexão/credenciais | `dbt debug` | ✅ `All checks passed!` | 3,4 s |
| T2 | Parse do projeto | `dbt parse` | ✅ | 4,2 s |
| T3 | Seed (cria `dbt_seed_materiais`) | `dbt seed` | ✅ PASS=1 | 4,5 s |
| T4 | Run completo (2 views + 1 table + 1 incremental) sobre tabelas reais | `dbt run` | ✅ PASS=4 | 4,6 s |
| T5 | Testes genéricos (unique/not_null) | `dbt test` | ✅ PASS=4 / FAIL=1 (**esperado** — achado de dados, ver A1) | ~2 s |
| T6 | Snapshot 3× (criação + 2 merges sem mudança de dados) | `dbt snapshot` | ✅ PASS=1 ×3; 39 linhas, 39 chaves distintas | ~4 s cada |
| T7 | Incremental append: seed +2 linhas → re-seed → re-run | `dbt seed` + `dbt run -s dbt_inc_materiais` | ✅ 5 → 7 linhas (apenas as novas anexadas) | ~8 s |
| T8 | Full refresh (swap atômico de tabelas) | `dbt run --full-refresh` | ✅ PASS=4 | 4,8 s |
| T9 | Documentação com catálogo completo (3.144 relações) | `dbt docs generate` | ✅ catálogo gerado | 7,0 s |
| T10 | Integridade da base real | contagens antes/depois | ✅ ENG_UNIDADE 60, ENG_GRUMAT 39, FAMILIAS_OCUPACIONAIS 393 — inalteradas | — |

### Resultados detalhados de `dbt test` (T5)

| Teste | Resultado | Observação |
|---|---|---|
| `unique_dbt_stg_eng_grumat_grupo_tag` | ✅ | 39 tags, todas distintas |
| `not_null_dbt_stg_eng_grumat_grupo_tag` | ✅ | |
| `not_null_dbt_stg_eng_unidade_unidade_tag` | ✅ | (filtro `tag <> ''` no modelo) |
| `unique_dbt_stg_eng_unidade_unidade_tag` | ❌ 1 falha | **Achado real: tag 'KG' duplicada (2 linhas)** — ver A1 |
| `not_null_dbt_stg_eng_unidade_unidade_descricao` | ✅ | |

### Dados produzidos pelos modelos (amostra)

- `dbt_mart_materiais` (agregação de 5.000 materiais reais de ENG_MATERIAL):
  14 grupos; topo: MANUTENÇÕES (2.675 itens), ROCHAS ORNAMENTAIS (PRÓPRIO) (804),
  MATERIAL DE CONSTRUÇÃO (669) — acentuação preservada de ponta a ponta.
- `dbt_inc_materiais`: 7 linhas após o append.
- `dbt_snap_eng_grumat`: 39 linhas, estável entre execuções.

## Achados na base real (detectados pelos testes)

- **A1 — Duplicata em ENG_UNIDADE:** a tag `KG` aparece 2 vezes. Detectado pelo
  teste `unique` do dbt (falha esperada e desejada — é o teste funcionando).
- **A2 — Overfill em ENG_UNIDADE.TAG:** a coluna está declarada `VARCHAR(3)`,
  porém contém valores de até **6 caracteres** (dado legado da restauração).
  Qualquer `INSERT` estrito nessa coluna falha com `string truncation` — o
  snapshot inicial apontado para ENG_UNIDADE expôs exatamente isso. O snapshot
  foi redirecionado para ENG_GRUMAT (íntegra) e o mecanismo passou a falhar com
  erro claro, comportamento correto do adaptador.

## Bugs do adaptador encontrados e corrigidos durante estes testes

1. **Describe de largura de string errado dentro de CTE + UNION** — o engine
   reporta larguras imprecisas para expressões string (ex.: literal `'insert'`
   de 6 chars descrito como 5). Corrigido com piso mínimo (256) para strings
   sem tamanho exato via tabelas de sistema
   (`dbt/adapters/firebird/column.py`).
2. **Staging de snapshot mais estreita que a alvo** — agora as colunas da
   staging são alargadas (`pad_columns_to_target`) para nunca serem menores
   que as da tabela alvo (`macros/materializations/snapshot_helpers.sql`).
3. **Staging residual bloqueando re-execução de snapshot** — após falha, a
   `__dbt_tmp` permanecia e travava a execução seguinte. Adicionada limpeza
   automática de staging residual antes da criação.
4. **Literais de snapshot truncáveis** — `'insert'`/`'update'`/`'delete'`/
   `'False'`/`'True'` agora com `cast(... as varchar(n))` explícito.

Após as correções, **toda a matriz foi re-executada do zero e passou**.

## Estado final do banco após os testes

Objetos criados (todos removíveis com `DROP`, não há dependências das tabelas
do cliente): `dbt_seed_materiais`, `dbt_stg_eng_unidade` (view),
`dbt_stg_eng_grumat` (view), `dbt_mart_materiais`, `dbt_inc_materiais`,
`dbt_snap_eng_grumat`.

## Como reproduzir

```bash
cd tests\banco_real
dbt debug --profiles-dir .
dbt seed --profiles-dir .
dbt run --profiles-dir .
dbt test --profiles-dir .
dbt snapshot --profiles-dir .
dbt docs generate --profiles-dir .
```
