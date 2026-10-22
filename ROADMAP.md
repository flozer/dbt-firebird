# ROADMAP — dbt-firebird

Estado e planos do projeto. Atualizado em 2026-10.

## Estado atual (out/2026)

- **v0.1.1 publicada no PyPI** (`pip install dbt-firebird dbt-core`)
- Repositório público, licença Apache-2.0, CI verde
  (Firebird 3/4/5 × Python 3.9/3.12 + bandit)
- Documentação oficial no docs.getdbt.com mergeada
  (página `firebird-setup` + listagem em community adapters)
- Validado em produção real: base de 66 GB, 3.144 relações, charset WIN1252

## Concluído

- [x] Adaptador completo: table (swap atômico), view, incremental
      (append/delete+insert/merge), seed, snapshot (SCD2)
- [x] Resiliência a concorrência: READ COMMITTED, `lock_timeout`, retry de locks
- [x] `persist_docs` (COMMENT ON), `validate_sql`, describe via PREPARE
- [x] Suítes dbt-tests-adapter (6 passed / 7 skipped documentados)
- [x] Publicação PyPI com Trusted Publishing (OIDC, sem tokens)
- [x] Segurança: Dependabot, secret scanning + push protection, branch
      protection, bandit no CI
- [x] Docs oficiais dbt (PR #10114 no docs.getdbt.com, mergeado)

## Curto prazo

- [ ] **Candidatura ao Trusted Adapter Program**: abrir issue
      "Add adapter to Trusted list" no docs.getdbt.com — pré-requisitos
      cumpridos (docs mergeadas, bandit no CI, PyPI via OIDC, Dependabot).
      *Gated: autorização do mantenedor.*
- [ ] CI automático em `push`/PR (hoje só `workflow_dispatch`)
- [ ] Acompanhar review/feedback da página firebird-setup no docs.getdbt.com
- [ ] Monitorar primeiro PR do Dependabot pós-lançamento (validar fluxo)

## Médio prazo

- [ ] Testar o `ephemeral` contornando a limitação de CTEs
      (`__dbt__cte__` não-quotado) — avaliar se é possível via macro do core
- [ ] Firebird 3 além da suíte: testes funcionais com FB3 real (identificadores
      de 31 bytes, diferenças de sintaxe residuais)
- [ ] `dbt source freshness` (tabela `METADATA`/`RDB$TRANSACTIONS`?)
- [ ] Melhor suporte a contratos (`contract: enforced`) — normalização de
      tipos do Firebird no comparador
- [ ] Indexes: suporte a `+indexes` em modelos table/incremental
- [ ] Cobertura: reduzir os skips das suítes oficiais

## Longo prazo

- [ ] Avaliar adaptador para **dbt Fusion (v2, engine Rust)** quando o
      ecossistema de adaptadores v2 estabilizar
- [ ] i18n da documentação (EN/PT)
- [ ] Suporte a DECFLOAT/INT128 (Firebird 4/5) nas conversões de tipo
- [ ] Comunidade: guia de troubleshooting expandindo, exemplos por ERP

## Não-objetivos

- CDC/replicação (o [duckdb-firebird](https://github.com/flozer/duckdb-firebird)
  cobre o caminho de leitura analítica)
- Suporte a Firebird < 3.0
