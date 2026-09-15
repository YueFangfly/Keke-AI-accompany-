"""Memory tool — lets the Agent read/write long-term memories."""

from tools.base import Tool
from services.memory import memory_service


class MemorySearchTool(Tool):
    name = "search_memory"
    description = (
        "Search your long-term memory for past conversations and facts about the user. "
        "Use this when the user refers to something you talked about before, "
        "or when you need context about their preferences, experiences, or history."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "What to search for in memory",
            },
        },
        "required": ["query"],
    }

    def __init__(self, user_id: str = "default") -> None:
        self._user_id = user_id

    def run(self, *, query: str) -> str:
        results = memory_service.search(self._user_id, query)
        if not results:
            return "No relevant memories found."
        lines = []
        for m in results:
            lines.append(f"- {m['content']} (relevance: {1 - m['distance']:.2f})")
        return "Relevant memories:\n" + "\n".join(lines)


class MemorySaveTool(Tool):
    name = "save_memory"
    description = (
        "Save an important fact or detail about the user to long-term memory. "
        "Use this when the user shares something worth remembering: "
        "preferences, life events, goals, important dates, etc."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "content": {
                "type": "string",
                "description": "The fact or detail to remember",
            },
        },
        "required": ["content"],
    }

    def __init__(self, user_id: str = "default") -> None:
        self._user_id = user_id

    def run(self, *, content: str) -> str:
        memory_service.add(self._user_id, content)
        return f"Saved to memory: {content}"
