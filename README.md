<div align="center">
  <h1>dbt-firebird</h1>
  <p><strong>Execute <a href="https://github.com/dbt-labs/dbt-core">dbt-core</a> diretamente em bancos <a href="https://firebirdsql.org/">Firebird</a>.</strong></p>
  <p><em>O primeiro adaptador dbt para o Firebird — construído sobre o driver
    oficial <a href="https://pypi.org/project/firebird-driver/">firebird-driver</a>.</em></p>
  <p>
    Modelos SQL versionados, testes de qualidade de dados, documentação gerada,
    snapshots (SCD2) e materializações incrementais para Firebird 3.0, 4.0 e
    5.0 — transações corretas, swap atômico de tabelas e tolerância a
    concorrência.
  </p>
  <p>
    <a href="LICENSE"><img alt="license Apache-2.0" src="https://img.shields.io/badge/license-Apache--2.0-green.svg"></a>
    <a href="https://github.com/flozer/dbt-firebird/releases/tag/v0.1.1"><img alt="release v0.1.1" src="https://img.shields.io/badge/release-v0.1.1-blue.svg"></a>
    <a href="https://github.com/flozer/dbt-firebird/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/flozer/dbt-firebird/actions/workflows/ci.yml/badge.svg"></a>
    <a href="https://pypi.org/project/dbt-firebird/"><img alt="PyPI version" src="https://img.shields.io/pypi/v/dbt-firebird?logo=pypi&logoColor=white"></a>
    <a href="https://pypi.org/project/dbt-firebird/"><img alt="PyPI downloads/mês" src="https://img.shields.io/pypi/dm/dbt-firebird?logo=pypi&logoColor=white"></a>
  </p>
</div>

> **Status:** versão 0.1.1, validada contra Firebird 5.0.3 (incluindo uma base
> real de ~66 GB com 3.144 tabelas — ver
> [`RELATORIO_TESTES_BANCO_REAL.md`](RELATORIO_TESTES_BANCO_REAL.md)) e pela
> matriz de CI Firebird 3/4/5 × Python 3.9/3.12.

---

## Sumário

