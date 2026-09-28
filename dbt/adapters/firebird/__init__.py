from dbt.adapters.base import AdapterPlugin

from dbt.adapters.firebird.connections import FirebirdConnectionManager, FirebirdCredentials
from dbt.adapters.firebird.impl import FirebirdAdapter
from dbt.include import firebird

Plugin = AdapterPlugin(
    adapter=FirebirdAdapter,
    credentials=FirebirdCredentials,
    include_path=firebird.PACKAGE_PATH,
)
