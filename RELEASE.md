# Guia de publicação (PyPI)

Este guia descreve **o que falta fazer** para publicar o `dbt-firebird` no
PyPI e o procedimento em si. Nada é publicado automaticamente: o workflow de
publish só dispara manualmente (`workflow_dispatch`), e o job exige o
environment `pypi` — que pode inclusive ser configurado com "required
reviewer" para exigir sua aprovação em cada publicação.

## Estado atual (tudo pronto)

- [x] `pyproject.toml` completo (metadados, URLs, classifiers, autores)
- [x] Workflow [`.github/workflows/publish.yml`](.github/workflows/publish.yml):
      build + `twine check` + publish via **Trusted Publishing** (OIDC, sem
      token/senha do PyPI)
- [x] Environment `pypi` criado no repositório GitHub
- [x] Tag `v0.1.0` criada
- [x] CI verde na matriz Firebird 3/4/5 × Python 3.9/3.12
- [ ] **Sua conta no PyPI + registro do Trusted Publisher** (única etapa manual)
- [ ] **Seu OK explícito** para disparar a publicação

## Passo a passo da única etapa manual

1. Crie a conta em <https://pypi.org/account/register/> (confirme o e-mail).
2. Ative 2FA na conta (obrigatório para publicar).
3. Em <https://pypi.org/manage/account/publishing/>, registre um **"pending
   publisher"** com estes valores exatos:

   | Campo | Valor |
   |---|---|
   | PyPI project name | `dbt-firebird` |
   | Owner | `flozer` |
   | Repository | `dbt-firebird` |
   | Workflow name | `publish.yml` |
   | Environment name | `pypi` |

4. (Opcional, recomendado) No GitHub: *Settings → Environments → pypi*,
   marque **"Required reviewers"** e adicione a si mesmo — cada publicação
   pedirá seu clique de aprovação.

## Como publicar (quando der o OK)

1. **Antes**, confira a versão em `pyproject.toml` e o `CHANGELOG.md`
   (o PyPI não aceita o mesmo número duas vezes).
2. `gh workflow run publish.yml --ref main` (ou no site: *Actions → Publish
   to PyPI → Run workflow*).
3. Se configurou required reviewer, aprove a execução em *Actions → run em
   andamento → Review deployments*.
4. O job `build` gera o sdist/wheel e valida os metadados (`twine check`);
   o job `publish` envia ao PyPI via OIDC.
5. Valide num venv limpo:

   ```bash
   python -m venv /tmp/check && /tmp/check/Scripts/pip install dbt-firebird dbt-core
   dbt --version          # deve listar "firebird: <versão>"
   ```

## Depois da primeira publicação

- Tornar o repo público: `gh repo edit flozer/dbt-firebird --visibility public`
- Trocar a instalação do README de `git+https://...` para `pip install dbt-firebird`
- Abrir o PR na documentação oficial do dbt (`docs.getdbt.com`) e candidatar
  ao Trusted Adapter Program — **somente com autorização explícita do dono**
