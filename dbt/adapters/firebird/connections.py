from __future__ import annotations

import os
import traceback
from contextlib import contextmanager
from dataclasses import dataclass
from typing import Optional, Tuple

import firebird.driver as fdb

from dbt.adapters.contracts.connection import (
    AdapterResponse,
    Connection,
    ConnectionState,
    Credentials,
)
from dbt.adapters.events.logging import AdapterLogger
from dbt.adapters.exceptions import FailedToConnectError
from dbt.adapters.sql.connections import SQLConnectionManager
from dbt_common.exceptions import DbtRuntimeError

logger = AdapterLogger("Firebird")


@dataclass
class FirebirdCredentials(Credentials):
    # `database` e `schema` sao obrigatorios no contrato do dbt, mas no Firebird
    # nao existe o conceito de schema: `database` e um rotulo logico derivado
    # do arquivo .fdb e `schema` e ignorado (padrao 'main').
    database: Optional[str] = None  # type: ignore[assignment]
    schema: Optional[str] = None  # type: ignore[assignment]

    host: Optional[str] = None
    port: int = 3050
    path: Optional[str] = None  # caminho do arquivo .fdb, visto pelo SERVIDOR
    user: Optional[str] = None
    password: Optional[str] = None
    charset: str = "UTF8"
    role: Optional[str] = None

    _ALIASES = {
        "dbname": "database",
        "pass": "password",
        "db_file": "path",
    }

    def __post_init__(self):
        if not self.path:
            raise DbtRuntimeError(
                "Firebird adapter requires `path`: the database file path as seen "
                "by the server (e.g. D:/data/mydb.fdb or /data/mydb.fdb)"
            )
        if not self.database:
            self.database = os.path.splitext(os.path.basename(self.path))[0]
        if not self.schema:
            self.schema = "main"

    @property
    def type(self) -> str:
        return "firebird"

    @property
    def unique_field(self) -> str:
        return f"{self.host or 'local'}:{self.path}"

    def _connection_keys(self) -> Tuple[str, ...]:
        return (
            "host",
            "port",
            "path",
            "database",
            "schema",
            "user",
            "charset",
            "role",
        )

    @property
    def dsn(self) -> str:
        if self.host:
            return f"{self.host}/{self.port}:{self.path}"
        return self.path


class FirebirdConnectionManager(SQLConnectionManager):
    TYPE = "firebird"

    @classmethod
    def open(cls, connection: Connection) -> Connection:
        if connection.state == ConnectionState.OPEN:
            return connection

        credentials: FirebirdCredentials = connection.credentials

        def connect():
            return fdb.connect(
                credentials.dsn,
                user=credentials.user,
                password=credentials.password,
                charset=credentials.charset,
                role=credentials.role,
            )

        # retry_connection registra o handle/estado e converte falhas
        # persistentes em FailedToConnectError; erros transientes (rede,
        # servidor reiniciando) ganham 1 retry
        return cls.retry_connection(
            connection,
            connect=connect,
            logger=logger,
            retryable_exceptions=(fdb.OperationalError, fdb.InterfaceError),
            retry_limit=1,
        )

    def cancel(self, connection: Connection) -> None:
        # firebird-driver nao expoe cancelamento assincrono de statement.
        logger.debug("Cancel not supported for Firebird connections")

    @contextmanager
    def exception_handler(self, sql: str):
        try:
            yield
        except fdb.Error as e:
            logger.debug("Firebird error: {} ({})", str(e).strip(), sql)
            logger.debug("Traceback: {}", traceback.format_exc())
            raise DbtRuntimeError(f"Firebird error: {str(e).strip()}\nSQL: {sql}") from e
        except Exception as e:
            logger.debug("Unexpected error running Firebird query: {}", sql)
            logger.debug("Traceback: {}", traceback.format_exc())
            raise DbtRuntimeError(str(e)) from e

    @classmethod
    def _rollback_handle(cls, connection: Connection) -> None:
        # o firebird-driver dispara assert no rollback de transacao inativa;
        # statements que falham no PREPARE comitam a transacao de preparo que
        # eles mesmos abriram, deixando-a inativa
        handle = connection.handle
        tx = getattr(handle, "main_transaction", None)
        if tx is not None and not tx.is_active():
            return
        super()._rollback_handle(connection)

    @classmethod
    def get_response(cls, cursor) -> AdapterResponse:
        rows_affected = None
        try:
            # statements DDL nao reportam RECORDS e o INFO request falha
            rows = getattr(cursor, "rowcount", None)
            if isinstance(rows, int) and rows >= 0:
                rows_affected = rows
        except fdb.Error:
            pass
        return AdapterResponse(_message="OK", rows_affected=rows_affected)

    def add_begin_query(self):
        # Firebird inicia transacoes implicitamente no primeiro statement.
        return self.get_thread_connection(), None

    def add_commit_query(self):
        connection = self.get_thread_connection()
        handle = connection.handle
        # commit sem transacao ativa dispara assert no firebird-driver
        tx = getattr(handle, "main_transaction", None)
        if tx is None or tx.is_active():
            handle.commit()
        return connection, None

    def commit(self):
        """Commit real sempre que houver transacao ativa no driver.

        As materializations deste adaptador commitam explicitamente entre DDL
        e DML (regra de snapshot de metadados) e o fluxo do dbt emite commits
        "sobrando" no fim — em vez de depender da flag transaction_open
        (que dessincroniza com as transacoes implicitas do Firebird), comitamos
        com base no estado REAL da transacao no driver.
        """
        connection = self.get_if_exists()
        if connection is None:
            return connection
        handle = connection.handle
        tx = getattr(handle, "main_transaction", None)
        if tx is not None and tx.is_active():
            handle.commit()
        connection.transaction_open = False
        return connection
