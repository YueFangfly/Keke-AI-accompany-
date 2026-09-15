"""
KeKe AI Backend — FastAPI server.

Endpoints:
  POST /chat          — Send a message, get KeKe's reply (with RAG + Agent)
  POST /memory/add    — Manually add a memory
  POST /memory/search — Search memories (for debugging / the Memory page)
  GET  /memory/list   — List all memories for a user
  GET  /health        — Health check
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from models.schemas import (
    ChatRequest,
    ChatResponse,
    MemoryAddRequest,
    MemorySearchRequest,
)
from services.agent import agent_service
from services.memory import memory_service

app = FastAPI(title="KeKe AI Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_conversation_store: dict[str, list[dict]] = {}


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "keke-ai-backend"}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    history_key = f"{req.user_id}:{req.conversation_id}"
    history = _conversation_store.get(history_key, [])

    result = agent_service.chat(
        user_id=req.user_id,
        message=req.message,
        conversation_history=history,
    )

    history.append({"role": "user", "content": req.message})
    history.append({"role": "assistant", "content": result["reply"]})
    from config import settings
    history[:] = history[-(settings.max_conversation_history * 2):]
    _conversation_store[history_key] = history

    return ChatResponse(**result)


@app.post("/memory/add")
def add_memory(req: MemoryAddRequest):
    doc_id = memory_service.add(req.user_id, req.content, req.metadata)
    return {"id": doc_id, "status": "saved"}


@app.post("/memory/search")
def search_memory(req: MemorySearchRequest):
    results = memory_service.search(req.user_id, req.query, req.top_k)
    return {"results": results}


@app.get("/memory/list")
def list_memories(user_id: str = "default"):
    return {"memories": memory_service.list_all(user_id)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
