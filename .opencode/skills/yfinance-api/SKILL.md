# yfinance API Reference

Complete reference for the `yfinance` Python library — free financial data from Yahoo Finance, no API key required.

## When to use

Use this skill when building anything that needs stock market data: prices, financials, news, options, holders, analyst recommendations. The `yfinance` library provides all of this through a single `Ticker` object.

## Installation

```
pip install yfinance>=1.6.0
```

Transitive dependency: `pandas` (all data returns as DataFrames or dicts).

## Core Pattern

```python
import yfinance as yf

company = yf.Ticker("AAPL")
```

The `Ticker` object is the entry point for ALL data. Every method below is called on a Ticker instance.

## Ticker Methods — Complete Reference

### Price & Trading Data

#### `.history(period, interval)` → DataFrame
Returns OHLCV data. Index is DatetimeIndex.

```python
hist = company.history(period="1mo", interval="1d")
# Columns: Open, High, Low, Close, Volume, Dividends, Stock Splits
# Index: Date (DatetimeIndex)
```

**period values**: `1d`, `5d`, `1mo`, `3mo`, `6mo`, `1y`, `2y`, `5y`, `10y`, `ytd`, `max`
**interval values**: `1m`, `2m`, `5m`, `15m`, `30m`, `60m`, `90m`, `1h`, `1d`, `5d`, `1wk`, `1mo`, `3mo`

> Intraday intervals (1m–90m) cannot extend beyond the last 60 days.

To get the index as a column for JSON serialization:
```python
hist = hist.reset_index(names="Date")
```

#### `.info` → dict
Returns a large dict (100+ keys) with current price, company info, financial metrics.

```python
info = company.info
# Key fields: symbol, quoteType, currentPrice, regularMarketPrice,
# longName, sector, industry, marketCap, trailingPE, forwardPE,
# dividendYield, beta, fiftyTwoWeekHigh, fiftyTwoWeekLow, ...
```

**Validation pattern**: A valid ticker always has `symbol` and `quoteType` in the dict. If missing, the ticker is invalid.

```python
if not info or 'symbol' not in info or 'quoteType' not in info:
    return f"No stock info found for ticker {ticker}."
```

#### `.fast_info` → dict-like
Lightweight price data without a full `.info` fetch. Useful for spot price.

```python
price = company.fast_info.get("lastPrice")  # float or None
```

#### `.actions` → DataFrame
Dividends and stock splits history. Index is DatetimeIndex.

```python
actions = company.actions
# Columns: Dividends, Stock Splits
# Index: Date
actions = actions.reset_index(names="Date")
```

### News

#### `.news` → list[dict]
Returns news articles. Each item has nested `content` dict.

```python
news = company.news
# Structure of each item:
# {
#   "content": {
#     "contentType": "STORY",  # filter on this
#     "title": "...",
#     "summary": "...",
#     "description": "...",
#     "canonicalUrl": {"url": "https://..."}
#   }
# }
```

**Important**: Filter for `contentType == "STORY"` to get actual articles. Extract `title`, `summary`, `description`, and `canonicalUrl.url`.

### Financial Statements

All financial statement properties return a DataFrame where:
- **Columns** are `pd.Timestamp` dates (fiscal periods)
- **Index** (rows) are metric names (e.g., "Total Revenue", "Net Income")

This is the TRANSPOSE of what you might expect. To serialize to JSON records per date:

```python
result = []
for column in statement.columns:
    date_str = column.strftime("%Y-%m-%d") if isinstance(column, pd.Timestamp) else str(column)
    date_obj = {"date": date_str}
    for index, value in statement[column].items():
        date_obj[index] = None if pd.isna(value) else value
    result.append(date_obj)
return json.dumps(result)
```

#### Annual statements
- `.income_stmt` → DataFrame
- `.balance_sheet` → DataFrame
- `.cashflow` → DataFrame

