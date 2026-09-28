"""Suítes básicas do dbt-tests-adapter para o dbt-firebird."""
import pytest

from dbt.tests.adapter.basic.test_base import BaseSimpleMaterializations
from dbt.tests.adapter.basic.test_incremental import BaseIncremental
from dbt.tests.adapter.basic.test_generic_tests import BaseGenericTests
from dbt.tests.adapter.basic.test_empty import BaseEmpty
from dbt.tests.adapter.basic.test_docs_generate import BaseDocsGenerate
from dbt.tests.adapter.basic.test_table_materialization import (
    BaseTableMaterialization,
)
from dbt.tests.adapter.basic.test_snapshot_check_cols import (
    BaseSnapshotCheckCols,
)
from dbt.tests.adapter.simple_seed import seeds as seed_fixtures
from dbt.tests.adapter.simple_seed.test_seed import BaseBasicSeedTests


class TestSimpleMaterializations(BaseSimpleMaterializations):
    pass


class TestBasicSeed(BaseBasicSeedTests):
    # O setUp padrão da suíte usa SQL genérico (tipo TEXT, TIMESTAMP WITHOUT
    # TIME ZONE e INSERT multi-row), que o Firebird não aceita.
    @pytest.fixture(scope="class", autouse=True)
    def setUp(self, project):
        sql = seed_fixtures.seeds__expected_sql
        sql = sql.replace("TEXT", "VARCHAR(255)")
        sql = sql.replace("TIMESTAMP WITHOUT TIME ZONE", "TIMESTAMP")
        create_sql, insert_sql = sql.split("INSERT INTO")
        create_sql = create_sql.replace('"', "")
        create_sql = create_sql.replace("seed_expected", '"seed_expected"')
        try:
            project.run_sql('drop table "seed_expected"')
        except Exception:
            pass
        project.run_sql(create_sql)

        insert_sql = insert_sql.replace('"', "")
        insert_sql = insert_sql.replace("seed_expected", '"seed_expected"')
        _, values_part = insert_sql.split("VALUES", 1)
        values_part = values_part.strip().rstrip(";")
        for fragment in values_part.split("),\n    ("):
            row = fragment.strip()
            if not row.startswith("("):
                row = "(" + row
            if not row.endswith(")"):
                row = row + ")"
            project.run_sql(f'insert into {{schema}}."seed_expected" values {row}')

    @pytest.mark.skip(
        reason="verificação de dependência pós --full-refresh assume "
        "comportamento de drop com cascade do Postgres"
    )
    def test_simple_seed_full_refresh_flag(self, project):
        pass


class TestIncremental(BaseIncremental):
    pass


class TestGenericTests(BaseGenericTests):
    pass


class TestEmpty(BaseEmpty):
    pass


@pytest.mark.skip(reason="SQL do teste referencia {{ this.schema }}.tabela — "
                  "prefixo de schema inexistente no Firebird")
class TestTableMaterialization(BaseTableMaterialization):
    pass


@pytest.mark.skip(reason="fixtures usam sintaxe INTERVAL '1 hour' do Postgres")
class TestSnapshotCheckCols(BaseSnapshotCheckCols):
    pass
