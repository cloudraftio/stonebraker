from langchain_groq import ChatGroq as Groq
from langgraph.graph import START, END, StateGraph
from langgraph.graph import MessagesState
from typing_extensions import TypedDict
from IPython.display import Image, display
from langgraph.checkpoint.memory import MemorySaver
import re
import dotenv

llm = Groq (
    # temperature=0.1,
    model_name="llama-3.3-70b-specdec",
    groq_api_key=dotenv.get_key(".env", "GROQ_API_KEY") 
)


class AgentState(TypedDict):
    query: str
    analysis: str
    schema: str    
    feedback: str

from langchain_core.messages import SystemMessage, HumanMessage, RemoveMessage

def analyze_database(state: AgentState):
    query = state.get("query", "")
    adb = state.get("analysis", "")
    fdb = state.get("feedback", "")
    schema = state.get("schema", "")

    with open("performance_queries.json", "r") as f:
        performance_queries = f.read()

    sys_message = SystemMessage(
        content=f"""
        You are a database optimization expert. 
        Analyze the given PostgreSQL schema and provide specific, actionable optimization suggestions.
        These are some performance queries which are natively supported of postgres: {performance_queries}
        """
    )

    if adb and fdb and schema:
        analysis_message = (
            f"This is the previous analysis of the postgres database: {adb}"
            f"This was the original query asked by the user: {query}"
            f"Re Analyze the database based on the user feedback: {fdb}"
            f"Take this schema as a context: {schema}"
        )
    else:
        analysis_message = (
            f"This is the user given query: {query}"
            f"Given this PostgreSQL database schema: {schema}"
            f"Analyze the schema and suggest optimizations including:"
            f"- Index creation opportunities"
            f"- Query performance improvements"
            f"- Table structure recommendations"
        )
    
    message = [
        sys_message,
        HumanMessage(content=analysis_message)
    ]

    response = llm.invoke(message)

    return {"analysis": response.content, "feedback": ""}


def human_in_loop(state: AgentState):
    user_response = input("\nAre you satisfied with the analysis? (yes/no): ").strip().lower()
    
    if user_response == "no":
        feedback = input("\nPlease provide specific feedback for improvement: ")
        return {"feedback": feedback}
    
    return {"feedback": ""}

def should_continue(state: AgentState):
    return "analyze_database" if state.get("feedback") else END


def create_human_readable(state: AgentState):
    sys_message = SystemMessage(
        content="""
        You are a technical writer.
        You have a great experience in working with .md files. 
        """
    )

    adb = state.get("analysis","")
    hmn_message = HumanMessage(
        content=(
        f"Convert this analysis to human readable md format: {adb}"
        "Make sure you don't change the content of the analysis"
        )
    )

    message = [
        sys_message,
        hmn_message
    ]

    response = llm.invoke(message)

    output_file = "REPORT.md"
    with open(output_file, "w") as f:
        f.write(response.content)

    return response.content


builder = StateGraph(AgentState)

builder.add_node("analyze_database", analyze_database)
builder.add_node("human_in_loop", human_in_loop)
builder.add_node("create_human_readable", create_human_readable)

builder.add_edge(START, "analyze_database")
builder.add_edge("analyze_database", "human_in_loop")
builder.add_edge("analyze_database", "create_human_readable")
builder.add_conditional_edges("human_in_loop", should_continue, ["analyze_database", "create_human_readable"])
builder.add_edge("create_human_readable", END)

memory = MemorySaver()
graph = builder.compile(interrupt_before=['human_in_loop'], checkpointer=memory)

# display(Image(graph.get_graph(xray=1).draw_mermaid_png()))


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


# TEST

query = "Identify and give me solutions to optimize my postgres database"
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
thread = {"configurable": {"thread_id": "1"}}

for event in graph.stream({"query":query,"schema":schema,}, thread, stream_mode="values"):
    analysis = event.get('analysis', '')
    print(analysis)

    with open("TEST.md", "w") as f:
        f.write(analysis)

    save_sql_queries(analysis)