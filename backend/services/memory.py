"""
RAG-based long-term memory service.

Pipeline:
  1. Store: text → embedding → ChromaDB
  2. Retrieve: query → embedding → vector similarity search → top-k results
"""

import time
import uuid

import chromadb
from chromadb.config import Settings as ChromaSettings

from config import settings


class MemoryService:
    def __init__(self) -> None:
        self._client = chromadb.PersistentClient(
            path=settings.chroma_persist_dir,
            settings=ChromaSettings(anonymized_telemetry=False),
        )

    def _get_collection(self, user_id: str) -> chromadb.Collection:
        return self._client.get_or_create_collection(
            name=f"memory_{user_id}",
            metadata={"hnsw:space": "cosine"},
        )

    # ── Store ─────────────────────────────────────────────
    def add(self, user_id: str, content: str, metadata: dict | None = None) -> str:
        """Chunk text and store embeddings in ChromaDB.

        ChromaDB's default embedding function (all-MiniLM-L6-v2) handles
        the text → vector conversion automatically.
        """
        collection = self._get_collection(user_id)
        doc_id = str(uuid.uuid4())
        doc_metadata = {
            "timestamp": time.time(),
            "source": "conversation",
            **(metadata or {}),
        }
        collection.add(
            ids=[doc_id],
            documents=[content],
            metadatas=[doc_metadata],
        )
        return doc_id

    # ── Retrieve ──────────────────────────────────────────
    def search(self, user_id: str, query: str, top_k: int = 5) -> list[dict]:
        """Semantic search: query → embedding → cosine similarity → top-k."""
        collection = self._get_collection(user_id)
        if collection.count() == 0:
            return []
        results = collection.query(
            query_texts=[query],
            n_results=min(top_k, collection.count()),
        )
        memories = []
        for i, doc in enumerate(results["documents"][0]):
            memories.append({
                "content": doc,
                "distance": results["distances"][0][i],
                "metadata": results["metadatas"][0][i],
            })
        return memories

    def list_all(self, user_id: str) -> list[dict]:
        collection = self._get_collection(user_id)
        results = collection.get()
        return [
            {"id": results["ids"][i], "content": results["documents"][i],
             "metadata": results["metadatas"][i]}
            for i in range(len(results["ids"]))
        ]

    def delete(self, user_id: str, memory_id: str) -> None:
        collection = self._get_collection(user_id)
        collection.delete(ids=[memory_id])


memory_service = MemoryService()
