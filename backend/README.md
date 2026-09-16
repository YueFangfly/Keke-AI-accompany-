# KeKe AI Backend

RAG + Agent 驱动的 AI 陪伴后端服务。为 [KeKe iOS App](../KekeApp/README.md) 提供智能对话、长期记忆和工具调用能力。

## Architecture

```
iOS App ── HTTP ──► FastAPI Backend ── API ──► Claude LLM
                         │
                         ├── RAG Memory (ChromaDB)
                         │   ├── Semantic chunking
                         │   ├── Embedding (all-MiniLM-L6-v2)
                         │   └── Cosine similarity search
                         │
                         ├── Agent System (ReAct Loop)
                         │   ├── Web search (DuckDuckGo)
                         │   ├── Memory read/write
                         │   ├── Weather (Open-Meteo)
                         │   ├── Health data analysis
                         │   ├── Calculator
                         │   └── Date/time
                         │
                         └── Auto memory extraction
```

## Core Components

### RAG Pipeline

**Retrieval-Augmented Generation** — gives the LLM access to conversation history and user facts via semantic search.

1. **Store**: text → semantic chunking → embedding (all-MiniLM-L6-v2) → ChromaDB
2. **Retrieve**: query → embedding → cosine similarity search → top-k results
3. **Augment**: retrieved context is injected into the system prompt before LLM generation

Chunking strategies:
- **Fixed-size**: splits at character boundaries with configurable overlap
- **Semantic**: splits on paragraph/sentence boundaries, merges small fragments
- **Conversation**: groups message turns into coherent dialogue chunks

### Agent System

Implements the **ReAct** (Reasoning + Acting) pattern:

1. User sends message
2. RAG retrieves relevant memories
3. LLM receives: system prompt + memories + user message + available tools
4. If LLM calls a tool → execute → feed result back → LLM reasons again
5. Repeat until LLM gives a final text response (max 10 rounds)
6. Auto-extract memorable facts from the exchange → store in RAG

Available tools:

| Tool | Description |
|------|-------------|
| `web_search` | Search the web via DuckDuckGo |
| `search_memory` | Semantic search over long-term memories |
| `save_memory` | Store a fact to long-term memory |
| `get_current_time` | Current date/time in CST |
| `get_weather` | Weather forecast via Open-Meteo API |
| `analyze_health` | Health metrics analysis with guidelines |
| `calculator` | Safe math expression evaluation |

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `POST` | `/chat` | Send message, get AI reply with RAG + Agent |
| `POST` | `/memory/add` | Manually add a memory |
| `POST` | `/memory/search` | Semantic search over memories |
| `GET` | `/memory/list` | List all memories for a user |

## Quick Start

```bash
cd backend

# Install dependencies
pip install -r requirements.txt

# Set your API key
cp .env.example .env
# Edit .env and add your Anthropic API key

# Run the server
python main.py
# Server starts at http://localhost:8000

# Or with uvicorn (auto-reload for development)
uvicorn main:app --reload
```

## Run Tests

```bash
cd backend
python -m pytest tests/ -v
```

No API key needed for tests — they test RAG, chunking, tools, and API endpoints without calling Claude.

## Docker

```bash
cd backend
docker build -t keke-backend .
docker run -p 8000:8000 -e ANTHROPIC_API_KEY=sk-ant-... keke-backend
```

## Tech Stack

- **Python 3.11+** / **FastAPI** — async web framework
- **Anthropic SDK** — Claude API for LLM
- **ChromaDB** — vector database for RAG
- **all-MiniLM-L6-v2** — embedding model (runs locally, no GPU needed)
- **Pydantic** — data validation
- **Docker** — containerized deployment

## Project Structure

```
backend/
├── main.py                 # FastAPI entry point & API routes
├── config.py               # Configuration (env vars, defaults)
├── requirements.txt        # Python dependencies
├── Dockerfile              # Docker deployment
├── models/
│   └── schemas.py          # Request/response Pydantic models
├── services/
│   ├── agent.py            # Agent: ReAct loop + tool orchestration
│   ├── memory.py           # RAG: ChromaDB vector store + search
│   └── chunking.py         # Text chunking strategies
├── tools/
│   ├── base.py             # Tool abstract base class
│   ├── web_search.py       # Web search (DuckDuckGo)
│   ├── memory_tool.py      # Memory read/write tools
│   ├── datetime_tool.py    # Date/time tool
│   ├── weather.py          # Weather forecast (Open-Meteo)
│   ├── health_analysis.py  # Health data analysis
│   └── calculator.py       # Safe math evaluation
└── tests/
    ├── test_api.py          # API endpoint tests
    ├── test_memory.py       # RAG memory tests
    ├── test_chunking.py     # Chunking strategy tests
    └── test_tools.py        # Tool unit tests
```
