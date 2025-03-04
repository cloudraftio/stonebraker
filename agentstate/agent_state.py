from typing_extensions import TypedDict 
from performer.performer import sql_agent

class AgentState(TypedDict):
    query: str
    analysis: str
    schema: str
    execute: bool
    feedback: str
    execute_query: str

    # Add this whenever necessary
    # def __init__(self):
    #     super().__init__()
    #     self["schema"] = sql_agent.get_schema()