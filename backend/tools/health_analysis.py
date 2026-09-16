"""Health data analysis tool — analyzes health metrics sent from iOS."""

from tools.base import Tool


class HealthAnalysisTool(Tool):
    name = "analyze_health"
    description = (
        "Analyze health data (steps, sleep, heart rate, etc.) and provide insights. "
        "Use this when the user shares health metrics or asks about their health trends."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "data_type": {
                "type": "string",
                "enum": ["steps", "sleep", "heart_rate", "general"],
                "description": "Type of health data to analyze",
            },
            "values": {
                "type": "string",
                "description": "The health data values as a descriptive string",
            },
        },
        "required": ["data_type", "values"],
    }

    _GUIDELINES = {
        "steps": "WHO recommends 8000-10000 steps/day. <5000 is sedentary.",
        "sleep": "Adults need 7-9 hours. Deep sleep should be 15-20% of total.",
        "heart_rate": "Normal resting HR: 60-100 bpm. Athletes may be 40-60.",
        "general": "Look for trends and anomalies across all metrics.",
    }

    def run(self, *, data_type: str, values: str) -> str:
        guideline = self._GUIDELINES.get(data_type, self._GUIDELINES["general"])
        return (
            f"Health data ({data_type}): {values}\n"
            f"Reference: {guideline}\n"
            "Please provide a caring, non-medical analysis based on this data."
        )
