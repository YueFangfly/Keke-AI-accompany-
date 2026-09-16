"""Weather tool — free API, no key required."""

import httpx

from tools.base import Tool


class WeatherTool(Tool):
    name = "get_weather"
    description = (
        "Get current weather and forecast for a city. "
        "Use this when the user asks about weather or when you want to "
        "suggest outdoor activities based on conditions."
    )
    input_schema = {
        "type": "object",
        "properties": {
            "city": {
                "type": "string",
                "description": "City name, e.g. 'Hangzhou' or '杭州'",
            },
        },
        "required": ["city"],
    }

    def run(self, *, city: str) -> str:
        try:
            geo = httpx.get(
                "https://geocoding-api.open-meteo.com/v1/search",
                params={"name": city, "count": 1},
                timeout=10,
            )
            geo.raise_for_status()
            results = geo.json().get("results")
            if not results:
                return f"City not found: {city}"
            lat, lon = results[0]["latitude"], results[0]["longitude"]
            name = results[0].get("name", city)

            weather = httpx.get(
                "https://api.open-meteo.com/v1/forecast",
                params={
                    "latitude": lat,
                    "longitude": lon,
                    "current": "temperature_2m,weather_code,wind_speed_10m,relative_humidity_2m",
                    "daily": "temperature_2m_max,temperature_2m_min,weather_code",
                    "timezone": "Asia/Shanghai",
                    "forecast_days": 3,
                },
                timeout=10,
            )
            weather.raise_for_status()
            data = weather.json()
            cur = data["current"]

            code_map = {
                0: "晴", 1: "大部晴", 2: "多云", 3: "阴",
                45: "雾", 48: "雾凇", 51: "小毛毛雨", 53: "毛毛雨",
                55: "大毛毛雨", 61: "小雨", 63: "中雨", 65: "大雨",
                71: "小雪", 73: "中雪", 75: "大雪", 80: "阵雨",
                95: "雷暴", 96: "雷暴+冰雹",
            }
            desc = code_map.get(cur["weather_code"], f"代码{cur['weather_code']}")

            lines = [
                f"{name} 现在: {desc}, {cur['temperature_2m']}°C, "
                f"湿度{cur['relative_humidity_2m']}%, 风速{cur['wind_speed_10m']}km/h",
            ]
            daily = data["daily"]
            for i in range(min(3, len(daily["time"]))):
                d_desc = code_map.get(daily["weather_code"][i], "?")
                lines.append(
                    f"  {daily['time'][i]}: {d_desc}, "
                    f"{daily['temperature_2m_min'][i]}~{daily['temperature_2m_max'][i]}°C"
                )
            return "\n".join(lines)
        except Exception as e:
            return f"Weather lookup failed: {e}"
