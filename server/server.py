"""Stock Market MCP Server — workshop reference implementation.

═══════════════════════════════════════════════════════════════════════
WHAT IS THIS?
═══════════════════════════════════════════════════════════════════════
This is a complete MCP (Model Context Protocol) server that provides
financial data tools to AI agents. MCP is an open protocol — like
USB for AI — that lets any AI host (OpenCode, Cursor, Claude, etc.)
discover and call tools defined here.

HOW IT WORKS:
  1. You deploy this server on OpenShift (as a container)
  2. An AI agent connects and calls tools/list to discover what's available
  3. The agent reads each tool's name, description, and parameter types
  4. When a user asks "What's Apple's stock price?", the agent calls
     get_stock_info(ticker="AAPL") on this server
  5. This server fetches live data from Yahoo Finance and returns it

KEY CONCEPTS:
  - @server.tool() — decorator that registers a function as an MCP tool.
    The function name, docstring, and type hints become the tool's schema
    that the LLM reads when deciding which tool to call.
  - Type hints matter — they become JSON Schema so the LLM knows what
    arguments to pass (str, int, float, Enum for constrained choices).
  - Streamable HTTP transport — the server listens on port 8080 at /mcp
    for JSON-RPC 2.0 requests over HTTP with Server-Sent Events (SSE).
  - Error handling — every tool returns a string (success or error).
    Never raise exceptions — the MCP client expects text responses.

TOOLS PROVIDED (9 total):
  1. get_historical_stock_prices — OHLCV data with configurable period
  2. get_stock_info — comprehensive company data (price, metrics, profile)
  3. get_stock_news — recent news articles
  4. get_stock_actions — dividends and splits history
  5. get_financial_statement — income/balance/cashflow (annual or quarterly)
  6. get_holder_info — institutional, insider, major holders
  7. get_option_expiration_dates — available option dates
  8. get_option_chain — calls/puts with strike filtering
  9. get_recommendations — analyst recommendations and upgrades

DATA SOURCE:
  Yahoo Finance via the yfinance library. No API key required.
  Data updates during market hours (NYSE: 9:30-16:00 ET, M-F).

═══════════════════════════════════════════════════════════════════════
"""

import json
import os
import re
from enum import Enum

import pandas as pd
import yfinance as yf
from mcp.server import MCPServer


# ═══════════════════════════════════════════════════════════════════════
# ENUMS — constrained parameter types
# ═══════════════════════════════════════════════════════════════════════
# When a tool parameter is an Enum, the MCP SDK generates a JSON Schema
# "enum" field. The LLM sees the allowed values and picks one.
# This prevents invalid inputs like "quarterly_magic_sheet".

class FinancialType(str, Enum):
    """Types of financial statements available from Yahoo Finance."""
    income_stmt = "income_stmt"
    quarterly_income_stmt = "quarterly_income_stmt"
    balance_sheet = "balance_sheet"
    quarterly_balance_sheet = "quarterly_balance_sheet"
    cashflow = "cashflow"
    quarterly_cashflow = "quarterly_cashflow"


class HolderType(str, Enum):
    """Types of shareholder/insider data available."""
    major_holders = "major_holders"
    institutional_holders = "institutional_holders"
    mutualfund_holders = "mutualfund_holders"
    insider_transactions = "insider_transactions"
    insider_purchases = "insider_purchases"
    insider_roster_holders = "insider_roster_holders"


class RecommendationType(str, Enum):
    """Types of analyst recommendation data."""
    recommendations = "recommendations"
    upgrades_downgrades = "upgrades_downgrades"


# ═══════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS — shared logic used by multiple tools
# ═══════════════════════════════════════════════════════════════════════

_CLASS_SHARE_SUFFIXES = {"A", "B"}


def normalize_ticker(ticker: str) -> str:
    """Normalize US class-share tickers to the hyphen form yfinance expects.

    Examples: BRK.B -> BRK-B, GOOG/A -> GOOG-A
    Most tickers pass through unchanged.
    """
    if not ticker:
        return ticker
    match = re.fullmatch(r"\s*([A-Za-z]{1,6})[./-]([A-Za-z])\s*", ticker)
    if match and match.group(2).upper() in _CLASS_SHARE_SUFFIXES:
        return f"{match.group(1).upper()}-{match.group(2).upper()}"
    return ticker


