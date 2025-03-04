from utils.sql_utils import execute_query, get_schema_info

class SQLAgent:
    def __init__(self, db_config: dict, name: str = "SQLAgent"):
        self.db_config = db_config
        self.name = name

    def get_schema(self):
        return get_schema_info(self.db_config)

    def is_query_in_context(self, query: str, schema: dict) -> bool:
        for table in schema.keys():
            if table.lower() in query.lower():
                return True
        return False

    def execute_query(self, query: str):
        schema = self.get_schema()
        if not self.is_query_in_context(query, schema):
            available_tables = ", ".join(schema.keys())
            raise ValueError(
                f"Query out of context. Please reframe your question to reference one of the tables: {available_tables}"
            )
        return execute_query(self.db_config, query)
    
    def invoke(self, state: dict):
        """
        The supervisor calls this method with a state dictionary.
        Expecting a 'query' key in the state.
        """
        query = state.get("query", "")
        return self.execute_query(query)
