from agentstate.agent_state import AgentState
from langgraph.checkpoint.memory import MemorySaver
from langchain_core.messages import SystemMessage, HumanMessage, RemoveMessage
from llm.llm import llm # Change according to where you want to test with
from langgraph.graph import START, END, StateGraph
from sql.sql_agent import SQLAgent
from langchain_core.tools import tool
from typing import Annotated, Literal
from langgraph.types import Command, interrupt
from feedback.human_in_loop import human
from utils.sql_utils import extract_sql_queries


db_config = {
    "user": "postgres",
    "password": "postgres",
    "host": "localhost",
    "port": "5432",
    "database": "ecommerce_db"
}

sql_agent = SQLAgent(db_config=db_config,name="SQLAgent")
get_dB_schema = sql_agent.get_schema() # Use this schema for dynamic databases


# @tool
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
    # sql_commands = extract_sql_commands(response.content)  # New helper function
    return {
        "analysis": response.content,
        "feedback": fdb,
        "schema": schema,
        "query": query
    }


def human_in_loop(state: AgentState):
    user_response = input("\nAre you satisfied with the analysis? (yes/no): ").strip().lower()
    
    if user_response == "no":
        feedback = input("\nPlease provide specific feedback for improvement: ")
        return {"feedback": feedback, "execute": False, "reanalyze": True}
    
    return {"feedback": "", "execute": True, "reanalyze": False}

def should_continue(state: AgentState):
    if state.get("reanalyze", False):
        return "analyze_database"
    return "create_human_readable" if state.get("execute") else END

# @tool
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

    sql_queries = extract_sql_queries(response.content)
    state.update("execute_queries", sql_queries)

    output_file = "REPORT.md"
    with open(output_file, "w") as f:
        f.write(response.content)

    return {
        "mrk_down": response.content,
        "execute_query": sql_queries,
        **state
    }


# def verify_sql(queries, schema: str) -> bool:
    

# @tool
def sql_executor(state: AgentState) -> Command[Literal["sql_executor", END]]: # type: ignore
    execute_query = state.get("execute_query","")
    sys_message = SystemMessage(
        content="""
        You are a SQL expert.
        You have a great experience in working with Postgres Database.
        Your main goal is to verify the incoming sql query to the provided schema.
        Make sure you only print true or false.
        true if the SQL format is ok.
        false if the SQL format is not ok. 
        """
    )

    schema = state.get("schema","")
    hmn_message = HumanMessage(
        content=(
        "Check, if my SQL query will correctly execute or not."
        f"SQL Queries: {execute_query}"
        f"Schema: {schema}"
        )
    )
    
    message = [
        sys_message,
        hmn_message
    ]

    response = llm.invoke(message)

    if response.content == "true":
        sql_agent.execute_query(execute_query)
        return END  
    else:
        return "sql_executor" 
    

builder = StateGraph(AgentState)

builder.add_node("analyze_database", analyze_database)
builder.add_node("human_in_loop", human_in_loop)
builder.add_node("create_human_readable", create_human_readable)
builder.add_node("sql_executor", sql_executor)
# builder.add_node("human", human)

builder.add_edge(START, "analyze_database")
builder.add_edge("analyze_database", "human_in_loop")
builder.add_conditional_edges(
    "human_in_loop",
    lambda s: "analyze_database" if s["reanalyze"] else "create_human_readable",
    {"analyze_database", "create_human_readable"}
)
builder.add_edge("create_human_readable", "sql_executor")

memory = MemorySaver()
graph = builder.compile(interrupt_before=['human_in_loop'], checkpointer=memory)
