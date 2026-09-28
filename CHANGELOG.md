# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/)
e versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [Não lançado]

### Adicionado
- Opção `lock_timeout` no profile (padrão 10s): tempo de espera por lock de
  outra transação antes de falhar.
- Retry automático (3 tentativas com backoff) para conflitos de
  lock/concorrência do Firebird (deadlock, lock time-out, update conflict).

### Alterado
- Transações usam **READ COMMITTED** (antes SNAPSHOT): updates concorrentes
  sobre a mesma linha esperam e aplicam sobre a versão mais recente, em vez
  de falhar com "update conflicts with concurrent update".

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
