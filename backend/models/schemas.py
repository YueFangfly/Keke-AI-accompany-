"""Request and response schemas for the API."""

from pydantic import BaseModel


class ChatRequest(BaseModel):
    message: str
    user_id: str = "default"
    conversation_id: str = "default"


class ChatResponse(BaseModel):
    reply: str
    tool_calls: list[dict] | None = None
    memories_used: list[str] | None = None


class MemoryAddRequest(BaseModel):
    user_id: str = "default"
    content: str
    metadata: dict | None = None


class MemorySearchRequest(BaseModel):
    user_id: str = "default"
    query: str
    top_k: int = 5