def _spot_price(company: yf.Ticker) -> float | None:
    """Resolve current underlying price, or None when unavailable.
    Tries fast_info first (cached), then falls back to 1-day history.
    """
    try:
        price = company.fast_info.get("lastPrice")
        if price is not None and float(price) > 0:
            return float(price)
    except Exception:
        pass
    try:
        hist = company.history(period="1d", interval="1d")
        if hist is not None and not hist.empty and "Close" in hist.columns:
            closes = hist["Close"].dropna()
            if len(closes) > 0 and float(closes.iloc[-1]) > 0:
                return float(closes.iloc[-1])
    except Exception:
        pass
    return None


def _window_strikes(
    company: yf.Ticker, chain: pd.DataFrame, strike_window_pct: float | None
) -> pd.DataFrame:
    """Restrict options chain to strikes within ±strike_window_pct of spot price.
    If windowing fails or is not requested, returns the full chain.
    """
    if strike_window_pct is None or "strike" not in chain.columns:
        return chain
    try:
        window = float(strike_window_pct)
    except (TypeError, ValueError):
        return chain
    if window <= 0:
        return chain
    spot = _spot_price(company)
    if spot is None:
        return chain
    windowed = chain[
        (chain["strike"] >= spot * (1 - window))
        & (chain["strike"] <= spot * (1 + window))
    ]
    return windowed if not windowed.empty else chain


def _project_fields(chain: pd.DataFrame, fields: list[str] | None) -> pd.DataFrame:
    """Restrict chain to requested columns. If any field is unrecognized,
    returns the full chain unchanged (fail-safe).
    """
    if not fields:
        return chain
    available = set(chain.columns)
    if any(field not in available for field in fields):
        return chain
    keep = [col for col in chain.columns if col in set(fields)]
    if "strike" in chain.columns and "strike" not in keep:
        keep.insert(0, "strike")
    return chain[keep]


# ═══════════════════════════════════════════════════════════════════════
# MCP SERVER INSTANCE
# ═══════════════════════════════════════════════════════════════════════
# This creates the server object. The "instructions" field is optional
# metadata that some MCP clients display — it's NOT what the LLM reads
# for tool selection (that comes from each tool's description).

server = MCPServer(
    "stock-market",
    instructions="""
# Stock Market MCP Server

Provides comprehensive financial data for stocks via Yahoo Finance.
9 tools covering prices, news, financials, options, and analyst data.
""",
)


# ═══════════════════════════════════════════════════════════════════════
# TOOL 1: get_historical_stock_prices
# ═══════════════════════════════════════════════════════════════════════
# The @server.tool() decorator registers this function as an MCP tool.
# - name: what the LLM sees when picking a tool
# - description: the LLM reads this to decide when to use the tool
# - Function parameters (ticker, period, interval) become the tool's
#   input schema. Type hints -> JSON Schema types. Defaults are optional.

@server.tool(
    name="get_historical_stock_prices",
    description="Get historical stock prices (OHLCV) for a given ticker symbol.",
)
async def get_historical_stock_prices(
    ticker: str, period: str = "1mo", interval: str = "1d"
) -> str:
    """Get historical stock prices for a given ticker symbol.

    Args:
        ticker: Stock ticker symbol (e.g., AAPL, MSFT)
        period: Data period — 1d, 5d, 1mo, 3mo, 6mo, 1y, 2y, 5y, 10y, ytd, max
        interval: Data interval — 1m, 2m, 5m, 15m, 30m, 60m, 90m, 1h, 1d, 5d, 1wk, 1mo, 3mo
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        hist_data = company.history(period=period, interval=interval)
        hist_data = hist_data.reset_index(names="Date")
        return hist_data.to_json(orient="records", date_format="iso")
    except Exception as e:
        return f"Error: getting historical stock prices for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 2: get_stock_info
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_stock_info",
    description="Get comprehensive stock information including price, metrics, and company details.",
)
async def get_stock_info(ticker: str) -> str:
    """Get stock information for a given ticker symbol.

    Returns a JSON object with current price, P/E ratio, market cap,
    52-week range, sector, industry, company description, and more.
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        info = company.info
        if not info or "symbol" not in info or "quoteType" not in info:
            return f"No stock info found for ticker {ticker}."
        return json.dumps(info)
    except Exception as e:
        return f"Error: getting stock information for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 3: get_stock_news
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_stock_news",
    description="Get latest news articles for a stock.",
)
async def get_stock_news(ticker: str) -> str:
    """Get news for a given ticker symbol.

    Returns titles, summaries, and URLs from Yahoo Finance news feed.
    Filters to STORY content type (excludes ads and video-only).
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        news_data = company.news
        if not news_data:
            return f"No news found for ticker {ticker}."
        news_list = []
        for news in news_data:
            if news.get("content", {}).get("contentType", "") == "STORY":
                title = news.get("content", {}).get("title", "")
                summary = news.get("content", {}).get("summary", "")
                description = news.get("content", {}).get("description", "")
                url = news.get("content", {}).get("canonicalUrl", {}).get("url", "")
                news_list.append(
                    f"Title: {title}\nSummary: {summary}\nDescription: {description}\nURL: {url}"
                )
        if not news_list:
            return f"No news found for ticker {ticker}."
        return "\n\n".join(news_list)
    except Exception as e:
        return f"Error: getting news for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 4: get_stock_actions
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_stock_actions",
    description="Get stock dividends and stock splits history.",
)
async def get_stock_actions(ticker: str) -> str:
    """Get stock dividends and stock splits for a given ticker symbol.

    Returns dates and amounts for all recorded dividends and splits.
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        actions_df = company.actions
        actions_df = actions_df.reset_index(names="Date")
        return actions_df.to_json(orient="records", date_format="iso")
    except Exception as e:
        return f"Error: getting stock actions for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 5: get_financial_statement
