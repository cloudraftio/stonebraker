from typing_extensions import TypedDict 

class AgentState(TypedDict):
    query: str
    analysis: str
    schema: str    
    feedback: str