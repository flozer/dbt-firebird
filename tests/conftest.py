import os

import pytest
import firebird.driver as fdb

pytest_plugins = ["dbt.tests.fixtures.project"]

TEST_DB_PATH = os.environ.get(
    "FIREBIRD_TEST_DB_PATH", "C:/dados/dbt-firebird/tests/db_test.fdb"
)


def _connect(path: str):
    return fdb.connect(f"localhost:{path}", user="SYSDBA", password="masterkey")


def _wipe_database(path: str) -> None:
    """O Firebird não tem schemas: os testes compartilham um namespace único.
    Remove todas as relações de usuário para a sessão começar limpa."""
    con = _connect(path)
    cur = con.cursor()
    cur.execute(
        "select trim(rdb$relation_name), coalesce(rdb$relation_type, 0) "
        "from rdb$relations where coalesce(rdb$system_flag, 0) = 0"
    )
    relations = [(r[0].strip(), r[1]) for r in cur.fetchall()]
    con.commit()
    # derruba views antes de tabelas; repete até não restar nada pendente
    for _ in range(3):
        remaining = []
        for name, kind in relations:
            ddl = f'drop view "{name}"' if kind == 1 else f'drop table "{name}"'
            try:
                cur.execute(ddl)
            except fdb.Error:
                remaining.append((name, kind))
        tx = getattr(con, "main_transaction", None)
        if tx is None or tx.is_active():
            con.commit()
        relations = remaining
        if not relations:
            break
    con.close()


def _ensure_database(path: str) -> None:
    if not os.path.exists(path):
        con = fdb.create_database(f"localhost:{path}", user="SYSDBA", password="masterkey")
        con.close()
    _wipe_database(path)


@pytest.fixture(scope="session", autouse=True)
def clean_database():
    _ensure_database(TEST_DB_PATH)
    yield


@pytest.fixture(scope="class")
def dbt_profile_target():
    return {
        "type": "firebird",
        "host": "localhost",
        "port": 3050,
        "path": TEST_DB_PATH,
        "user": "SYSDBA",
        "password": "masterkey",
        "charset": "UTF8",
        "threads": 1,
    }