# ═══════════════════════════════════════════════════════════════════════
# This tool uses an Enum parameter (FinancialType) to constrain the
# financial_type input. The LLM sees the allowed values in the schema.

@server.tool(
    name="get_financial_statement",
    description="Get financial statement: income_stmt, quarterly_income_stmt, balance_sheet, quarterly_balance_sheet, cashflow, quarterly_cashflow.",
)
async def get_financial_statement(ticker: str, financial_type: str) -> str:
    """Get financial statement for a given ticker symbol.

    Args:
        ticker: Stock ticker symbol
        financial_type: One of the FinancialType enum values
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        if financial_type == FinancialType.income_stmt:
            statement = company.income_stmt
        elif financial_type == FinancialType.quarterly_income_stmt:
            statement = company.quarterly_income_stmt
        elif financial_type == FinancialType.balance_sheet:
            statement = company.balance_sheet
        elif financial_type == FinancialType.quarterly_balance_sheet:
            statement = company.quarterly_balance_sheet
        elif financial_type == FinancialType.cashflow:
            statement = company.cashflow
        elif financial_type == FinancialType.quarterly_cashflow:
            statement = company.quarterly_cashflow
        else:
            return (
                f"Error: invalid financial type {financial_type}. "
                f"Please use one of: {', '.join(e.value for e in FinancialType)}."
            )
        if statement.empty:
            return f"No financial statement data found for ticker {ticker}."
        result = []
        for column in statement.columns:
            date_str = (
                column.strftime("%Y-%m-%d")
                if isinstance(column, pd.Timestamp)
                else str(column)
            )
            date_obj = {"date": date_str}
            for index, value in statement[column].items():
                date_obj[index] = None if pd.isna(value) else value
            result.append(date_obj)
        return json.dumps(result)
    except Exception as e:
        return f"Error: getting financial statement for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 6: get_holder_info
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_holder_info",
    description="Get holder info: major_holders, institutional_holders, mutualfund_holders, insider_transactions, insider_purchases, insider_roster_holders.",
)
async def get_holder_info(ticker: str, holder_type: str) -> str:
    """Get holder information for a given ticker symbol.

    Args:
        ticker: Stock ticker symbol
        holder_type: One of the HolderType enum values
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        if holder_type == HolderType.major_holders:
            return company.major_holders.reset_index(names="metric").to_json(orient="records")
        elif holder_type == HolderType.institutional_holders:
            return company.institutional_holders.to_json(orient="records")
        elif holder_type == HolderType.mutualfund_holders:
            return company.mutualfund_holders.to_json(orient="records", date_format="iso")
        elif holder_type == HolderType.insider_transactions:
            return company.insider_transactions.to_json(orient="records", date_format="iso")
        elif holder_type == HolderType.insider_purchases:
            return company.insider_purchases.to_json(orient="records", date_format="iso")
        elif holder_type == HolderType.insider_roster_holders:
            return company.insider_roster_holders.to_json(orient="records", date_format="iso")
        else:
            return (
                f"Error: invalid holder type {holder_type}. "
                f"Please use one of: {', '.join(e.value for e in HolderType)}."
            )
    except Exception as e:
        return f"Error: getting holder info for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 7: get_option_expiration_dates
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_option_expiration_dates",
    description="Get available options expiration dates for a stock.",
)
async def get_option_expiration_dates(ticker: str) -> str:
    """Fetch available options expiration dates.

    Use this before get_option_chain to pick a valid expiration date.
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        options = company.options
        if not options:
            return f"No options expiration dates found for ticker {ticker}."
        return json.dumps(options)
    except Exception as e:
        return f"Error: getting option expiration dates for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 8: get_option_chain
# ═══════════════════════════════════════════════════════════════════════
# This is the most complex tool — it shows optional parameters, list types,
# and helper function composition. The LLM learns from the description
# that it should call get_option_expiration_dates first to get valid dates.

@server.tool(
    name="get_option_chain",
    description="Get option chain for a ticker, expiration date, and type (calls/puts). Use strike_window_pct to filter strikes near spot. Use fields to select columns.",
)
async def get_option_chain(
    ticker: str,
    expiration_date: str,
    option_type: str,
    strike_window_pct: float | None = None,
    fields: list[str] | None = None,
) -> str:
    """Fetch option chain with optional strike window and field projection.

    Args:
        ticker: Stock ticker symbol
        expiration_date: Must be one of the dates from get_option_expiration_dates
        option_type: "calls" or "puts"
        strike_window_pct: Optional — filter strikes within this % of spot (e.g., 0.1 = ±10%)
        fields: Optional — list of column names to return (e.g., ["strike", "lastPrice", "volume"])
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        if expiration_date not in company.options:
            return f"Error: No options available for the date {expiration_date}. Use get_option_expiration_dates to get valid dates."
        if option_type not in ["calls", "puts"]:
            return "Error: Invalid option type. Please use 'calls' or 'puts'."
        option_chain = company.option_chain(expiration_date)
        chain = option_chain.calls if option_type == "calls" else option_chain.puts
        chain = _window_strikes(company, chain, strike_window_pct)
        chain = _project_fields(chain, fields)
        return chain.to_json(orient="records", date_format="iso")
    except Exception as e:
        return f"Error: getting option chain for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# TOOL 9: get_recommendations
