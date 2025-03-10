from langgraph.graph import StateGraph, END, START
from langgraph.checkpoint.memory import MemorySaver
from agentstate.agent_state import AgentState, TestingState
from langchain_core.messages import SystemMessage, HumanMessage
from llm.llm import llm
from utils.sql_utils import extract_sql_queries
from sql.sql_agent import SQLAgent
import logging

logger = logging.getLogger(__name__)

def create_tester_graph():
    logger.info("Creating tester graph...")
    builder = StateGraph(TestingState)

    def testing_agent(state: TestingState):
        logger.debug("Starting testing agent...")

        try:
            before_results = run_test("before_exec", state["schema"], "")
            state["before_exec"] = before_results["before_exec"]
            
            if state["execute_query"]:
                after_results = run_test("after_exec", state["schema"], state["execute_query"])
                state["after_exec"] = after_results["after_exec"]
            
            return state
            
        except Exception as e:
            logger.error(f"Testing failed: {str(e)}")
            return state

    def run_test(type: str, schema: str, execute_query: str):
        max_retries = 3
        current_try = 0
        
        while current_try < max_retries:
            try:
                if type == "before_exec":
                    system_prompt = SystemMessage(
                        content=f"""
                        You are an expert in PostgreSQL database optimization and query analysis.  
                        Given the following database schema, generate valid SQL queries to test its functionality.  
                        Return **only** valid SQL queries, with no additional explanations.  

                        **Schema:**  
                        {schema}
                        """
                    )
                    state_to_return = "before_exec"
                else:
                    system_prompt = SystemMessage(
                        content=f"""
                        You are an expert in PostgreSQL database optimization and query analysis.  
                        Below is the database schema and a set of optimized queries provided for performance improvement.  
                        Generate valid SQL queries to test the schema, incorporating these optimizations where applicable.  
                        Return **only** valid SQL queries, with no additional explanations.  

                        **Schema:**  
                        {schema}  

                        **Optimized Queries:**  
                        {execute_query}
                        """
                    )
                    state_to_return = "after_exec"

                user_message = HumanMessage(
                    content="Provide specific postgres queries to test the performance of my database."
                )
                
                response = llm.invoke([system_prompt, user_message])
                
                if response.content:
                    sql_queries = extract_sql_queries(response.content)
                    if sql_queries:
                        sql_agent = SQLAgent()
                        results = sql_agent.execute_queries(sql_queries)
                        logger.info(f"Successfully tested the schema for {type}")
                        return {state_to_return: results}
                
                logger.warning(f"Attempt {current_try + 1}: Invalid SQL response, retrying...")
                current_try += 1
                
            except Exception as e:
                logger.error(f"Attempt {current_try + 1} failed: {str(e)}")
                current_try += 1
                
        return {state_to_return: f"Error in testing the schema for {type}: Could not generate valid SQL queries"}

    def analyze_test(state: TestingState):
        system_prompt = SystemMessage(content=f"""
        You are a postgreSQL database performance expert. Analyze these results:
        Before Optimization: {state['before_exec']}
        After Optimization: {state.get('after_exec', 'No optimization performed')}
        
        Compare the performance and provide detailed analysis on improvements or issues.
        """)

        user_prompt = HumanMessage(
            content="Analyze the performance results and provide detailed insights."
        )

        try:
            response = llm.invoke([system_prompt, user_prompt])
            logger.info("Successfully generated analysis")
            state["results"] = response.content
            return state
        except Exception as e:
            logger.error(f"Analysis failed: {str(e)}")
            state["results"] = "Error in analysis generation"
            return state

    def human_in_loop(state: TestingState):
        logger.info("Requesting human feedback for cleanup...")
        return state

    def windup(state: TestingState):
        if not state.get("proceed_cleanup", False):
            logger.info("Cleanup not authorized, skipping...")
            return state

        logger.debug("Starting cleanup process...")
        max_retries = 3
        current_try = 0
        
        while current_try < max_retries:
            try:
                system_prompt = SystemMessage(content=f"""
                You are a postgreSQL database expert. Generate cleanup queries for:
                Schema: {state['schema']}
                Executed Queries: {state['execute_query']}
                Return only valid SQL cleanup queries.
                """)

                user_prompt = HumanMessage(
                    content="Generate cleanup queries for the optimization changes."
                )

                response = llm.invoke([system_prompt, user_prompt])
                
                if response.content:
                    sql_queries = extract_sql_queries(response.content)
                    if sql_queries:
                        sql_agent = SQLAgent()
                        results = sql_agent.execute_queries(sql_queries)
                        logger.info("Successfully executed cleanup")
                        state["wind_up"] = results
                        return state
                
                current_try += 1
                logger.warning(f"Attempt {current_try}: Invalid cleanup queries")

            except Exception as e:
                logger.error(f"Cleanup attempt {current_try + 1} failed: {str(e)}")
                current_try += 1

        state["wind_up"] = "Error in cleanup: Could not generate valid SQL queries"
        return state

    builder.add_node("testing_agent", testing_agent)
    builder.add_node("analyze_test", analyze_test)
    builder.add_node("human_in_loop", human_in_loop)
    builder.add_node("windup", windup)

    builder.add_edge(START, "testing_agent")
    builder.add_edge("testing_agent", "analyze_test")
    builder.add_edge("analyze_test", "human_in_loop")
    builder.add_conditional_edges(
        "human_in_loop",
        lambda s: "windup" if s.get("proceed_cleanup", False) else END,
        {"windup", END}
    )
    builder.add_edge("windup", END)

    return builder.compile(
        interrupt_before=['human_in_loop'],
        checkpointer=MemorySaver()
    )