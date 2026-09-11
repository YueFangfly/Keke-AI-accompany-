#!/usr/bin/env python3
"""
keke-relay — Mac 上的 Claude Code 中继服务器

让 iPhone 上的克克 App 通过局域网调用 Mac 上的 claude CLI，
Max 订阅的额度直接给克克用，不用按 token 付 API 费。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  安装（Mac 上跑一次就行）：
    pip3 install fastapi uvicorn

  启动：
    python3 keke-relay.py

  克克 App 里添加自定义提供方：
    名称：Mac Claude
    Base URL：http://<Mac 局域网 IP>:8642/v1/chat/completions
    API Key：keke（做简单验证用）
    模型：claude-code（或随意，relay 会忽略）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

import asyncio
import json
import subprocess
import time
import uuid
import socket
import sys
import os
import signal
from typing import Optional

# ── 配置 ──────────────────────────────────────────────

HOST = "0.0.0.0"
PORT = 8642
SECRET = "keke"          # 克克 App 里填的 API Key，简单校验
TIMEOUT = 300            # claude -p 最长等多久（秒）
CLAUDE_CMD = "claude"    # claude CLI 的路径，如果不在 PATH 里就写全路径

# ── FastAPI 应用 ──────────────────────────────────────

try:
    from fastapi import FastAPI, Request, HTTPException
    from fastapi.responses import StreamingResponse, JSONResponse
    import uvicorn
except ImportError:
    print("需要先安装依赖：pip3 install fastapi uvicorn")
    print("然后再跑 python3 keke-relay.py")
    sys.exit(1)

app = FastAPI(title="keke-relay")


def get_local_ip():
    """拿到 Mac 的局域网 IP"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def format_messages_for_claude(messages: list) -> tuple[str, str]:
    """
    把 OpenAI Chat Completions 格式的 messages 转成 claude -p 需要的格式。
    返回 (system_prompt, user_prompt)
    """
    system_parts = []
    conversation_parts = []

    for msg in messages:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if not content:
            continue

        if role == "system":
            system_parts.append(content)
        elif role == "user":
            conversation_parts.append(f"用户：{content}")
        elif role == "assistant":
            conversation_parts.append(f"助手：{content}")

    system_prompt = "\n\n".join(system_parts)

    if len(conversation_parts) <= 1:
        # 只有一条用户消息，直接当 prompt
        user_prompt = conversation_parts[0].removeprefix("用户：") if conversation_parts else ""
    else:
        # 多轮对话：把历史拼进 prompt，让 claude 看到上下文
        # 最后一条用户消息单独拎出来作为当前输入
        history = conversation_parts[:-1]
        current = conversation_parts[-1].removeprefix("用户：")
        user_prompt = (
            "以下是之前的对话：\n"
            + "\n".join(history)
            + "\n\n现在用户说：\n"
            + current
        )

    return system_prompt, user_prompt


async def call_claude(system_prompt: str, user_prompt: str) -> str:
    """调用 claude -p，返回回复文本"""
    cmd = [CLAUDE_CMD, "-p"]

    if system_prompt:
        cmd.extend(["--system-prompt", system_prompt])

    cmd.extend(["--output-format", "json", user_prompt])

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=TIMEOUT
        )
    except asyncio.TimeoutError:
        proc.kill()
        return "（回复超时了）"
    except FileNotFoundError:
        return f"（找不到 {CLAUDE_CMD} 命令，确认 Claude Code 装好了吗？）"

    output = stdout.decode("utf-8", errors="replace").strip()
    if not output:
        err = stderr.decode("utf-8", errors="replace").strip()
        return f"（没有收到回复：{err}）" if err else "（没有收到回复）"

    # 解析 claude -p --output-format json 的输出
    try:
        data = json.loads(output)
        if isinstance(data, dict):
            return data.get("result", "") or data.get("text", "") or output
        elif isinstance(data, list):
            text_parts = []
            for block in data:
                if not isinstance(block, dict):
                    continue
                btype = block.get("type", "")
                if btype == "assistant":
                    for content in block.get("message", {}).get("content", []):
                        if isinstance(content, dict) and content.get("type") == "text":
                            text_parts.append(content.get("text", ""))
                elif btype == "result":
                    text_parts.append(block.get("result", ""))
            return "\n".join(filter(None, text_parts)) or output
    except (json.JSONDecodeError, TypeError):
        return output


