import streamlit as st
from performer.performer import graph
from agentstate.agent_state import AgentState

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

if st.button("Analyze"):
    if query and schema:
        run_analysis()
    else:
        st.error("Please provide both query and schema")

if st.session_state.analysis_history:
    st.subheader("Analysis History")
    for i, analysis in enumerate(st.session_state.analysis_history, 1):
        st.write(f"Iteration {i}:")
        st.code(analysis)

    st.subheader("Feedback")
    col1, col2 = st.columns(2)
    
    with col1:
        if st.button("Yes - Accept Analysis"):
            graph.update_state(thread, {"execute": True})
            st.success("Analysis accepted! Proceeding to execution...")
            st.query_params = {"status": "completed"}
            st.rerun()
    
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