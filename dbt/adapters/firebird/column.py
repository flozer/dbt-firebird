from dataclasses import dataclass
from typing import Optional

from dbt.adapters.base.column import Column

# firebird-driver: charset id -> bytes por caractere
_BYTES_PER_CHAR = {
    0: 1,  # NONE
    1: 1,  # OCTETS
    2: 1,  # ASCII
    3: 3,  # UNICODE_FSS
    4: 4,  # UTF8
}


@dataclass
class FirebirdColumn(Column):
    TYPE_LABELS = {
        "STRING": "VARCHAR(8191)",
        "TEXT": "VARCHAR(8191)",
        "INT": "INTEGER",
        "INTEGER": "INTEGER",
        "BIGINT": "BIGINT",
        "FLOAT": "DOUBLE PRECISION",
        "BOOLEAN": "BOOLEAN",
        "DATE": "DATE",
        "TIMESTAMP": "TIMESTAMP",
    }

    @classmethod
    def from_driver_meta(cls, name: str, meta, char_size: Optional[int] = None) -> "FirebirdColumn":
        """Constrói a coluna a partir de um ItemMetadata do firebird-driver."""
        dtype, size, precision, scale = _meta_to_type_parts(meta)
        if char_size is not None and size is not None:
            size = char_size
            dtype = f"{dtype.split('(')[0]}({char_size})"
        elif size is not None and dtype.startswith(("VARCHAR", "CHAR")):
            # O engine descreve larguras erradas para strings de expressões
            # dentro de derived tables com UNION (ex.: literal 'insert' -> 5).
            # Sem tamanho exato via tabelas de sistema, aplica um piso seguro.
            size = max(size, 256)
            dtype = f"{dtype.split('(')[0]}({size})"
        return cls(
            column=name,
            dtype=dtype,
            char_size=size,
            numeric_precision=precision,
            numeric_scale=scale,
        )


def _meta_to_type_parts(meta):
    """Mapeia (SQLDataType, subtype, scale, length, charset) -> tipo DDL Firebird.

    Retorna (dtype, char_size, numeric_precision, numeric_scale).
    """
    from firebird.driver.types import SQLDataType

    dt = SQLDataType(meta.datatype)
    subtype = meta.subtype or 0
    scale = meta.scale or 0

    if dt in (SQLDataType.TEXT, SQLDataType.VARYING):
        chars = max(1, meta.length // _BYTES_PER_CHAR.get(meta.charset, 4))
        base = "CHAR" if dt == SQLDataType.TEXT else "VARCHAR"
        return (f"{base}({chars})", chars, None, None)
    if dt == SQLDataType.SHORT:
        if subtype or scale:
            return _numeric("DECIMAL", scale)
        return ("SMALLINT", None, None, None)
    if dt == SQLDataType.LONG:
        if subtype or scale:
            return _numeric("DECIMAL", scale)
        return ("INTEGER", None, None, None)
    if dt == SQLDataType.INT64:
        if subtype or scale:
            return _numeric("DECIMAL", scale)
        return ("BIGINT", None, None, None)
    if dt == SQLDataType.INT128:  # Firebird 4/5
        return _numeric("DECIMAL", scale, default_precision=38)
    if dt == SQLDataType.FLOAT:
        return ("FLOAT", None, None, None)
    if dt in (SQLDataType.DOUBLE, SQLDataType.D_FLOAT):
        return ("DOUBLE PRECISION", None, None, None)
    if dt == SQLDataType.TIMESTAMP:
        return ("TIMESTAMP", None, None, None)
    if dt in (SQLDataType.TIMESTAMP_TZ, SQLDataType.TIMESTAMP_TZ_EX):
        return ("TIMESTAMP WITH TIME ZONE", None, None, None)
    if dt == SQLDataType.DATE:
        return ("DATE", None, None, None)
    if dt == SQLDataType.TIME:
        return ("TIME", None, None, None)
    if dt in (SQLDataType.TIME_TZ, SQLDataType.TIME_TZ_EX):
        return ("TIME WITH TIME ZONE", None, None, None)
    if dt == SQLDataType.BOOLEAN:
        return ("BOOLEAN", None, None, None)
    if dt == SQLDataType.BLOB:
        if subtype == 1:
            return ("BLOB SUB_TYPE TEXT", None, None, None)
        return ("BLOB SUB_TYPE BINARY", None, None, None)
    if dt in (SQLDataType.DEC16, SQLDataType.DEC34):
        return (f"DECFLOAT({34 if dt == SQLDataType.DEC34 else 16})", None, None, None)
    # fallback conservador
    return ("VARCHAR(8191)", 8191, None, None)


def _numeric(base: str, scale: int, default_precision: int = 18):
    return (f"{base}({default_precision}, {abs(scale)})", None, default_precision, abs(scale))
