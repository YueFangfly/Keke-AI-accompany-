"""Tests for FastAPI endpoints (no Claude API key needed)."""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_memory_crud():
    r = client.post("/memory/add", json={
        "user_id": "api_test",
        "content": "test memory entry",
    })
    assert r.status_code == 200
    assert r.json()["status"] == "saved"

    r = client.post("/memory/search", json={
        "user_id": "api_test",
        "query": "test memory",
    })
    assert r.status_code == 200
    assert len(r.json()["results"]) > 0

    r = client.get("/memory/list?user_id=api_test")
    assert r.status_code == 200
    assert len(r.json()["memories"]) > 0
