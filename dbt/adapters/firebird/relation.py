from dataclasses import dataclass

from dbt.adapters.base.relation import BaseRelation
from dbt.adapters.contracts.relation import Policy


@dataclass(frozen=True, eq=False, repr=False)
class FirebirdRelation(BaseRelation):
    """Relacoes do Firebird tem um unico namespace: o nome da tabela.

    `database` e `schema` sao rotulos logicos do dbt e nunca sao renderizados
    no SQL — apenas o identificador quoted, para preservar maiusculas/minusculas.
    """

    @classmethod
    def get_default_quote_policy(cls) -> Policy:
        return Policy(database=False, schema=False, identifier=True)

    def render(self) -> str:
        return self.quoted(self.identifier)