#### Quarterly statements
- `.quarterly_income_stmt` → DataFrame
- `.quarterly_balance_sheet` → DataFrame
- `.quarterly_cashflow` → DataFrame

Check `.empty` before processing:
```python
if financial_statement.empty:
    return f"No financial statement data found for ticker {ticker}."
```

### Holder Information

All holder properties return DataFrames. Serialize with `.to_json(orient="records")`.

| Property | Returns | Notes |
|----------|---------|-------|
| `.major_holders` | DataFrame | Use `.reset_index(names="metric")` to get the metric column |
| `.institutional_holders` | DataFrame | Has `Holder` column |
| `.mutualfund_holders` | DataFrame | Use `date_format="iso"` |
| `.insider_transactions` | DataFrame | Use `date_format="iso"` |
| `.insider_purchases` | DataFrame | Use `date_format="iso"` |
| `.insider_roster_holders` | DataFrame | Use `date_format="iso"` |

### Options

#### `.options` → tuple of str
Returns available expiration dates as strings in `YYYY-MM-DD` format.

```python
options = company.options  # ("2024-01-19", "2024-01-26", ...)
```

#### `.option_chain(date)` → namedtuple
Returns a namedtuple with `.calls` and `.puts` DataFrames.

```python
chain = company.option_chain("2024-01-19")
calls_df = chain.calls
puts_df = chain.puts
# Columns: contractSymbol, lastTradeDate, strike, lastPrice, bid, ask,
#          change, percentChange, volume, openInterest, impliedVolatility,
#          inTheMoney, contractSize, currency
```

**Column names are camelCase** (not snake_case): `lastPrice`, `openInterest`, `impliedVolatility`, `inTheMoney`. This matters for field projection.

### Analyst Recommendations

#### `.recommendations` → DataFrame
Current analyst recommendations.

```python
recs = company.recommendations  # May be empty
if recs.empty:
    return "[]"
return recs.to_json(orient="records")
```

#### `.upgrades_downgrades` → DataFrame
Historical upgrades/downgrades. Has `GradeDate` as index and `Firm` column.

```python
ud = company.upgrades_downgrades
ud = ud.reset_index()  # Brings GradeDate from index to column
# Filter by date:
cutoff = pd.Timestamp.now() - pd.DateOffset(months=12)
ud = ud[ud["GradeDate"] >= cutoff]
ud = ud.sort_values("GradeDate", ascending=False)
# Deduplicate by firm (most recent only):
latest_by_firm = ud.drop_duplicates(subset=["Firm"])
```

## pandas → JSON Serialization Patterns

### Records format (most common)
```python
df.to_json(orient="records", date_format="iso")
# Returns: '[{"col1": val1, "col2": val2}, ...]'
```

### With date index → column
```python
df = df.reset_index(names="Date")
df.to_json(orient="records", date_format="iso")
```

### Financial statement (transposed)
Columns are dates, rows are metrics. Iterate columns to build per-date records:
```python
result = []
for column in stmt.columns:
    date_str = column.strftime("%Y-%m-%d") if isinstance(column, pd.Timestamp) else str(column)
    obj = {"date": date_str}
    for idx, val in stmt[column].items():
        obj[idx] = None if pd.isna(val) else val
    result.append(obj)
return json.dumps(result)
```

## Ticker Normalization Gotcha

Yahoo Finance uses hyphens for US class shares: `BRK-B`, `BF-B`. Users and LLMs often type `BRK.B` or `BRK/B`. The dotted form **silently returns empty data** (no error). Always normalize:

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

Only single-letter class suffixes (A, B) are converted. Exchange suffixes like `.TO`, `.L`, `.HK` are legitimate and left unchanged.

## Error Handling Pattern

yfinance methods rarely raise exceptions — they return empty DataFrames or dicts. Always check:
- `if not info or 'symbol' not in info` — invalid ticker
- `if df.empty` — no data for this query
- `if not options` — no options available
- Wrap everything in `try/except Exception as e` and return error strings
