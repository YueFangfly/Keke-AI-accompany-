"""Tests for Agent tools."""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from tools.calculator import CalculatorTool
from tools.datetime_tool import DateTimeTool


def test_calculator_basic():
    calc = CalculatorTool()
    assert "6" in calc.run(expression="2 + 4")
    assert "15" in calc.run(expression="3 * 5")
    assert "2" in calc.run(expression="10 / 5")


def test_calculator_complex():
    calc = CalculatorTool()
    result = calc.run(expression="(3 + 5) * 2")
    assert "16" in result


def test_calculator_power():
    calc = CalculatorTool()
    assert "8" in calc.run(expression="2 ** 3")


def test_calculator_invalid():
    calc = CalculatorTool()
    result = calc.run(expression="import os")
    assert "Cannot evaluate" in result


def test_datetime():
    dt = DateTimeTool()
    result = dt.run()
    assert "CST" in result
    assert "202" in result


def test_tool_schema():
    calc = CalculatorTool()
    schema = calc.to_claude_tool()
    assert schema["name"] == "calculator"
    assert "description" in schema
    assert "input_schema" in schema


def test_all_tools_have_schema():
    from tools.web_search import WebSearchTool
    from tools.weather import WeatherTool
    from tools.health_analysis import HealthAnalysisTool

    for cls in [WebSearchTool, WeatherTool, HealthAnalysisTool, CalculatorTool, DateTimeTool]:
        tool = cls()
        schema = tool.to_claude_tool()
        assert "name" in schema
        assert "description" in schema
        assert "input_schema" in schema
