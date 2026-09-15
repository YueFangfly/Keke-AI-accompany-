"""Web search tool — lets the Agent look things up online."""

import httpx

from tools.base import Tool


class WebSearchTool(Tool):
    name = "web_search"
    description = (
        "Search the web for current information. "
        "Use this when the user asks about recent events, facts you're unsure about, "
        "or anything that requires up-to-date information."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "The search query",
            },
        },
        "required": ["query"],
    }

    def run(self, *, query: str) -> str:
        try:
            resp = httpx.get(
                "https://html.duckduckgo.com/html/",
                params={"q": query},
                headers={"User-Agent": "KeKeBot/1.0"},
                timeout=10,
            )
            resp.raise_for_status()
            from html.parser import HTMLParser

            results: list[str] = []

            class _Parser(HTMLParser):
                _in_result = False
                _buf = ""

                def handle_starttag(self, tag: str, attrs: list) -> None:
                    cls = dict(attrs).get("class", "")
                    if tag == "a" and "result__a" in cls:
                        self._in_result = True
                        self._buf = ""

                def handle_data(self, data: str) -> None:
                    if self._in_result:
                        self._buf += data

                def handle_endtag(self, tag: str) -> None:
                    if tag == "a" and self._in_result:
                        self._in_result = False
                        if self._buf.strip():
                            results.append(self._buf.strip())

            _Parser().feed(resp.text)
            if not results:
                return f"No results found for: {query}"
            return "Search results:\n" + "\n".join(
                f"- {r}" for r in results[:5]
            )
        except Exception as e:
            return f"Search failed: {e}"
