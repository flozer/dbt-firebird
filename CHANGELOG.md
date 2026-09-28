# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.1] - 2026-09-28

### Adicionado
- Opção `lock_timeout` no profile (padrão 10s): tempo de espera por lock de
  outra transação antes de falhar.
- Retry automático (3 tentativas com backoff) para conflitos de
  lock/concorrência do Firebird (deadlock, lock time-out, update conflict).
- `persist_docs`: comentários de tabela/coluna via `COMMENT ON` (Firebird).
- `validate_sql` próprio (o default usa `EXPLAIN`, não suportado pelo
  Firebird) e `snapshot_string_as_time`.
- Retry de conexão transiente no `open` (via `retry_connection`).
- Suítes extras do `dbt-tests-adapter`: ValidateConnection, Ephemeral,
  SingularTestsEphemeral, DocsGenerate (com skips documentados).
- Documentação para o usuário final: tutorial completo, `dbt init`
  interativo, case-sensitivity de identificadores, IBExpert, charsets
  legados, troubleshooting.

### Alterado
- Transações usam **READ COMMITTED** (antes SNAPSHOT): updates concorrentes
  sobre a mesma linha esperam e aplicam sobre a versão mais recente, em vez
  de falhar com "update conflicts with concurrent update".
- `commit()` baseado no estado real da transação no driver (elimina perda
  de comentários/DDL por commit dessincronizado da flag do dbt).
- `require-dbt-version: >=1.8.0, <2.0.0` no projeto interno.

## [0.1.0] - 2026-09-26

### Adicionado
- Adaptador dbt para Firebird sobre o `firebird-driver` (interface `dbt-adapters` v1).
- Materializações próprias: `table` (swap atômico via DELETE+INSERT),
  `view` (CREATE OR ALTER VIEW), `incremental` (append / delete+insert / merge),
  `seed` (substituição atômica) e `snapshot` (check e timestamp, SCD2).
- Describe de colunas via PREPARE (sem executar a query) com tamanhos exatos
  via tabelas de sistema.
- Suporte a `dbt test`, `dbt docs generate`, hooks e `full-refresh`.
- Suítes `dbt-tests-adapter` (5 passed, 3 skipped documentados) e projeto de exemplo.
- Validação contra base real de produção (66 GB, 3.144 relações, WIN1252) —
  ver `RELATORIO_TESTES_BANCO_REAL.md`.