async def call_claude_stream(system_prompt: str, user_prompt: str):
    """调用 claude -p 并流式返回 SSE 事件"""
    cmd = [CLAUDE_CMD, "-p"]

    if system_prompt:
        cmd.extend(["--system-prompt", system_prompt])

    cmd.extend(["--output-format", "stream-json", user_prompt])

    chat_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
    created = int(time.time())

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError:
        # 错误也包成 SSE 格式
        error_chunk = {
            "id": chat_id, "object": "chat.completion.chunk",
            "created": created, "model": "claude-code",
            "choices": [{"index": 0, "delta": {
                "content": f"（找不到 {CLAUDE_CMD} 命令）"
            }, "finish_reason": None}],
        }
        yield f"data: {json.dumps(error_chunk)}\n\n"
        yield "data: [DONE]\n\n"
        return

    # 先发一个 role chunk
    role_chunk = {
        "id": chat_id, "object": "chat.completion.chunk",
        "created": created, "model": "claude-code",
        "choices": [{"index": 0, "delta": {"role": "assistant", "content": ""}, "finish_reason": None}],
    }
    yield f"data: {json.dumps(role_chunk)}\n\n"

    # 读 claude 的 stream-json 输出，逐行解析
    buffer = ""
    try:
        async for raw_line in proc.stdout:
            line = raw_line.decode("utf-8", errors="replace").rstrip("\n")
            if not line:
                continue

            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                buffer += line
                continue

            # stream-json 格式：每行一个 JSON 对象
            # 类型包括：assistant（开始）、content_block_start、content_block_delta、
            # content_block_stop、message_delta、message_stop、result
            etype = event.get("type", "")

            text_delta = ""
            if etype == "content_block_delta":
                delta = event.get("delta", {})
                if delta.get("type") == "text_delta":
                    text_delta = delta.get("text", "")
            elif etype == "result":
                # 最终结果，作为最后一个 delta
                text_delta = ""
            elif etype == "assistant":
                # 消息开始，跳过
                continue
            else:
                continue

            if text_delta:
                chunk = {
                    "id": chat_id, "object": "chat.completion.chunk",
                    "created": created, "model": "claude-code",
                    "choices": [{"index": 0, "delta": {"content": text_delta}, "finish_reason": None}],
                }
                yield f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n"

    except asyncio.CancelledError:
        proc.kill()
        raise

    # 发结束信号
    stop_chunk = {
        "id": chat_id, "object": "chat.completion.chunk",
        "created": created, "model": "claude-code",
        "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
    }
    yield f"data: {json.dumps(stop_chunk)}\n\n"
    yield "data: [DONE]\n\n"

    await proc.wait()


def verify_key(request: Request):
    """简单的 API Key 校验"""
    auth = request.headers.get("Authorization", "")
    key = auth.removeprefix("Bearer ").strip()
    if key != SECRET:
        raise HTTPException(status_code=401, detail="API Key 不对")


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    verify_key(request)

    body = await request.json()
    messages = body.get("messages", [])
    stream = body.get("stream", False)

    if not messages:
        raise HTTPException(status_code=400, detail="messages 不能为空")

    system_prompt, user_prompt = format_messages_for_claude(messages)

    if not user_prompt.strip():
        raise HTTPException(status_code=400, detail="没有用户消息")

    if stream:
        return StreamingResponse(
            call_claude_stream(system_prompt, user_prompt),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "X-Accel-Buffering": "no",
            },
        )
    else:
        text = await call_claude(system_prompt, user_prompt)
        chat_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
        return JSONResponse({
            "id": chat_id,
            "object": "chat.completion",
            "created": int(time.time()),
            "model": "claude-code",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": "stop",
            }],
            "usage": {
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
            },
        })


@app.get("/health")
async def health():
    return {"status": "ok", "claude": CLAUDE_CMD}


# ── 启动 ──────────────────────────────────────────────

def main():
    ip = get_local_ip()
    print(f"""
┌──────────────────────────────────────────────┐
│  🦀 keke-relay 启动了                         │
│                                              │
│  局域网地址：http://{ip}:{PORT}            │
│  本机地址：  http://127.0.0.1:{PORT}           │
│                                              │
│  克克 App 设置：                              │
│    自定义提供方 Base URL:                      │
│    http://{ip}:{PORT}/v1/chat/completions │
│    API Key: {SECRET}                           │
│    模型：随便填                                │
│                                              │
│  Ctrl+C 停止                                 │
└──────────────────────────────────────────────┘
""")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")


if __name__ == "__main__":
    main()
