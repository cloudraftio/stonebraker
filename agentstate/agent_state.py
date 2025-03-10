from typing_extensions import TypedDict, List
# from performer.performer import sql_agent

class AgentState(TypedDict):
    query: str
    analysis: str
    schema: str
    execute: bool
    reanalyze: bool
    feedback: str
    execute_query: str
    mrk_down: str

    # Add this whenever necessary
    # def __init__(self):
    #     super().__init__()
    #     self["schema"] = sql_agent.get_schema()

class TestingState(TypedDict):
    schema: str
    execute_query: str
    before_exec: str
    after_exec: str
    results: str
    wind_up: str
    proceed_cleanup: bool