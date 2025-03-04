from agentstate.agent_state import AgentState
from typing import Literal
from langgraph.types import Command, interrupt
from langgraph.graph import MessagesState, StateGraph, START


def human(state: AgentState, config) -> Command[Literal["analysis","another_agent"]]:
    user_input = interrupt(value="Ready for user input")
    langgraph_triggers = config["metadata"]["langgraph_triggers"]
    if len(langgraph_triggers) != 1:
        raise AssertionError("Expected exactly 1 trigger in human node")
    active_agent = langgraph_triggers[0].split(":")[1]
    return Command(
            update={
                "messages": [
                    {
                        "role": "human",
                        "content": user_input,
                    }
                ]
            },
            goto=active_agent,
        )

