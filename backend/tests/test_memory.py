"""Tests for the RAG memory service."""

import sys
import os
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ["CHROMA_PERSIST_DIR"] = tempfile.mkdtemp()

from services.memory import MemoryService


def _fresh_service() -> MemoryService:
    svc = MemoryService()
    svc._client = __import__("chromadb").PersistentClient(
        path=tempfile.mkdtemp(),
        settings=__import__("chromadb").config.Settings(anonymized_telemetry=False),
    )
    return svc


def test_add_and_search():
    svc = _fresh_service()
    svc.add("test", "I love matcha latte")
    svc.add("test", "My birthday is March 15")
    svc.add("test", "I'm looking for AI jobs in Hangzhou")

    results = svc.search("test", "what drink do you like")
    assert len(results) > 0
    assert "matcha" in results[0]["content"].lower()


def test_search_empty():
    svc = _fresh_service()
    results = svc.search("nobody", "anything")
    assert results == []


def test_list_all():
    svc = _fresh_service()
    svc.add("test2", "fact one")
    svc.add("test2", "fact two")
    all_memories = svc.list_all("test2")
    assert len(all_memories) == 2


def test_delete():
    svc = _fresh_service()
    doc_id = svc.add("test3", "temporary memory")
    assert len(svc.list_all("test3")) == 1
    svc.delete("test3", doc_id)
    assert len(svc.list_all("test3")) == 0


def test_add_long_text():
    svc = _fresh_service()
    long_text = "First paragraph about cooking.\n\n" * 20
    ids = svc.add_long_text("test4", long_text)
    assert len(ids) >= 1
    results = svc.search("test4", "cooking")
    assert len(results) > 0


def test_add_conversation():
    svc = _fresh_service()
    messages = [
        {"role": "user", "content": "I got a job offer from Alibaba"},
        {"role": "assistant", "content": "That's amazing!"},
        {"role": "user", "content": "The salary is 25k/month"},
        {"role": "assistant", "content": "That's a great offer for a junior role"},
    ]
    ids = svc.add_conversation("test5", messages)
    assert len(ids) >= 1
    results = svc.search("test5", "job offer salary")
    assert len(results) > 0
    assert "alibaba" in results[0]["content"].lower() or "25k" in results[0]["content"]
