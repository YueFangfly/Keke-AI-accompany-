"""Tests for text chunking strategies."""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from services.chunking import chunk_fixed, chunk_semantic, chunk_conversation


def test_fixed_short_text():
    result = chunk_fixed("hello world", chunk_size=500)
    assert result == ["hello world"]


def test_fixed_splits():
    text = "a" * 1000
    chunks = chunk_fixed(text, chunk_size=300, overlap=50)
    assert len(chunks) > 1
    assert all(len(c) <= 300 for c in chunks)


def test_fixed_overlap():
    text = "abcdefghij" * 100
    chunks = chunk_fixed(text, chunk_size=200, overlap=50)
    for i in range(len(chunks) - 1):
        assert chunks[i][-50:] == chunks[i + 1][:50]


def test_semantic_paragraphs():
    text = "First paragraph here.\n\nSecond paragraph here.\n\nThird paragraph here."
    chunks = chunk_semantic(text)
    assert len(chunks) >= 1
    full = " ".join(chunks)
    assert "First" in full
    assert "Third" in full


def test_semantic_long_paragraph():
    text = "This is a sentence. " * 100
    chunks = chunk_semantic(text, max_chunk_size=200)
    assert len(chunks) > 1
    assert all(len(c) <= 800 for c in chunks)


def test_conversation_chunking():
    messages = [
        {"role": "user", "content": f"message {i}"}
        for i in range(12)
    ]
    chunks = chunk_conversation(messages, turns_per_chunk=4)
    assert len(chunks) == 3


def test_conversation_empty():
    assert chunk_conversation([]) == []
