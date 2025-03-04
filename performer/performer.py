from agentstate.agent_state import AgentState
from langgraph.checkpoint.memory import MemorySaver
from langchain_core.messages import SystemMessage, HumanMessage, RemoveMessage
from llm.llm import llm # Change according to where you want to test with
from langgraph.graph import START, END, StateGraph


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
