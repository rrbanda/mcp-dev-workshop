---
name: stock-market-mcp-spec
description: Exact specification for a stock market MCP server with 9 tools, 3 enums, 4 helpers. Use when asked to build a stock market MCP server, financial data server, or anything involving stock prices, financial statements, options chains, or analyst recommendations via MCP.
---

# Stock Market MCP Server Specification

Exact specification for a stock market data MCP server. Follow this spec precisely to produce a server with 9 tools, 3 enum types, 4 helper functions, and dual-transport support.

## When to use

Use this skill when asked to build a stock market MCP server, financial data MCP server, or anything involving stock prices, financial statements, options chains, or analyst recommendations via MCP.

## Dependencies

```
mcp[cli]>=2.1.0,<3
yfinance>=1.6.0,<2
```

pandas comes as a transitive dependency of yfinance.

## Server Configuration

```python
from mcp.server import MCPServer

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
```

## Type Definitions

Define exactly these three Enum classes:

```python
from enum import Enum

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
```

## Helper Functions

### 1. normalize_ticker

Converts US class-share tickers from dot/slash to hyphen form (BRK.B → BRK-B). Exchange suffixes (.TO, .L, .HK) are left unchanged.

```python
import re

_CLASS_SHARE_SUFFIXES = {"A", "B"}

def normalize_ticker(ticker: str) -> str:
    if not ticker:
        return ticker
    match = re.fullmatch(r"\s*([A-Za-z]{1,6})[./-]([A-Za-z])\s*", ticker)
    if match and match.group(2).upper() in _CLASS_SHARE_SUFFIXES:
        return f"{match.group(1).upper()}-{match.group(2).upper()}"
    return ticker
```

### 2. _spot_price

Resolves current underlying price. Tries fast_info first, falls back to daily close. Returns None if unavailable.

```python
def _spot_price(company: yf.Ticker) -> float | None:
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
```

### 3. _window_strikes

Restricts option chain to strikes within ±strike_window_pct of spot. Returns full chain when window is None, non-positive, spot unavailable, or result would be empty.

```python
def _window_strikes(company: yf.Ticker, chain: pd.DataFrame, strike_window_pct: float | None) -> pd.DataFrame:
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
```

### 4. _project_fields

Restricts chain to requested columns. Always retains `strike`. All-or-nothing: if ANY requested field doesn't exist, returns full chain unchanged (never silently drops a column).

```python
def _project_fields(chain: pd.DataFrame, fields: list[str] | None) -> pd.DataFrame:
    if not fields:
        return chain
    available = set(chain.columns)
    if any(field not in available for field in fields):
        return chain
    keep = [col for col in chain.columns if col in set(fields)]
    if "strike" in chain.columns and "strike" not in keep:
        keep.insert(0, "strike")
    return chain[keep]
```

## Tool Specifications

All tools are `async def`. All use `@server.tool(name="...", description="...")` pattern. All wrap logic in `try/except Exception` and return error strings on failure.

### Tool 1: get_historical_stock_prices

```python
@server.tool(
    name="get_historical_stock_prices",
    description="Get historical stock prices for a given ticker symbol. Returns Date, Open, High, Low, Close, Volume.",
)
async def get_historical_stock_prices(ticker: str, period: str = "1mo", interval: str = "1d") -> str:
```

**Implementation**: `yf.Ticker(normalize_ticker(ticker)).history(period, interval)` → `.reset_index(names="Date")` → `.to_json(orient="records", date_format="iso")`

### Tool 2: get_stock_info

```python
@server.tool(
    name="get_stock_info",
    description="Get comprehensive stock information including price, metrics, and company details.",
)
async def get_stock_info(ticker: str) -> str:
```

**Implementation**: `yf.Ticker(normalize_ticker(ticker)).info` → validate `symbol` and `quoteType` exist → `json.dumps(info)`

### Tool 3: get_stock_news

```python
@server.tool(
    name="get_stock_news",
    description="Get latest news articles for a stock.",
)
async def get_stock_news(ticker: str) -> str:
```

**Implementation**: `yf.Ticker(normalize_ticker(ticker)).news` → filter for `contentType == "STORY"` → extract title, summary, description, URL → join with `"\n\n"`.

### Tool 4: get_stock_actions

```python
@server.tool(
    name="get_stock_actions",
    description="Get stock dividends and stock splits history.",
)
async def get_stock_actions(ticker: str) -> str:
```

**Implementation**: `yf.Ticker(normalize_ticker(ticker)).actions` → `.reset_index(names="Date")` → `.to_json(orient="records", date_format="iso")`

