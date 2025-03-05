from langgraph.graph import StateGraph, END, START
from langgraph.checkpoint.memory import MemorySaver
from agentstate.agent_state import AgentState
from langchain_core.messages import SystemMessage, HumanMessage
from llm.llm import llm  # Make sure this is imported properly
from utils.sql_utils import extract_sql_queries
from sql.sql_agent import SQLAgent
from typing import Literal
from langgraph.types import Command
import logging

logger = logging.getLogger(__name__)

def create_performer_graph(db_config: dict):
    logger.info("Creating optimization performer graph...")
    
    builder = StateGraph(AgentState)

    def analyze_database(state: AgentState):
        logger.debug("Starting database analysis...")
        
        system_prompt = SystemMessage(content=f"""
        You are a database optimization expert. Analyze the PostgreSQL schema and provide optimization suggestions.
        Schema: {state['schema']}
        User Query: {state['query']}
        Previous Feedback: {state.get('feedback', '')}
        """)
        
        user_message = HumanMessage(content="Provide specific optimization recommendations including indexes, query improvements, and schema changes.")
        
        try:
            response = llm.invoke([system_prompt, user_message])
            logger.info("Successfully generated analysis")
            return {"analysis": response.content}
        except Exception as e:
            logger.error(f"Analysis failed: {str(e)}")
            return {"analysis": "Error in analysis generation"}

    def human_in_loop(state: AgentState):
        logger.info("Requesting human feedback...")
        return state

    def create_human_readable(state: AgentState):
        logger.debug("Generating human-readable report...")
        
        system_prompt = SystemMessage(content="""
        You are a technical writer. Convert the technical analysis into markdown format.
        Keep SQL code blocks intact and explanations clear.
        """)
        
        user_message = HumanMessage(content=f"Analysis to convert:\n{state['analysis']}")
        
        try:
            response = llm.invoke([system_prompt, user_message])
            sql_queries = extract_sql_queries(response.content)
            logger.info(f"Extracted {len(sql_queries.split(';'))} SQL queries")
            return {
                "mrk_down": response.content,
                "execute_query": sql_queries
            }
        except Exception as e:
            logger.error(f"Report generation failed: {str(e)}")
            return {"mrk_down": "Error generating report", "execute_query": ""}

    def sql_executor(state: AgentState) -> Command[Literal["sql_executor", END]]: # type: ignore
        logger.info("Executing SQL queries...")
        
        if not state.get("execute_query"):
            logger.warning("No SQL queries to execute")
            return END
            
        try:
            sql_agent = SQLAgent(db_config=state["db_config"])
            for query in state["execute_query"].split(";"):
                query = query.strip()
                if query:
                    logger.info(f"Executing: {query[:50]}...")
                    sql_agent.execute_query(query)
            logger.info("All SQL queries executed successfully")
            return END
        except Exception as e:
            logger.error(f"SQL execution failed: {str(e)}")
            return "sql_executor"

    builder.add_node("analyze_database", analyze_database)
    builder.add_node("human_in_loop", human_in_loop)
    builder.add_node("create_human_readable", create_human_readable)
    builder.add_node("sql_executor", sql_executor)

    builder.add_edge(START, "analyze_database")
    builder.add_edge("analyze_database", "human_in_loop")
    builder.add_conditional_edges(
        "human_in_loop",
        lambda s: "analyze_database" if s.get("reanalyze", False) else "create_human_readable",
        {"analyze_database", "create_human_readable"}
    )
    builder.add_edge("create_human_readable", "sql_executor")

    return builder.compile(
        interrupt_before=['human_in_loop'],
        checkpointer=MemorySaver()
    )