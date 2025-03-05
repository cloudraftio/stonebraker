import re
import psycopg2
from psycopg2.extras import RealDictCursor


# Saving the SQL Queries to further execute them
def save_sql_queries(content, output_file="sql_queries.sql"):
    """Extract and save SQL queries that are wrapped in Markdown SQL code blocks."""
    sql_block_pattern = r"```sql\s*(.*?)\s*```"
    
    sql_queries = re.finditer(sql_block_pattern, content, re.MULTILINE | re.DOTALL)
    
    with open(output_file, 'w') as f:
        for i, query in enumerate(sql_queries, 1):
            query_content = query.group(1).strip()
            f.write(f"-- Query {i}\n")
            f.write(f"{query_content}\n\n")

def extract_sql_queries(content: str) -> str:
    sql_block_pattern = r"```sql\s*(.*?)\s*```"
    sql_queries = re.finditer(sql_block_pattern, content, re.MULTILINE | re.DOTALL)
    
    extracted_queries = []
    for query in sql_queries:
        query_content = query.group(1).strip()
        extracted_queries.append(query_content)
    
    return "\n\n".join(extracted_queries)

def get_db_connection(db_config: dict):
    try:
        connection = psycopg2.connect(**db_config)
        return connection
    except Exception as e:
        print("Error connecting to database:", e)
        raise

def execute_query(db_config: dict, query: str):
    conn = get_db_connection(db_config)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query)
            results = cursor.fetchall()
        conn.commit()
        return results
    except Exception as e:
        conn.rollback()
        print("Error executing query:", e)
        raise
    finally:
        conn.close()

def get_schema_info(db_config: dict):
    """
    Dynamically fetch the schema: table names and their columns 
    from the public schema.
    """
    conn = get_db_connection(db_config)
    schema = {}
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT table_name, column_name 
                FROM information_schema.columns 
                WHERE table_schema = 'public'
                ORDER BY table_name, ordinal_position;
            """)
            rows = cursor.fetchall()
            for table, column in rows:
                if table not in schema:
                    schema[table] = []
                schema[table].append(column)
        return schema
    except Exception as e:
        print("Error fetching schema info:", e)
        raise
    finally:
        conn.close()
