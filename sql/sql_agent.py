# sql_agent.py
import logging
from typing import Dict, Any, List
import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2 import sql as psql

logger = logging.getLogger(__name__)

class SQLAgent:
    def __init__(self, db_config: Dict[str, Any], name: str = "SQLAgent"):
        self.db_config = db_config
        self.name = name
        self._schema = None
        logger.info(f"Initialized SQLAgent for {db_config['database']}")

    def get_connection(self):
        try:
            conn = psycopg2.connect(
                host=self.db_config["host"],
                port=self.db_config["port"],
                user=self.db_config["user"],
                password=self.db_config["password"],
                database=self.db_config["database"]
            )
            conn.autocommit = False
            return conn
        except Exception as e:
            logger.error(f"Connection failed: {str(e)}")
            raise

    def get_schema(self) -> Dict[str, List[str]]:
        if self._schema:
            return self._schema
            
        logger.debug("Fetching schema...")
        schema = {}
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cursor:
                    cursor.execute("""
                        SELECT table_name, column_name, data_type 
                        FROM information_schema.columns 
                        WHERE table_schema = 'public'
                        ORDER BY table_name, ordinal_position;
                    """)
                    for table, column, dtype in cursor.fetchall():
                        if table not in schema:
                            schema[table] = []
                        schema[table].append(f"{column} ({dtype})")
                    self._schema = schema
                    logger.info(f"Schema loaded with {len(schema)} tables")
                    return schema
        except Exception as e:
            logger.error(f"Schema fetch failed: {str(e)}")
            raise

    def execute_query(self, query: str) -> List[Dict]:
        logger.info(f"Executing query: {query[:100]}...")
        try:
            with self.get_connection() as conn:
                with conn.cursor(cursor_factory=RealDictCursor) as cursor:
                    cursor.execute(query)
                    result = cursor.fetchall()
                    conn.commit()
                    logger.debug(f"Query affected {cursor.rowcount} rows")
                    return result
        except psycopg2.Error as e:
            logger.error(f"Query error: {str(e)}")
            conn.rollback()
            raise RuntimeError(f"SQL Error: {str(e)}") from e
        except Exception as e:
            logger.error(f"Execution failed: {str(e)}")
            raise RuntimeError(f"Execution error: {str(e)}") from e

    def validate_query(self, query: str) -> bool:
        try:
            with self.get_connection() as conn:
                with conn.cursor() as cursor:
                    cursor.execute(psql.SQL("EXPLAIN {query}").format(query=psql.SQL(query)))
                    return True
        except Exception as e:
            logger.warning(f"Invalid query: {str(e)}")
            return False