### Tool 5: get_financial_statement

```python
@server.tool(
    name="get_financial_statement",
    description="Get financial statement (income_stmt, quarterly_income_stmt, balance_sheet, quarterly_balance_sheet, cashflow, quarterly_cashflow).",
)
async def get_financial_statement(ticker: str, financial_type: str) -> str:
```

**Implementation**:
1. Match `financial_type` against FinancialType enum values to select the right property.
2. Check `.empty`.
3. Iterate columns (dates) and rows (metrics) to build per-date JSON records. Handle `pd.isna(value)` → `None`.

### Tool 6: get_holder_info

```python
@server.tool(
    name="get_holder_info",
    description="Get holder information (major_holders, institutional_holders, mutualfund_holders, insider_transactions, insider_purchases, insider_roster_holders).",
)
async def get_holder_info(ticker: str, holder_type: str) -> str:
```

**Implementation**: Match `holder_type` against HolderType enum. For `major_holders`, use `.reset_index(names="metric")`. All use `.to_json(orient="records")`. Most use `date_format="iso"`.

### Tool 7: get_option_expiration_dates

```python
@server.tool(
    name="get_option_expiration_dates",
    description="Get available options expiration dates for a stock.",
)
async def get_option_expiration_dates(ticker: str) -> str:
```

**Implementation**: `yf.Ticker(normalize_ticker(ticker)).options` → check not empty → `json.dumps(options)`

### Tool 8: get_option_chain

```python
@server.tool(
    name="get_option_chain",
    description="Get option chain for a ticker, expiration date, and type (calls/puts). Use strike_window_pct and fields to reduce payload size.",
)
async def get_option_chain(
    ticker: str,
    expiration_date: str,
    option_type: str,
    strike_window_pct: float | None = None,
    fields: list[str] | None = None,
) -> str:
```

**Implementation**:
1. Validate `expiration_date` is in `company.options`.
2. Validate `option_type` is "calls" or "puts".
3. Get `company.option_chain(expiration_date)`, select `.calls` or `.puts`.
4. Apply `_window_strikes(company, chain, strike_window_pct)`.
5. Apply `_project_fields(chain, fields)`.
6. Return `.to_json(orient="records", date_format="iso")`.

### Tool 9: get_recommendations

```python
@server.tool(
    name="get_recommendations",
    description="Get analyst recommendations or upgrades/downgrades. Specify months_back for upgrades/downgrades (default 12).",
)
async def get_recommendations(ticker: str, recommendation_type: str, months_back: int = 12) -> str:
```

**Implementation**:
- For "recommendations": `company.recommendations` → check `.empty` → `.to_json(orient="records")`.
- For "upgrades_downgrades": `company.upgrades_downgrades` → `.reset_index()` → filter by `GradeDate >= cutoff` → sort descending → `drop_duplicates(subset=["Firm"])` → `.to_json(orient="records", date_format="iso")`.

## Error Handling Pattern

Every tool follows this pattern:

```python
async def tool_name(ticker: str, ...) -> str:
    try:
        company = yf.Ticker(normalize_ticker(ticker))
        # ... implementation ...
        return result
    except Exception as e:
        print(f"Error: getting X for {ticker}: {e}")
        return f"Error: getting X for {ticker}: {e}"
```

## Entry Point

Support both stdio (local dev) and streamable-http (deployment):

```python
def main() -> None:
    import os
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        server.run(transport="streamable-http", host="0.0.0.0", port=8080)
    else:
        server.run(transport="stdio")

if __name__ == "__main__":
    main()
```

## Containerfile

```dockerfile
FROM registry.access.redhat.com/ubi9/python-312:latest
WORKDIR /opt/app-root/src
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY server.py .
ENV MCP_TRANSPORT=streamable-http
EXPOSE 8080
CMD ["python", "server.py"]
```

## Deployment (OpenShift)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stock-market-mcp
  labels:
    app: stock-market-mcp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stock-market-mcp
  template:
    metadata:
      labels:
        app: stock-market-mcp
    spec:
      containers:
        - name: server
          image: image-registry.openshift-image-registry.svc:5000/MY_NAMESPACE/stock-market-mcp:latest
          ports:
            - containerPort: 8080
          env:
            - name: MCP_TRANSPORT
              value: "streamable-http"
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "200m"
            limits:
              memory: "512Mi"
              cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: stock-market-mcp
spec:
  selector:
    app: stock-market-mcp
  ports:
    - port: 8080
      targetPort: 8080
```
