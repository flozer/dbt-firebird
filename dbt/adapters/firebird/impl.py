from typing import List, Optional
from decimal import Decimal
import re

import agate

from dbt.adapters.base import available
from dbt.adapters.events.logging import AdapterLogger
from dbt.adapters.sql.impl import SQLAdapter

from dbt.adapters.firebird.column import FirebirdColumn
from dbt.adapters.firebird.connections import FirebirdConnectionManager
from dbt.adapters.firebird.relation import FirebirdRelation

logger = AdapterLogger("Firebird")


class FirebirdAdapter(SQLAdapter):
    """Adaptador dbt para o Firebird, construido sobre o firebird-driver."""

    ConnectionManager = FirebirdConnectionManager
    Relation = FirebirdRelation
    Column = FirebirdColumn

    @classmethod
    def date_function(cls) -> str:
        return "CURRENT_TIMESTAMP"

    @available
    def debug_query(self) -> None:
        # `select 1 as id` puro é inválido no Firebird (exige FROM)
        self.execute("select 1 as id from rdb$database")

    @classmethod
    def is_cancelable(cls) -> bool:
        return False

    @classmethod
    def valid_incremental_strategies(cls) -> List[str]:
        return ["append", "delete+insert", "merge"]

    @classmethod
    def builtin_incremental_strategies(cls) -> List[str]:
        return ["append", "delete+insert", "merge"]

    # --- tipos para seeds (agate -> Firebird) ---

    @classmethod
    def convert_text_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        # dimensiona o VARCHAR pelos dados reais do seed: VARCHAR UTF8 consome
        # 4 bytes por char e o limite de tamanho de registro é ~64KB
        max_len = 1
        for value in agate_table.columns[col_idx].values():
            if value is not None:
                max_len = max(max_len, len(str(value)))
        return f"VARCHAR({min(8191, max_len + 10)})"

    @classmethod
    def convert_number_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        decimals = agate_table.aggregate(agate.MaxPrecision(col_idx))
        return "DOUBLE PRECISION" if decimals else "BIGINT"

    @classmethod
    def convert_integer_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        return "BIGINT"

    @classmethod
    def convert_boolean_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        return "BOOLEAN"

    @classmethod
    def convert_datetime_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        return "TIMESTAMP"

    @classmethod
    def convert_date_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        return "DATE"

    @classmethod
    def convert_time_type(cls, agate_table: "agate.Table", col_idx: int) -> str:
        return "TIME"

    # --- describe via PREPARE (nao executa a query) ---

    @available.parse(lambda *a, **k: [])
    def get_column_schema_from_query(self, sql: str, bindings: Optional[object] = None) -> list:
        """Colunas (nome/tipo) de um SELECT, via PREPARE do statement.

        Sobrescreve o metodo base: em vez de executar a query com limit 0,
        apenas a prepara — no Firebird isso nao executa nada e funciona
        com CTEs e expressoes.
        """
        return self._describe_sql(sql)

    @available
    def describe_relation(self, relation) -> list:
        return self._describe_sql(f"select first 0 * from {relation.render()}")

    @available
    def pad_columns_to_target(self, cols: list, target_cols: list) -> list:
        """Alarga colunas da staging para a largura da tabela alvo: o width
        descrito do SELECT pode ser menor que o real e a staging precisa
        acomodar qualquer valor que caiba na alvo."""
        target_by_name = {c.name.lower(): c for c in target_cols}
        padded = []
        for col in cols:
            target = target_by_name.get(col.name.lower())
            if (
                target is not None
                and col.dtype.upper().startswith(("VARCHAR", "CHAR"))
                and target.dtype.upper().startswith(("VARCHAR", "CHAR"))
                and (target.char_size or 0) > (col.char_size or 0)
            ):
                base = col.dtype.split("(")[0]
                padded.append(
                    FirebirdColumn(
                        column=col.column,
                        dtype=f"{base}({target.char_size})",
                        char_size=target.char_size,
                        numeric_precision=col.numeric_precision,
                        numeric_scale=col.numeric_scale,
                    )
                )
            else:
                padded.append(col)
        return padded

    @available
    def seed_binding(self, value):
        """firebird-driver não converte Decimal para parâmetros inteiros sem
        escala; os seeds do dbt (agate) entregam todo número como Decimal."""
        if isinstance(value, Decimal):
            return int(value) if value == value.to_integral_value() else float(value)
        return value

    @available
    def run_sql_for_tests(self, sql, fetch, conn):
        """Como o SQLAdapter, mas busca ANTES do commit (no firebird-driver o
        commit invalida os cursores) e remove prefixos `<schema>.` — o
        Firebird não tem schemas e as suítes de teste os usam no SQL fixo.
        A suíte oficial gera schemas no formato `test_schema<sufixo>`."""
        schema = getattr(conn.credentials, "schema", None)
        if schema:
            sql = sql.replace(f"{schema}.", "")
        sql = re.sub(r"\btest\d+\w*\.", "", sql)
        cursor = conn.handle.cursor()
        try:
            cursor.execute(sql)
            result = None
            if fetch == "one":
                result = cursor.fetchone()
            elif fetch == "all":
                result = cursor.fetchall()
            conn.handle.commit()
            return result
        except BaseException as e:
            try:
                conn.handle.rollback()
            except Exception:
                pass
            logger.debug("run_sql_for_tests failed: {}", sql)
            print(sql)
            print(e)
            raise e

    def get_rows_different_sql(
        self,
        relation_a,
        relation_b,
        column_names: Optional[List[str]] = None,
        except_operator: str = "EXCEPT",
    ) -> str:
        """Template próprio: o Firebird não possui EXCEPT/INTERSECT, então a
        diferença de linhas é calculada com NOT EXISTS + IS NOT DISTINCT FROM."""
        names: List[str]
        if column_names is None:
            columns = self.get_columns_in_relation(relation_a)
            names = sorted((self.quote(c.name) for c in columns))
        else:
            names = sorted((self.quote(n) for n in column_names))

        a = str(relation_a)
        b = str(relation_b)
        match_b_to_a = " and ".join(f"s2.{c} is not distinct from s1.{c}" for c in names)
        match_a_to_b = " and ".join(f"s2.{c} is not distinct from s1.{c}" for c in names)

        return f"""
select
    (select count(*) from {a}) - (select count(*) from {b}) as row_count_difference,
    (select count(*) from {a} s1 where not exists (
        select 1 from {b} s2 where {match_b_to_a}))
  + (select count(*) from {b} s1 where not exists (
        select 1 from {a} s2 where {match_a_to_b})) as num_mismatched
from rdb$database
""".strip()

    def quote_seed_column(self, column: str, quote_config: object) -> str:
        # Colunas de seed nunca são quotadas: no Firebird, identificadores
        # não-quotados são armazenados em maiúsculas e o SQL dos modelos
        # referencia colunas sem aspas — quotar criaria colunas inatingíveis.
        return column

    def _describe_sql(self, sql: str) -> list:
        statement_sql = _strip_semicolon(sql)
        connection = self.connections.get_thread_connection()
        cursor = connection.handle.cursor()
        try:
            stmt = cursor.prepare(statement_sql)
        except Exception:
            logger.debug("describe failed for SQL: {}", statement_sql)
            raise
        try:
            metas = list(stmt._out_desc)
        finally:
            try:
                stmt.free()
            except Exception:
                pass

        # O tamanho informado pelo driver no buffer de mensagem superestima o
        # número de caracteres (varia com o charset); para colunas que vêm de
        # tabelas base, busca o tamanho exato em RDB$RELATION_FIELDS.
        char_sizes = self._exact_char_sizes(connection, metas)

        columns = []
        for meta in metas:
            name = (meta.alias or meta.field or "").strip()
            override = char_sizes.get((meta.relation.strip(), meta.field.strip()))
            columns.append(FirebirdColumn.from_driver_meta(name, meta, override))
        return columns

    def _exact_char_sizes(self, connection, metas) -> dict:
        by_relation: dict = {}
        for meta in metas:
            if meta.relation and meta.field:
                by_relation.setdefault(
                    meta.relation.strip(), set()
                ).add(meta.field.strip())
        sizes = {}
        for relation, fields in by_relation.items():
            placeholders = ", ".join("?" for _ in fields)
            lookup = connection.handle.cursor()
            lookup.execute(
                "select rf.rdb$field_name, fld.rdb$field_length, cs.rdb$bytes_per_character "
                "from rdb$relation_fields rf "
                "join rdb$fields fld on fld.rdb$field_name = rf.rdb$field_source "
                "join rdb$character_sets cs on cs.rdb$character_set_id = fld.rdb$character_set_id "
                f"where rf.rdb$relation_name = ? and rf.rdb$field_name in ({placeholders})",
                [relation, *fields],
            )
            for field_name, length, bytes_per_char in lookup.fetchall():
                bpc = int(bytes_per_char) if bytes_per_char else 1
                sizes[(relation, field_name.strip())] = max(1, int(length) // bpc)
        return sizes


def _strip_semicolon(sql: str) -> str:
    return sql.strip().rstrip(";").strip()
