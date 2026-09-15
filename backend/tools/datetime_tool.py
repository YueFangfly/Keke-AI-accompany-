"""Date/time tool — lets the Agent know the current time."""

from datetime import datetime, timezone, timedelta

from tools.base import Tool

_CST = timezone(timedelta(hours=8))


class DateTimeTool(Tool):
    name = "get_current_time"
    description = "Get the current date and time in China Standard Time (CST)."
    input_schema = {
        "type": "object",
        "properties": {},
    }

    def run(self) -> str:
        now = datetime.now(_CST)
        return now.strftime("%Y-%m-%d %H:%M:%S CST (weekday: %A)")
