import streamlit as st
import logging
from typing import Dict, Any
from performer.performer import create_performer_graph
from agentstate.agent_state import AgentState
from utils.sql_utils import extract_sql_queries
from sql.sql_agent import SQLAgent

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("app.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

st.set_page_config(page_title="DB Optimizer", layout="wide")
st.title("PostgreSQL Database Optimization Assistant")

with st.sidebar:
    st.header("Database Configuration")
    db_host = st.text_input("Host", value="localhost")
    db_port = st.number_input("Port", value=5432, min_value=1, max_value=65535)
    db_user = st.text_input("Username", value="postgres")
    db_password = st.text_input("Password", type="password", value="postgres")
    db_name = st.text_input("Database Name", value="ecommerce_db")
    test_connection = st.button("Test Connection")

db_config = {
    "host": db_host,
    "port": db_port,
    "user": db_user,
    "password": db_password,
    "database": db_name
}

if test_connection:
    try:
        agent = SQLAgent(db_config)
        schema = agent.get_schema()
        st.success(f"Connected successfully to {db_name}! Found {len(schema)} tables.")
        logger.info(f"Successful connection to {db_config['database']}")
    except Exception as e:
        st.error(f"Connection failed: {str(e)}")
        logger.error(f"Connection error: {str(e)}")

query = st.text_area(
    "Optimization Request",
    placeholder="E.g.: 'Analyze query performance for slow orders report'",
    height=100
)

if "thread_id" not in st.session_state:
    st.session_state.thread_id = f"thread_{hash(frozenset(db_config.items()))}"
if "analysis_history" not in st.session_state:
    st.session_state.analysis_history = []

def initialize_agent():
    try:
        logger.info("Initializing SQL agent...")
        agent = SQLAgent(db_config)
        return agent
    except Exception as e:
        st.error(f"Agent initialization failed: {str(e)}")
        logger.critical(f"Agent init failure: {str(e)}")
        st.stop()

def run_analysis():
    agent = initialize_agent()
    schema = agent.get_schema()
    
    st.session_state.graph = create_performer_graph(db_config)
    
    initial_state = AgentState(
        query=query,
        schema=str(schema),
        db_config=db_config,
        analysis="",
        feedback="",
        execute=False,
        reanalyze=False,
        execute_query="",
        mrk_down=""
    )
    
    with st.status("Running optimization analysis...", expanded=True) as status:
        try:
            for event in st.session_state.graph.stream(
                initial_state,
                {"configurable": {"thread_id": st.session_state.thread_id}},
                stream_mode="values"
            ):
                if "analysis" in event:
                    st.session_state.analysis_history.append(event["analysis"])
                    status.write(f"Analysis iteration {len(st.session_state.analysis_history)} completed")
                    logger.info(f"New analysis generated: {event['analysis'][:50]}...")
            
            status.update(label="Analysis complete!", state="complete", expanded=False)
        except Exception as e:
            st.error(f"Analysis pipeline failed: {str(e)}")
            logger.error(f"Graph stream error: {str(e)}")
            st.stop()

def display_analysis():
    if not st.session_state.analysis_history:
        return

    latest = st.session_state.analysis_history[-1]
    
    with st.expander("Latest Optimization Report", expanded=True):
        st.markdown(latest)
    
    st.subheader("Analysis History")
    for i, analysis in enumerate(st.session_state.analysis_history, 1):
        with st.expander(f"Iteration {i}", expanded=False):
            st.markdown(analysis)

def execute_queries():
    if not st.session_state.analysis_history:
        return
    
    current_analysis = st.session_state.analysis_history[-1]
    sql_queries = extract_sql_queries(current_analysis)
    
    if not sql_queries:
        st.warning("No SQL queries found in the analysis")
        return
    
    with st.form("query_execution"):
        edited_queries = st.text_area(
            "SQL Queries to Execute",
            value=sql_queries,
            height=300
        )
        
        if st.form_submit_button("Execute Queries"):
            try:
                agent = SQLAgent(db_config)
                queries = [q.strip() for q in edited_queries.split(";") if q.strip()]
                
                with st.status("Executing SQL...") as status:
                    for i, query in enumerate(queries, 1):
                        try:
                            st.write(f"**Query {i}:**")
                            st.code(query, language="sql")
                            result = agent.execute_query(query)
                            st.json(result)
                            st.success("Executed successfully")
                            logger.info(f"Executed query {i}: {query[:50]}...")
                        except Exception as e:
                            st.error(f"Execution failed: {str(e)}")
                            logger.error(f"Query {i} error: {str(e)}")
            except Exception as e:
                st.error(f"Execution setup failed: {str(e)}")
                logger.error(f"Execution setup error: {str(e)}")

if st.button("Start/Restart Analysis"):
    if not all(db_config.values()):
        st.error("Please fill all database credentials")
    elif not query:
        st.error("Please enter an optimization request")
    else:
        run_analysis()

display_analysis()
execute_queries()