# ═══════════════════════════════════════════════════════════════════════

@server.tool(
    name="get_recommendations",
    description="Get analyst recommendations or upgrades/downgrades. Specify months_back for upgrades/downgrades (default 12).",
)
async def get_recommendations(
    ticker: str, recommendation_type: str, months_back: int = 12
) -> str:
    """Get recommendations or upgrades/downgrades for a given ticker symbol.

    Args:
        ticker: Stock ticker symbol
        recommendation_type: "recommendations" or "upgrades_downgrades"
        months_back: How many months back for upgrades_downgrades (default 12)
    """
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        if recommendation_type == RecommendationType.recommendations:
            recommendations = company.recommendations
            if recommendations.empty:
                return "[]"
            return recommendations.to_json(orient="records")
        elif recommendation_type == RecommendationType.upgrades_downgrades:
            upgrades_downgrades = company.upgrades_downgrades
            if upgrades_downgrades.empty:
                return "[]"
            upgrades_downgrades = upgrades_downgrades.reset_index()
            cutoff_date = pd.Timestamp.now() - pd.DateOffset(months=months_back)
            upgrades_downgrades = upgrades_downgrades[
                upgrades_downgrades["GradeDate"] >= cutoff_date
            ]
            upgrades_downgrades = upgrades_downgrades.sort_values(
                "GradeDate", ascending=False
            )
            latest_by_firm = upgrades_downgrades.drop_duplicates(subset=["Firm"])
            return latest_by_firm.to_json(orient="records", date_format="iso")
        else:
            return (
                f"Error: invalid recommendation type {recommendation_type}. "
                f"Please use one of: {', '.join(e.value for e in RecommendationType)}."
            )
    except Exception as e:
        return f"Error: getting recommendations for {ticker}: {e}"


# ═══════════════════════════════════════════════════════════════════════
# SERVER STARTUP
# ═══════════════════════════════════════════════════════════════════════
# Streamable HTTP transport: the server listens on 0.0.0.0:8080 so it's
# reachable from outside the container. The MCP Lifecycle Operator will
# connect to port 8080 at /mcp to perform a handshake (initialize call)
# that verifies this is a real MCP server before marking it Ready.

def main() -> None:
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        server.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        server.run(transport="stdio")


if __name__ == "__main__":
    main()
