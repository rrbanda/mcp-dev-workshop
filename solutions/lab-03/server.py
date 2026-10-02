"""Stock Market MCP Server — workshop reference implementation.

Provides comprehensive financial data tools for AI agents.
Built with MCP Python SDK v2 and yfinance.
No API key required — uses public Yahoo Finance data.
"""
import json
import re
from enum import Enum

import pandas as pd
import yfinance as yf
from mcp.server import MCPServer


class FinancialType(str, Enum):
    income_stmt = "income_stmt"
    quarterly_income_stmt = "quarterly_income_stmt"
    balance_sheet = "balance_sheet"
    quarterly_balance_sheet = "quarterly_balance_sheet"
    cashflow = "cashflow"
    quarterly_cashflow = "quarterly_cashflow"


class HolderType(str, Enum):
    major_holders = "major_holders"
    institutional_holders = "institutional_holders"
    mutualfund_holders = "mutualfund_holders"
    insider_transactions = "insider_transactions"
    insider_purchases = "insider_purchases"
    insider_roster_holders = "insider_roster_holders"


class RecommendationType(str, Enum):
    recommendations = "recommendations"
    upgrades_downgrades = "upgrades_downgrades"


_CLASS_SHARE_SUFFIXES = {"A", "B"}


def normalize_ticker(ticker: str) -> str:
    """Normalize US class-share tickers to the hyphen form yfinance expects."""
    if not ticker:
        return ticker
    match = re.fullmatch(r"\s*([A-Za-z]{1,6})[./-]([A-Za-z])\s*", ticker)
    if match and match.group(2).upper() in _CLASS_SHARE_SUFFIXES:
        return f"{match.group(1).upper()}-{match.group(2).upper()}"
    return ticker


def _spot_price(company: yf.Ticker) -> float | None:
    """Resolve current underlying price, or None when unavailable."""
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
    """Restrict chain to strikes within ±strike_window_pct of spot."""
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
    """Restrict chain to requested fields. All-or-nothing: if any field is
    unrecognized, returns full chain unchanged."""
    if not fields:
        return chain
    available = set(chain.columns)
    if any(field not in available for field in fields):
        return chain
    keep = [col for col in chain.columns if col in set(fields)]
    if "strike" in chain.columns and "strike" not in keep:
        keep.insert(0, "strike")
    return chain[keep]


server = MCPServer(
    "stock-market",
    instructions="""
# Stock Market MCP Server

This server provides comprehensive financial data for stocks.

Available tools:
- get_historical_stock_prices: Get historical OHLCV data with customizable period and interval.
- get_stock_info: Get comprehensive stock data including price, metrics, and company details.
- get_stock_news: Get latest news articles for a stock.
- get_stock_actions: Get stock dividends and stock splits history.
- get_financial_statement: Get income statement, balance sheet, or cash flow (annual/quarterly).
- get_holder_info: Get major holders, institutional holders, mutual funds, or insider data.
- get_option_expiration_dates: Get available options expiration dates.
- get_option_chain: Get options chain with optional strike window and field projection.
- get_recommendations: Get analyst recommendations or upgrades/downgrades history.
""",
)


@server.tool(
    name="get_historical_stock_prices",
    description="Get historical stock prices (OHLCV) for a given ticker symbol.",
)
async def get_historical_stock_prices(
    ticker: str, period: str = "1mo", interval: str = "1d"
) -> str:
    """Get historical stock prices for a given ticker symbol."""
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        hist_data = company.history(period=period, interval=interval)
        hist_data = hist_data.reset_index(names="Date")
        return hist_data.to_json(orient="records", date_format="iso")
    except Exception as e:
        print(f"Error: getting historical stock prices for {ticker}: {e}")
        return f"Error: getting historical stock prices for {ticker}: {e}"


@server.tool(
    name="get_stock_info",
    description="Get comprehensive stock information including price, metrics, and company details.",
)
async def get_stock_info(ticker: str) -> str:
    """Get stock information for a given ticker symbol."""
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        info = company.info
        if not info or "symbol" not in info or "quoteType" not in info:
            return f"No stock info found for ticker {ticker}."
        return json.dumps(info)
    except Exception as e:
        print(f"Error: getting stock information for {ticker}: {e}")
        return f"Error: getting stock information for {ticker}: {e}"


@server.tool(
    name="get_stock_news",
    description="Get latest news articles for a stock.",
)
async def get_stock_news(ticker: str) -> str:
    """Get news for a given ticker symbol."""
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
        print(f"Error: getting news for {ticker}: {e}")
        return f"Error: getting news for {ticker}: {e}"


@server.tool(
    name="get_stock_actions",
    description="Get stock dividends and stock splits history.",
)
async def get_stock_actions(ticker: str) -> str:
    """Get stock dividends and stock splits for a given ticker symbol."""
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        actions_df = company.actions
        actions_df = actions_df.reset_index(names="Date")
        return actions_df.to_json(orient="records", date_format="iso")
    except Exception as e:
        print(f"Error: getting stock actions for {ticker}: {e}")
        return f"Error: getting stock actions for {ticker}: {e}"


@server.tool(
    name="get_financial_statement",
    description="Get financial statement: income_stmt, quarterly_income_stmt, balance_sheet, quarterly_balance_sheet, cashflow, quarterly_cashflow.",
)
async def get_financial_statement(ticker: str, financial_type: str) -> str:
    """Get financial statement for a given ticker symbol."""
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
        print(f"Error: getting financial statement for {ticker}: {e}")
        return f"Error: getting financial statement for {ticker}: {e}"


@server.tool(
    name="get_holder_info",
    description="Get holder info: major_holders, institutional_holders, mutualfund_holders, insider_transactions, insider_purchases, insider_roster_holders.",
)
async def get_holder_info(ticker: str, holder_type: str) -> str:
    """Get holder information for a given ticker symbol."""
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
        print(f"Error: getting holder info for {ticker}: {e}")
        return f"Error: getting holder info for {ticker}: {e}"


@server.tool(
    name="get_option_expiration_dates",
    description="Get available options expiration dates for a stock.",
)
async def get_option_expiration_dates(ticker: str) -> str:
    """Fetch available options expiration dates."""
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        options = company.options
        if not options:
            return f"No options expiration dates found for ticker {ticker}."
        return json.dumps(options)
    except Exception as e:
        print(f"Error: getting option expiration dates for {ticker}: {e}")
        return f"Error: getting option expiration dates for {ticker}: {e}"


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
    """Fetch option chain with optional strike window and field projection."""
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
        print(f"Error: getting option chain for {ticker}: {e}")
        return f"Error: getting option chain for {ticker}: {e}"


@server.tool(
    name="get_recommendations",
    description="Get analyst recommendations or upgrades/downgrades. Specify months_back for upgrades/downgrades (default 12).",
)
async def get_recommendations(
    ticker: str, recommendation_type: str, months_back: int = 12
) -> str:
    """Get recommendations or upgrades/downgrades for a given ticker symbol."""
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
        print(f"Error: getting recommendations for {ticker}: {e}")
        return f"Error: getting recommendations for {ticker}: {e}"


def main() -> None:
    import os

    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        server.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        server.run(transport="stdio")


if __name__ == "__main__":
    main()
