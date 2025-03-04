# This is postgres performant agent

### Setup

#### .env Setup
```.env
GROQ_API_KEY=""
GROQ_MODEL="llama-3.3-70b-specdec"
ANALYZING_MODEL="deepseek-r1-distill-llama-70b-specdec"
OLLAMA_MODEL="llama3.2"
```

#### Prerequisites
- Python
- Groq/Ollama API Keys

1. `pip install -r requirements.txt`
2. Set up your API keys/url endpoints.
3. test out the code : `python testing.py`