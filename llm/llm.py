from langchain_groq import ChatGroq as Groq
from langchain_ollama import ChatOllama as Ollama # Use this for testing purpose only
import dotenv


llm = Groq (
    # temperature=0.1,
    model_name=dotenv.get_key(".env", "GROQ_MODEL"),
    groq_api_key=dotenv.get_key(".env", "GROQ_API_KEY") 
)

analyze_llm = Groq (
    # temperature=0.1,
    model_name=dotenv.get_key(".env", "ANALYZING_MODEL"),
    groq_api_key=dotenv.get_key(".env", "GROQ_API_KEY") 
)

ollama_llm = Ollama(
    model=dotenv.get_key(".env", "OLLAMA_MODEL"),
)