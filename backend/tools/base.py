"""Base class for Agent tools.

Every tool exposes:
  - name / description (for the LLM to know what it does)
  - input_schema (JSON Schema so the LLM knows what arguments to pass)
  - run() (actually executes the tool and returns a result string)
"""

from abc import ABC, abstractmethod
from typing import Any


class Tool(ABC):
    name: str
    description: str
    input_schema: dict

    @abstractmethod
    def run(self, **kwargs: Any) -> str:
        """Execute the tool and return a human-readable result."""
        ...

    def to_claude_tool(self) -> dict:
        """Convert to Claude API tool format."""
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.input_schema,
        }
