"""
Text chunking strategies for RAG.

Interview key points:
  - Why chunk? LLMs have context limits; embeddings work better on focused text.
  - Fixed-size: simple but may cut mid-sentence.
  - Semantic: respects sentence/paragraph boundaries → better retrieval quality.
  - Overlap: prevents losing context at chunk boundaries.
"""


def chunk_fixed(text: str, chunk_size: int = 500, overlap: int = 100) -> list[str]:
    """Fixed-size chunking with overlap.

    Splits text into chunks of roughly `chunk_size` characters,
    with `overlap` characters shared between consecutive chunks.
    """
    if len(text) <= chunk_size:
        return [text]
    chunks = []
    start = 0
    while start < len(text):
        end = start + chunk_size
        chunks.append(text[start:end])
        start = end - overlap
    return chunks


def chunk_semantic(text: str, max_chunk_size: int = 800) -> list[str]:
    """Semantic chunking — split on paragraph/sentence boundaries.

    Respects natural text structure:
      1. Split by double-newline (paragraphs)
      2. If a paragraph exceeds max_chunk_size, split by sentences
      3. Merge small consecutive chunks to avoid tiny fragments
    """
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]

    raw_chunks: list[str] = []
    for para in paragraphs:
        if len(para) <= max_chunk_size:
            raw_chunks.append(para)
        else:
            sentences = _split_sentences(para)
            buf = ""
            for s in sentences:
                if buf and len(buf) + len(s) > max_chunk_size:
                    raw_chunks.append(buf.strip())
                    buf = ""
                buf += s + " "
            if buf.strip():
                raw_chunks.append(buf.strip())

    return _merge_small_chunks(raw_chunks, max_chunk_size)


def _split_sentences(text: str) -> list[str]:
    """Split text into sentences (handles Chinese and English punctuation)."""
    import re
    parts = re.split(r'(?<=[.!?。！？\n])\s*', text)
    return [p for p in parts if p.strip()]


def _merge_small_chunks(chunks: list[str], max_size: int, min_size: int = 100) -> list[str]:
    """Merge chunks smaller than min_size with their neighbor."""
    if not chunks:
        return []
    merged = [chunks[0]]
    for chunk in chunks[1:]:
        if len(merged[-1]) < min_size and len(merged[-1]) + len(chunk) <= max_size:
            merged[-1] += "\n\n" + chunk
        else:
            merged.append(chunk)
    return merged


def chunk_conversation(messages: list[dict], turns_per_chunk: int = 6) -> list[str]:
    """Chunk a conversation history into digestible segments.

    Groups consecutive message turns together so each chunk has
    full context of a mini-conversation.
    """
    chunks = []
    for i in range(0, len(messages), turns_per_chunk):
        group = messages[i:i + turns_per_chunk]
        text = "\n".join(
            f"{'用户' if m['role'] == 'user' else '克克'}: {m['content']}"
            for m in group
            if isinstance(m["content"], str)
        )
        if text.strip():
            chunks.append(text)
    return chunks