1. [Requisitos](#requisitos)
2. [Instalação](#instalação)
3. [Preparando um banco de teste](#preparando-um-banco-de-teste)
4. [Configurando a conexão (profiles.yml)](#configurando-a-conexão-profilesyml)
5. [Seu primeiro projeto dbt do zero](#seu-primeiro-projeto-dbt-do-zero)
6. [O que cada materialização faz](#o-que-cada-materialização-faz)
7. [Comandos do dbt e o que esperar de cada um](#comandos-do-dbt-e-o-que-esperar-de-cada-um)
8. [Testes de qualidade de dados](#testes-de-qualidade-de-dados)
9. [Snapshots: histórico de mudanças (SCD2)](#snapshots-histórico-de-mudanças-scd2)
10. [Solução de problemas](#solução-de-problemas)
11. [Como o adaptador funciona por dentro](#como-o-adaptador-funciona-por-dentro)
12. [Limitações conhecidas](#limitações-conhecidas)
13. [Desenvolvimento e contribuição](#desenvolvimento-e-contribuição)
14. [Licença](#licença)

---

## Requisitos

| Item | Versão | Observação |
|---|---|---|
| Firebird | 3.0, 4.0 ou 5.0 | Servidor acessível por TCP (padrão porta 3050) ou acesso direto ao arquivo |
| Python | 3.9 a 3.12 | No Windows, marque "Add Python to PATH" na instalação |
| dbt-core | 1.8+ | Instalado junto do adaptador no passo seguinte |
| fbclient | opcional | A biblioteca cliente do Firebird (`fbclient.dll` / `libfbclient.so`) já vem com a instalação do servidor; em máquinas **sem** servidor instale o pacote "Firebird Client" |

## Instalação

```bash
pip install dbt-firebird
```

Isso instala o adaptador **e** as dependências (`dbt-adapters`,
`firebird-driver`). Instale também o `dbt-core`:

```bash
pip install dbt-core
dbt --version
```

A saída deve listar o adaptador:

```
Plugins:
  - firebird: 0.1.1
```

Alternativa, instalando direto do código-fonte (para testar mudanças não
publicadas):

```bash
pip install git+https://github.com/flozer/dbt-firebird.git
```

## Preparando um banco de teste

Se você já tem um banco Firebird, pule para a próxima seção. Para criar um
banco vazio de testes, use o `isql` (vem com o Firebird):

```
C:\> isql -user SYSDBA -password masterkey
SQL> CREATE DATABASE 'C:\dados\meu_teste.fdb';
SQL> EXIT;
```

Ou por qualquer ferramenta gráfica (IBExpert, FlameRobin, DBeaver).

> O caminho do arquivo `.fdb` é **do ponto de vista do servidor**. Se o dbt
> rodar na mesma máquina do Firebird, é o caminho normal do Windows
> (`C:\dados\meu_teste.fdb`). Se o servidor for remoto, é o caminho no
> servidor (`/dados/meu_teste.fdb` em Linux, por exemplo).

## Configurando a conexão (profiles.yml)

> **Atalho:** se você está criando um projeto **novo**, o `dbt init` faz isso
> para você — ele lista `firebird` como opção, pergunta host, porta, caminho,
> usuário, senha, charset e threads, grava o `profiles.yml` e já roda o
> `dbt debug` no final. A referência completa dos campos está abaixo, útil
> para conferir, ajustar ou configurar projetos existentes manualmente.

O dbt guarda as conexões em `~/.dbt/profiles.yml` (Windows:
`C:\Users\SEU_USUARIO\.dbt\profiles.yml`). Exemplo mínimo para uma base local:

```yaml
meu_projeto:
  target: dev
  outputs:
    dev:
      type: firebird
      path: C:/dados/meu_teste.fdb
      user: SYSDBA
      password: masterkey
      threads: 1
```

> **Atenção às barras:** use `/` (barra normal) no caminho, não `\`.

### Todas as opções

| Opção | Obrigatória | Padrão | O que significa |
|---|---|---|---|
| `type` | sim | — | Sempre `firebird` (nome do adaptador) |
| `path` | sim | — | Caminho do arquivo `.fdb` **visto pelo servidor** |
| `host` | não | *(local)* | Host/IP do servidor. **Omitir** = conexão direta ao arquivo na mesma máquina |
| `port` | não | `3050` | Porta TCP do servidor |
| `user` | sim | — | Usuário do banco (padrão de instalação: `SYSDBA`) |
| `password` | sim | — | Senha (padrão de instalação: `masterkey`) |
| `charset` | não | `UTF8` | Charset da conexão — ver tabela abaixo |
| `role` | não | — | Role (papel) do Firebird, se você usa |
| `lock_timeout` | não | `10` | Segundos que um statement espera por lock de outra transação antes de falhar (`0` = não espera; `-1` = espera indefinidamente) |
| `threads` | não | `1` | Execuções paralelas. **1 é recomendado** (o Firebird não tem schemas; mais threads compartilham o mesmo namespace) |
| `database` | não | nome do arquivo | Rótulo lógico interno do dbt — não afeta o SQL gerado |
| `schema` | não | `main` | Rótulo lógico interno do dbt — **o Firebird não tem schemas**; nunca é usado no SQL |

Exemplo com servidor remoto:

```yaml
      type: firebird
      host: 192.168.0.10
      port: 3050
      path: /dados/producao.fdb
      user: SYSDBA
      password: masterkey
      charset: WIN1252
      threads: 1
```

### Qual charset usar?

| Situação | `charset` |
|---|---|
| Base criada em Firebird 3+ com UTF8, ou dados só com ASCII (sem acento) | `UTF8` (padrão) |
| Base antiga/restaurada com charset `NONE` e acentuação portuguesa | `WIN1252` |
| Base em ISO8859-1 | `ISO8859_1` |

Se vir erros `UnicodeDecodeError: 'utf-8' codec can't decode...` ao rodar,
troque o charset para `WIN1252` — é o caso mais comum em bases legadas
brasileiras.

### Valide a conexão

```bash
dbt debug
```

O que esperar: `Connection test: OK connection ok` e `All checks passed!`.
Se falhar aqui, é conexão (host/path/senha) — não adianta seguir.

## Seu primeiro projeto dbt do zero

```bash
mkdir meu_projeto && cd meu_projeto
```

Crie o `dbt_project.yml`:

```yaml
name: meu_projeto
version: "1.0"
config-version: 2
profile: meu_projeto

model-paths: ["models"]
seed-paths: ["seeds"]
```

Crie um primeiro modelo em `models/clientes.sql`:

```sql
select
    codigo,
    nome,
    cidade
from CLIENTES
```

> `CLIENTES` é uma tabela que já existe no seu banco. Modelos podem ler
> tabelas reais diretamente ou referenciar outros modelos com
> `{{ ref('outro_modelo') }}`.

Rode:

```bash
dbt run
```

O que esperar:

```
1 of 1 START sql table model main.clientes ................ [RUN]
1 of 1 OK created sql table model main.clientes ........... [OK in 0.15s]
Done. PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=1
```

Isso criou a **tabela `clientes`** no seu banco (o nome do modelo vira o nome
da tabela). Mude o modelo para `select 1 as id` e rode de novo — o dbt
substitui a tabela pelos dados novos.

### Onde estão as tabelas criadas pelo dbt?

No Firebird, identificadores escritos **sem aspas** no SQL são convertidos
para MAIÚSCULAS. O dbt (convenção de todos os adaptadores, igual faz no
Postgres) cria seus objetos com o nome **entre aspas e em minúsculas** —
o modelo `clientes` vira a tabela `"clientes"`. Consequências práticas:

```sql
select * from "clientes";   -- ✅ correto (com aspas)
select * from clientes;     -- ❌ procura CLIENTES, que não existe
```

Ferramentas gráficas (FlameRobin, IBExpert, DBeaver) mostram os nomes
minúsculos na lista de tabelas — costumam aparecer agrupados após os nomes
maiúsculos legados. Consultas que juntam tabelas dbt com tabelas reais
funcionam normalmente misturando os dois estilos:

```sql
select c.customer_name, g.descricao
from "marts_customers" c
join ENG_GRUMAT g on g.tag = c.grupo_tag
```

> **Nota sobre IBExpert e afins:** os objetos minúsculos **estão**
> registrados no catálogo (mesmos metadados das tabelas maiúsculas:
> `relation_type`, `system_flag`, owner idênticos) e funcionam por SQL —
> só são fáceis de perder de vista na árvore do explorador, porque na
> ordenação por bytes aparecem **depois de todos os nomes maiúsculos**.
> Se não aparecer nem no fim da lista, atualize a árvore (refresh) e
> procure no grupo de nomes citados/entre aspas.

**Prefere nomes no estilo Firebird (sem aspas/maiúsculos)?** Configure o
`alias` do modelo/seed em maiúsculas — o dbt criará `"TABELA"`, que é
exatamente o nome que uma consulta sem aspas encontra:

```sql
-- dbt_project.yml
seeds:
  meu_projeto:
    store:
      +alias: STORE
```

> Se já existir a versão minúscula (`"store"`), **derrube-a antes** de
> mudar o alias — o dbt se recusa a adivinhar entre duas tabelas que só
> diferem no caso do nome.

## O que cada materialização faz

A materialização é como o dbt materializa o modelo no banco. Configure por
arquivo, por pasta ou no próprio modelo:

```sql
{{ config(materialized='table') }}
select ...
```

| Materialização | O que faz no Firebird | Quando usar |
|---|---|---|
| `view` (padrão de projeto novo) | `CREATE OR ALTER VIEW` — consulta guardada, sem dados duplicados | Camadas de preparação (staging); o Firebird reescreve a query a cada leitura |
| `table` | Cria a tabela e **insere** os dados; ao re-rodar, substitui atomicamente | Resultados finais (marts) consumidos por dashboards |
| `incremental` | Na 1ª vez cria a tabela; nas seguintes processa só o novo | Tabelas grandes que crescem (events, vendas) |
| `seed` | Carrega um CSV para uma tabela | Listas pequenas de referência, parâmetros de teste |
| `snapshot` | Mantém o **histórico** de mudanças de uma tabela (SCD2) | Auditoria: como o registro estava em cada época |
| `ephemeral` | Não cria nada; vira uma CTE dentro dos modelos que a usam | Intermediários que ninguém consulta direto |

### `table` — substituição atômica

Ao re-rodar um modelo table, o adaptador cria os dados numa tabela de apoio
(`__dbt_tmp`), depois faz `DELETE + INSERT + DROP` **numa única transação**:
quem estiver lendo a tabela nunca vê estado vazio (MVCC do Firebird). Se a
estrutura de colunas mudou, ele recria a tabela do zero (aí há uma janela
curta — e views dependentes precisam ser recriadas; veja
[Solução de problemas](#solução-de-problemas)).

### `incremental` — só o que mudou

```sql
{{
  config(
    materialized='incremental',
    unique_key='id'
  )
}}

select id, nome, valor, data_venda
from VENDAS
{% if is_incremental() %}
where data_venda > (select max(data_venda) from {{ this }})
{% endif %}
```

Na primeira execução cria a tabela completa. Nas seguintes, roda a query
(com o filtro `is_incremental` ativo) e aplica a estratégia:

| `incremental_strategy` | O que faz | Requer |
|---|---|---|
| `append` *(padrão)* | Insere as novas linhas no final | nada |
| `delete+insert` | Apaga as linhas com as mesmas chaves e reinsere | `unique_key` |
| `merge` | Atualiza as linhas existentes e insere as novas (MERGE nativo) | `unique_key` |

Também suporta `on_schema_change` (`ignore`/`fail`/`append`/`sync_all`) para
quando as colunas do modelo mudam, e `full_refresh=True`/`dbt run
--full-refresh` para reconstruir do zero.

### `seed` — CSV para tabela

Coloque `produtos.csv` em `seeds/` e rode `dbt seed`. O adaptador detecta os
tipos das colunas (inteiro, decimal, data, texto...) e dimensiona os
`VARCHAR` pelo conteúdo real do arquivo. Re-rodar um seed **substitui os
dados atomicamente** (delete + insert na mesma transação).

### Configurações globais por pasta

```yaml
# dbt_project.yml
models:
  meu_projeto:
    staging:
      +materialized: view
    marts:
      +materialized: table
```

## Comandos do dbt e o que esperar de cada um

Todos os comandos abaixo, executados dentro da pasta do projeto:

| Comando | O que faz | O que esperar |
|---|---|---|
| `dbt debug` | Testa a conexão e o ambiente | `All checks passed!` |
| `dbt parse` | Só valida o projeto (sem tocar no banco) | `Performance info: ...` |
| `dbt seed` | Carrega os CSVs de `seeds/` | `Done. PASS=n` |
| `dbt run` | Compila e materializa os modelos | `Done. PASS=n ERROR=0` |
| `dbt run -s nome_modelo` | Roda só um modelo | `PASS=1` |
| `dbt run --full-refresh` | Reconstrói tudo do zero | `PASS=n` (tabelas recriadas) |
| `dbt test` | Executa os testes de dados (próxima seção) | `PASS=x ERROR=0` — falhas indicam **dados** que violam as regras |
| `dbt snapshot` | Atualiza os snapshots | `Done. PASS=n` |
| `dbt docs generate` | Gera a documentação lendo o catálogo do banco | `Catalog written to .../catalog.json` |
| `dbt docs serve` | Abre a documentação no navegador | Site em `http://localhost:8080` |

Cada modelo tem o SQL compilado em `target/compiled/` — útil para depurar
exatamente o que foi executado no Firebird.

## Testes de qualidade de dados

Declare regras num `schema.yml` junto dos modelos:

```yaml
version: 2

models:
  - name: clientes
    description: "Clientes ativos"
    columns:
      - name: codigo
        tests:
          - unique       # não pode repetir
          - not_null     # não pode ser nulo
      - name: cidade
        tests:
          - not_null
```

`dbt test` roda cada regra como um `SELECT` de contagem. **Teste reprovado
não é erro do adaptador** — é o dbt avisando que encontrou dados que violam a
regra (por exemplo, um `unique` que falhou porque a tabela real tem chaves
duplicadas). Nos nossos testes contra uma base real, isso detectou uma chave
duplicada genuína — exatamente o propósito.

## Snapshots: histórico de mudanças (SCD2)

Um snapshot guarda **como o registro estava a cada execução**. Exemplo sobre
a tabela real `CLIENTES`:

Crie `snapshots/clientes_snapshot.sql`:

```jinja
{% snapshot clientes_snapshot %}

{{
    config(
        unique_key='codigo',
        strategy='check',
        check_cols=['nome', 'cidade'],
        invalidate_hard_deletes=True
    )
}}

select codigo, nome, cidade from CLIENTES

{% endsnapshot %}
```

| Opção | Significado |
|---|---|
| `strategy='check'` | Compara as colunas listadas em `check_cols` para detectar mudança |
| `strategy='timestamp'` | Alternativa: usa uma coluna de data de atualização (`updated_at`) |
| `check_cols='all'` | Compara todas as colunas |
| `unique_key` | Chave que identifica o registro |
| `invalidate_hard_deletes=True` | Registro que sumiu da origem é marcado como apagado (em vez de ignorado) |

Cada `dbt snapshot` compara a origem com a tabela `clientes_snapshot`:
linha nova → inserida; linha alterada → a antiga recebe `dbt_valid_to` (fechada)
e a nova é inserida; linha que sumiu → marcada como deletada. Execuções
repetidas sem mudanças não alteram nada.

## Solução de problemas

| Sintoma | Causa provável | Solução |
|---|---|---|
| `UnicodeDecodeError: 'utf-8' codec can't decode byte 0xe1` | Base legada (charset `NONE`) com acentuação WIN1252 | `charset: WIN1252` no profile |
| `string truncation / expected length N` ao rodar snapshot ou modelo | **Overfill**: a tabela real tem dados maiores que o declarado (ex.: coluna VARCHAR(3) com 6 chars — comum em bases restauradas) | Problema da base: corrija a coluna (`ALTER TABLE ... ALTER COLUMN ... TYPE`) ou filtre no modelo |
| `Table X already exists` em snapshot | Execução anterior falhou no meio | Reexecute — o adaptador limpa a tabela de apoio sozinho |
| `cannot delete COLUMN ... there are dependencies` | Tentando recriar uma tabela que tem views dependentes | Re-rodar sem mudar colunas usa o swap atômico (sem drop). Mudando colunas, derrube as views dependentes antes |
| `Token unknown - line 1, column 13 - SELECT` (ou similar) | Modelo com SQL sem `FROM` (o Firebird exige) | Adicione `from RDB$DATABASE` à query |
| `field ... exceeds maximum record size` | Modelo com muitas colunas de texto largas somando > 64 KB por linha | Reduza os VARCHARs com `cast(coluna as varchar(200))` no modelo |
| `deadlock / update conflicts with concurrent update` | Outra transação (aplicação, outro modelo em paralelo, trigger de auditoria) alterou a mesma linha/página enquanto o dbt escrevia | **O adaptador já contorna automaticamente**: transações em READ COMMITTED + `lock_timeout` de espera + até 3 tentativas com backoff. Se ainda ocorrer, reduza a concorrência (`threads: 1`) ou aumente `lock_timeout` no profile |
| Nomes de modelo com +31 caracteres no Firebird 3 | Limite de identificador de 31 bytes do FB3 | Encurte o nome (FB4/5 aceitam 63) |
| `Table unknown` logo após `CREATE` no mesmo script | DDL não é visível ao DML na mesma transação | É o dbt que orquestra — se acontecer em hooks, comite entre eles |
| "A tabela do meu modelo/seed não existe no banco" | Ela existe, em **minúsculas e com aspas** (`"store"`); consulta sem aspas procura `STORE` | Consulte com aspas (`select * from "store"`) — ver seção [Onde estão as tabelas criadas pelo dbt?](#onde-estão-as-tabelas-criadas-pelo-dbt) |

## Como o adaptador funciona por dentro

O Firebird tem características que exigiram adaptações específicas:

1. **Snapshot de metadados**: statements compilam contra o estado de metadados
   *commitado* antes da transação — DDL executado na mesma transação não é
   visível para o DML seguinte. Por isso o adaptador commita entre CREATE e
   INSERT (duas transações por materialização). Os dados, por outro lado, são
   lidos em **READ COMMITTED** (com espera limitada por `lock_timeout`) —
   isolamento adequado a ETL concorrente, que evita o clássico
   "update conflicts with concurrent update" do SNAPSHOT.

2. **Sem `CREATE TABLE AS SELECT`**: o adaptador *prepara* (PREPARE) a query do
   modelo — sem executá-la — para extrair nomes e tipos de colunas, gera o
   `CREATE TABLE` e depois carrega com `INSERT INTO ... SELECT`.

3. **Substituição atômica de tabelas**: como não há `RENAME TABLE`, a
   re-materialização cria uma tabela staging `__dbt_tmp`, carrega os dados e,
   se as colunas forem compatíveis, faz `DELETE + INSERT + DROP` **na mesma
   transação** — leitores (MVCC) nunca veem a tabela vazia.

4. **Sem schemas**: o namespace do Firebird é único. `database`/`schema` do
   perfil são rótulos lógicos; identificadores são sempre renderizados entre
   aspas duplas.

5. **Colunas de seed não são quotadas**: identificadores não-quotados são
   armazenados em maiúsculas — colunas de seed ficam alcançáveis por SQL
   sem aspas (padrão do dialeto).

6. **Tipos de texto dimensionados com segurança**: `VARCHAR` UTF8 consome 4
   bytes/char e o limite de registro é ~64 KB; seeds e CTAS dimensionam os
   `VARCHAR` pelo tamanho real (via tabelas de sistema e `PREPARE`), com piso
   de segurança para expressões cuja largura o engine descreve de forma
   imprecisa.

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
- Identificadores com mais de 31 caracteres: OK no Firebird 4/5; modelos dbt
  com sufixos internos (`__dbt_tmp`) devem respeitar o limite da sua versão
  (31 bytes no Firebird 3).

## Desenvolvimento e contribuição

Veja [`CONTRIBUTING.md`](CONTRIBUTING.md) para ambiente de desenvolvimento,
como rodar as suítes oficiais do `dbt-tests-adapter` (`.github/workflows/ci.yml`
roda a matriz Firebird 3/4/5 × Python 3.9/3.12) e as regras do dialeto.

Projeto de exemplo completo em [`example/`](example/) e relatório de testes
contra base real de produção em
[`RELATORIO_TESTES_BANCO_REAL.md`](RELATORIO_TESTES_BANCO_REAL.md).

## Autor

**Fernando Lozer** — GitHub [@flozer](https://github.com/flozer) ·
LinkedIn [/fernandolozer](https://www.linkedin.com/in/fernandolozer)

<div align="center">
  <h2>Apoie o projeto</h2>
  <p>Se o dbt-firebird ajuda o seu trabalho, considere apoiar o desenvolvimento contínuo.</p>
  <a href="https://buymeacoffee.com/fernandolozer">
    <img
      src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
      alt="Apoie Fernando Lozer no Buy Me a Coffee"
      height="50">
  </a>
</div>

## Licença

[Apache-2.0](LICENSE)
