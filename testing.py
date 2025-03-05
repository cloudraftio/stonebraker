# TEST

from performer.performer import graph, human_in_loop
from utils.sql_utils import save_sql_queries


query = [
    "Identify and give me solutions to optimize my postgres database"
    ]
# schema = """
# CREATE TABLE ecommerce.customers (
#     id SERIAL PRIMARY KEY,
#     name VARCHAR(100) NOT NULL,
#     email VARCHAR(100) UNIQUE NOT NULL,
#     address TEXT
# );

# CREATE TABLE ecommerce.products (
#     id SERIAL PRIMARY KEY,
#     name VARCHAR(200) NOT NULL,
#     description TEXT,
#     price DECIMAL(10, 2) NOT NULL,
#     stock_quantity INTEGER NOT NULL DEFAULT 0
# );

# CREATE TABLE ecommerce.orders (
#     id SERIAL PRIMARY KEY,
#     customer_id INTEGER NOT NULL,
#     order_date DATE NOT NULL,
#     total DECIMAL(10, 2) NOT NULL
# );
# """
schema = """
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

thread = {"configurable": {"thread_id": "performance_optimization_1"}}

while True:
    # Run analysis phase
    for event in graph.stream(
        {"query": query, "schema": schema},
        thread,
        stream_mode="values"
    ):
        if "analysis" in event:
            print("\n**Analysis**")
            print(event["analysis"])
    
    # Check if execution should proceed
    current_state = graph.get_state(thread)
    if current_state.values.get("execute"):
        break
    
    # Handle feedback loop
    user_response = input("\nSatisfied? (yes/no): ").lower()
    if user_response == "no":
        feedback = input("Feedback: ")
        graph.update_state(thread, {"feedback": feedback, "reanalyze": True})
    else:
        graph.update_state(thread, {"execute": True, "feedback": ""})