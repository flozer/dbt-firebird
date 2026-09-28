# dbt-firebird

Adaptador [dbt](https://www.getdbt.com/) para o banco de dados
[Firebird](https://firebirdsql.org/), construído sobre o driver oficial
[firebird-driver](https://pypi.org/project/firebird-driver/).

Desenvolvido e testado contra o **Firebird 5.0** (compatível com 3.0+ na
maioria dos recursos) e **dbt-core 1.8+** (interface `dbt-adapters` v1).

## Instalação

```bash
pip install dbt-firebird
```

A partir do código-fonte:

```bash
pip install -e .
```

## Configuração

`profiles.yml`:

```yaml
meu_projeto:
  target: dev
  outputs:
    dev:
      type: firebird
      host: localhost          # opcional; omita para acesso local ao arquivo
      port: 3050               # padrão 3050
      path: D:/dados/meubanco.fdb   # caminho do .fdb VISTO PELO SERVIDOR
      user: SYSDBA
      password: masterkey
      charset: UTF8            # padrão UTF8
      threads: 1               # 1 recomendado
```

| Campo      | Obrigatório | Descrição                                                        |
|------------|-------------|------------------------------------------------------------------|
| `path`     | sim         | Caminho do arquivo `.fdb` como o **servidor** enxerga            |
| `host`     | não         | Host do servidor; sem ele, conexão local direta ao arquivo       |
| `port`     | não         | Porta (padrão 3050)                                              |
| `user` / `password` | sim | Credenciais                                                      |
| `charset`  | não         | Charset da conexão (padrão `UTF8`)                               |
| `role`     | não         | Role do Firebird                                                 |
| `database` | não         | Rótulo lógico (padrão: nome do arquivo sem extensão)             |
| `schema`   | não         | Rótulo lógico (padrão `main`) — **o Firebird não tem schemas**   |

`database` e `schema` existem apenas para satisfazer o contrato do dbt —
nenhum dos dois é usado no SQL gerado.

### Charsets de bases legadas

O padrão é `UTF8`. Se a base foi criada com charset `NONE` e contém texto em
código de página legado (acentuação portuguesa em WIN1252, por exemplo), a
leitura falha com `UnicodeDecodeError`. Nesse caso configure o charset da
conexão:

```yaml
charset: WIN1252
```

Validado em uma base real restaurada (~66 GB, 3.144 tabelas) — ver
[`RELATORIO_TESTES_BANCO_REAL.md`](RELATORIO_TESTES_BANCO_REAL.md).

## Materializações suportadas

| Materialização | Status | Observações                                                        |
|----------------|--------|--------------------------------------------------------------------|
| `view`         | ✅     | `CREATE OR ALTER VIEW` (atómico)                                   |
| `table`        | ✅     | Swap atômico via DELETE+INSERT quando as colunas são compatíveis   |
| `incremental`  | ✅     | Estratégias `append`, `delete+insert` e `merge` (`unique_key`)     |
| `seed`         | ✅     | Substituição de dados atômica                                      |
| `snapshot`     | ✅     | Estratégias `check` e `timestamp` (SCD tipo 2)                     |
| `ephemeral`    | ✅     | Modelos viram CTEs — sem DDL específico                           |

Também suportado: `dbt test` (testes genéricos e singulares), `dbt docs generate`,
hooks, `on_schema_change` (`ignore`/`fail`/`append`/`sync_all`), `full-refresh`.

## Como o adaptador funciona (decisões de design)

O Firebird tem características que exigiram adaptações específicas:

1. **Snapshot de metadados**: statements compilam contra o estado de metadados
   *commitado* antes da transação — DDL executado na mesma transação não é
   visível ao DML seguinte. Por isso o adaptador commita entre CREATE e INSERT
   (duas transações por materialização).

2. **Sem `CREATE TABLE AS SELECT`**: o adaptador *prepara* (PREPARE) a query do
   modelo — sem executá-la — para extrair nomes e tipos de colunas, gera o
   `CREATE TABLE` e depois carrega com `INSERT INTO ... SELECT`.

3. **Substituição atômica de tabelas**: como não há `RENAME TABLE`, a
   re-materialização cria uma tabela staging `__dbt_tmp`, carrega os dados e,
   se as colunas forem compatíveis, faz `DELETE + INSERT + DROP` **na mesma
   transação** — leitores (MVCC) nunca veem a tabela vazia. Com colunas
   incompatíveis, faz drop + recreate (janela curta com a tabela vazia).

4. **Sem schemas**: o namespace do Firebird é único. `database`/`schema` do
   perfil são rótulos lógicos; identificadores são sempre renderizados entre
   aspas duplas.

5. **Colunas de seed não são quotadas**: identificadores não-quotados são
   armazenados em maiúsculas — colunas de seed ficam alcançáveis por SQL
   sem aspas (padrão do dialeto).

6. **Tipos de texto dimensionados pelos dados**: `VARCHAR` UTF8 consome 4
   bytes/char e o limite de registro é ~64 KB; seeds e CTAS dimensionam os
   `VARCHAR` pelo tamanho real (via tabelas de sistema e `PREPARE`).

## Limitações conhecidas

- **Sem `MD5()`**: snapshots usam `HASH()` (FNV1a-64, `BIGINT`) para o `dbt_scd_id`.
- **`rename` de tabelas/views não existe** no Firebird; macros que dependem
  disso (`rename_relation`) retornam erro explícito.
- **DROP TABLE bloqueado por dependências**: recriar uma tabela cujo schema
  mudou exige que views dependentes sejam derrubadas antes (o swap atômico
  evita o drop no caso comum).
- **Contratos** (`contract: enforced`): melhor esforço; a comparação de tipos
  depende dos nomes exatos de tipos do Firebird no YAML.
- **CANCEL de queries** não é suportado pelo firebird-driver (`is_cancelable = False`).
- Identificadores com mais de ~31 caracteres: OK no Firebird 4/5; modelos dbt
  com sufixos internos (`__dbt_tmp`) devem respeitar o limite da sua versão
  (31 bytes no Firebird 3).

## Desenvolvimento

```bash
python -m venv .venv
.venv/Scripts/pip install -e .[dev]   # Linux/macOS: .venv/bin/pip ...

# suítes oficiais do dbt-tests-adapter (requer Firebird local na porta 3050)
.venv/Scripts/pytest tests/adapter -v

# projeto de exemplo (crie o banco antes, ver example/profiles.yml)
cd example
../.venv/Scripts/dbt seed --profiles-dir .
../.venv/Scripts/dbt run --profiles-dir .
../.venv/Scripts/dbt test --profiles-dir .
../.venv/Scripts/dbt snapshot --profiles-dir .

# testes contra uma base real de 66 GB / 3.144 tabelas (relatório completo
# em RELATORIO_TESTES_BANCO_REAL.md)
cd tests/banco_real
dbt debug --profiles-dir .
dbt run --profiles-dir .
```

Variável de ambiente opcional: `FIREBIRD_TEST_DB_PATH` (padrão
`tests/db_test.fdb`, criado e limpo automaticamente).

## Estrutura do projeto

```
dbt/adapters/firebird/     # Credentials, ConnectionManager, Relation, Column, Adapter
dbt/include/firebird/      # macros do dialeto + materializations + profile template
tests/                     # suítes dbt-tests-adapter
example/                   # projeto dbt de exemplo
```

## Licença

Apache-2.0
