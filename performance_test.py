import sys
from io import StringIO
import logging
from performer.performer import graph  # Import your LangGraph setup

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)

def get_mock_schema():
    """Returns a mock schema for testing."""
    return """
     table_name  | column_name 
    -------------+-------------
     customers   | id
     customers   | name
     customers   | email
     customers   | address
     orders      | id
     orders      | customer_id
     orders      | order_date
     orders      | total
     products    | id
     products    | name
     products    | description
     products    | price
     products    | stock_quantity
    """

def test_workflow():
    """Simulates the workflow of the PostgreSQL optimization assistant with detailed logging."""
    logging.info("Starting test workflow...")
    
    mock_inputs = [
        "no",  
        "Just give me details about index creation.",  
        "yes" 
    ]
    mock_query = "Identify and give me solutions to optimize my postgres database"
    mock_schema = get_mock_schema()

    logging.info(f"Mock query: {mock_query}")
    logging.info(f"Mock schema:\n{mock_schema}")

    original_stdin = sys.stdin
    original_stdout = sys.stdout

    try:
        sys.stdin = StringIO("\n".join(mock_inputs))

        captured_output = StringIO()
        sys.stdout = captured_output

        thread = {"configurable": {"thread_id": "performance_optimization_test"}}
        logging.info(f"Initialized thread with ID: {thread['configurable']['thread_id']}")

        logging.info("Starting analysis phase...")
        for event in graph.stream(
            {"query": mock_query, "schema": mock_schema},
            thread,
            stream_mode="values"
        ):
            if "analysis" in event:
                logging.info("Analysis generated:")
                logging.info(event["analysis"])
                print("\n**Analysis**")
                print(event["analysis"])

        current_state = graph.get_state(thread)
        logging.info(f"Current state after analysis: {current_state.values}")
        
        if current_state.values.get("execute"):
            logging.info("User approved analysis. Proceeding to SQL execution...")
            sql_queries = current_state.values.get("execute_query", [])
            logging.info(f"Extracted SQL queries: {sql_queries}")
            
            print("\n**Executing SQL Commands**")
            for cmd in sql_queries:
                logging.info(f"Executing SQL command: {cmd}")
                print(f"Executing: {cmd}")

    finally:
        sys.stdin = original_stdin
        sys.stdout = original_stdout

    logging.info("Captured output from the workflow:")
    logging.info(captured_output.getvalue())

if __name__ == "__main__":
    test_workflow()