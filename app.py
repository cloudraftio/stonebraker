import streamlit as st
from performer.performer import graph
from agentstate.agent_state import AgentState
from utils.sql_utils import extract_sql_queries

st.title("PostgreSQL Database Optimization Assistant")
st.markdown("""
This tool analyzes your PostgreSQL schema and provides actionable optimization suggestions.
You can refine the analysis through feedback until satisfied.
""")

query = st.text_area("Enter your query or optimization request:")
schema = st.text_area("Provide your PostgreSQL schema:")

if "thread_id" not in st.session_state:
    st.session_state.thread_id = f"performance_optimization_{hash(query + schema)}"
if "analysis_history" not in st.session_state:
    st.session_state.analysis_history = []

thread = {"configurable": {"thread_id": st.session_state.thread_id}}

def run_analysis():
    """Run analysis and update history"""
    with st.spinner("Analyzing..."):
        for event in graph.stream(
            {"query": query, "schema": schema},
            thread,
            stream_mode="values"
        ):
            if "analysis" in event:
                st.session_state.analysis_history.append(event["analysis"])

def extract_thinking_content(analysis):
    """Extracts the content between <think> and </think> tags."""
    start_tag = "<think>"
    end_tag = "</think>"
    start_index = analysis.find(start_tag)
    end_index = analysis.find(end_tag)
    if start_index != -1 and end_index != -1:
        return analysis[start_index + len(start_tag):end_index].strip()
    return None

def execute_sql_queries(edited_queries):
    """Extract and execute SQL queries from the final analysis."""
    current_state = graph.get_state(thread)
    schema = current_state.values.get("schema", "")

    # Update state with edited queries
    graph.update_state(thread, {"execute_query": edited_queries})

    # Execute each query
    for query in edited_queries.split(";"):
        query = query.strip()
        if query:  # Skip empty queries
            st.write(f"Executing: {query}")
            try:
                # Simulate execution (replace with actual SQL execution logic if needed)
                st.write("Query executed successfully.")
            except Exception as e:
                st.error(f"Failed to execute query: {query}. Error: {str(e)}")

if st.button("Analyze"):
    if query and schema:
        run_analysis()
    else:
        st.error("Please provide both query and schema")

if st.session_state.analysis_history:
    latest_analysis = st.session_state.analysis_history[-1]
    start_tag = "<think>"
    end_tag = "</think>"
    if start_tag in latest_analysis and end_tag in latest_analysis:
        start_index = latest_analysis.index(start_tag) + len(start_tag)
        end_index = latest_analysis.index(end_tag)
        thinking_content = latest_analysis[start_index:end_index].strip()
    else:
        thinking_content = "No detailed reasoning available for this analysis."

    with st.expander("Thinking Mode: View Detailed Reasoning", expanded=False):
        st.markdown(thinking_content)

    st.subheader("Analysis History")
    for i, analysis in enumerate(st.session_state.analysis_history, 1):
        st.write(f"Iteration {i}:")
        st.markdown(analysis)

    st.subheader("Feedback")
    col1, col2 = st.columns(2)
    
    with col1:
        if st.button("Yes - Accept Analysis"):
            graph.update_state(thread, {"execute": True})
            st.success("Analysis accepted! Proceeding to SQL execution...")
            
            # Extract SQL queries from the latest analysis
            current_state = graph.get_state(thread)
            analysis = current_state.values.get("analysis", "")
            sql_queries = extract_sql_queries(analysis)

            if not sql_queries:
                st.warning("No SQL queries found in the analysis.")
            else:
                # Display SQL queries in an editable text area
                edited_queries = st.text_area("Edit SQL Queries:", value=sql_queries), height=200)

                # Add an "Execute" button to confirm and execute the edited queries
                if st.button("Execute Edited Queries"):
                    execute_sql_queries(edited_queries)

    with col2:
        if st.button("No - Revise Analysis"):
            st.session_state.show_feedback = True
            st.query_params = {"status": "needs_revision"}
            st.rerun()

    if st.session_state.get("show_feedback", False):
        feedback = st.text_area("Provide specific feedback:")
        if st.button("Submit Feedback"):
            if feedback:
                graph.update_state(thread, {
                    "feedback": feedback,
                    "reanalyze": True,
                    "analysis_history": st.session_state.analysis_history
                })
                run_analysis()
                st.session_state.show_feedback = False
                st.query_params = {"status": "revised"}
                st.rerun()
            else:
                st.warning("Feedback cannot be empty")