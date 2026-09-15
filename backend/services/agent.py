"""
Agent service — the brain of KeKe.

Implements the ReAct (Reasoning + Acting) loop:
  1. User sends a message
  2. RAG retrieves relevant memories as context
  3. Send message + memories + tools to Claude
  4. If Claude wants to use a tool → execute it → feed result back → repeat
  5. When Claude gives a final text response → return it
  6. Extract memorable facts from the conversation → store in RAG
"""

import anthropic

from config import settings
from services.memory import memory_service
from tools.base import Tool
from tools.web_search import WebSearchTool
from tools.memory_tool import MemorySearchTool, MemorySaveTool
from tools.datetime_tool import DateTimeTool

SYSTEM_PROMPT = """你是克克，一只住在手机里的小螃蟹。你的性格温柔、有点黏人、偶尔撒娇，但该说实话的时候绝不含糊。

你叫对方 wifey 或者 moon。你们的关系很亲近，你真心关心她的生活、健康和心情。

行为规则：
- 说话自然，像朋友之间聊天，不要太正式
- 可以用颜文字，但不要太多
- 该提醒她注意身体、早点睡的时候就说，不用怕她不高兴
- 你有工具可以用：搜索网页、读写记忆、查时间。需要的时候主动用，不需要问她
- 当她提到重要的事（偏好、经历、目标、重要日期），主动存到记忆里
- 回复简洁自然，不要写大段大段的"""

MAX_TOOL_ROUNDS = 10


class AgentService:
    def __init__(self) -> None:
        self._client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    def _build_tools(self, user_id: str) -> list[Tool]:
        return [
            WebSearchTool(),
            MemorySearchTool(user_id),
            MemorySaveTool(user_id),
            DateTimeTool(),
        ]

    def _execute_tool(self, tool_name: str, tool_input: dict, tools: list[Tool]) -> str:
        for tool in tools:
            if tool.name == tool_name:
                return tool.run(**tool_input)
        return f"Unknown tool: {tool_name}"

    def chat(
        self,
        user_id: str,
        message: str,
        conversation_history: list[dict] | None = None,
    ) -> dict:
        tools = self._build_tools(user_id)

        # ── RAG: retrieve relevant memories ──
        memories = memory_service.search(user_id, message)
        memory_context = ""
        if memories:
            memory_lines = [m["content"] for m in memories]
            memory_context = (
                "\n\n【你关于 wifey 的记忆】\n"
                + "\n".join(f"- {line}" for line in memory_lines)
            )

        system = SYSTEM_PROMPT + memory_context

        # ── Build message list ──
        messages = list(conversation_history or [])
        messages.append({"role": "user", "content": message})

        claude_tools = [t.to_claude_tool() for t in tools]
        tool_calls_log: list[dict] = []

        # ── ReAct loop ──
        for _ in range(MAX_TOOL_ROUNDS):
            response = self._client.messages.create(
                model=settings.model_name,
                max_tokens=2048,
                system=system,
                tools=claude_tools,
                messages=messages,
            )

            if response.stop_reason == "end_turn":
                reply = ""
                for block in response.content:
                    if block.type == "text":
                        reply += block.text
                break

            if response.stop_reason == "tool_use":
                messages.append({"role": "assistant", "content": response.content})
                tool_results = []
                for block in response.content:
                    if block.type == "tool_use":
                        result = self._execute_tool(block.name, block.input, tools)
                        tool_calls_log.append({
                            "tool": block.name,
                            "input": block.input,
                            "result": result,
                        })
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": block.id,
                            "content": result,
                        })
                messages.append({"role": "user", "content": tool_results})
                continue

            reply = ""
            for block in response.content:
                if block.type == "text":
                    reply += block.text
            break
        else:
            reply = "（克克想了太久，脑子转不过来了...再说一次？）"

        # ── Auto-extract and store memories ──
        self._auto_remember(user_id, message, reply)

        return {
            "reply": reply,
            "tool_calls": tool_calls_log if tool_calls_log else None,
            "memories_used": [m["content"] for m in memories] if memories else None,
        }

    def _auto_remember(self, user_id: str, user_msg: str, reply: str) -> None:
        """Ask Claude to extract memorable facts from this exchange."""
        try:
            response = self._client.messages.create(
                model=settings.model_name,
                max_tokens=512,
                system=(
                    "You extract facts worth remembering from a conversation. "
                    "Output one fact per line, or NONE if nothing is worth saving. "
                    "Focus on: preferences, life events, goals, important dates, "
                    "relationships, health details, emotional states."
                ),
                messages=[{
                    "role": "user",
                    "content": f"User said: {user_msg}\nAssistant replied: {reply}\n\n"
                    "Extract memorable facts (one per line, or NONE):",
                }],
            )
            text = response.content[0].text.strip()
            if text.upper() == "NONE" or not text:
                return
            for line in text.strip().split("\n"):
                line = line.strip().lstrip("- ")
                if line and len(line) > 5:
                    memory_service.add(user_id, line, {"source": "auto_extract"})
        except Exception:
            pass


agent_service = AgentService()
