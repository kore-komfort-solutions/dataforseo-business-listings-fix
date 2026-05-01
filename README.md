# dataforseo-business-listings-fix

The DataForSEO Business Listings Search API silently ignores the `location_name` parameter.
Use `location_coordinate` instead. This repo documents the issue and provides working scripts.

## The Problem

`POST /v3/business_data/business_listings/search/live` accepts a `location_name` parameter
in the request payload. The endpoint returns results without an error. But the location filter
is not applied. The same query against six different cities returns the same 1,000 records.

This is not in the DataForSEO documentation as a known limitation. The docs only show
`location_coordinate` in their example payloads, but they do not flag `location_name` as
unsupported. Developers who carry the `location_name` pattern from DataForSEO's other
endpoints (SERP, Keywords Data, Backlinks, DataForSEO Labs) into Business Listings hit
this silent failure.

## The Fix

Use `location_coordinate` with format `"latitude,longitude,radius_in_km"`. Add a
country code filter to keep international results out:

```json
{
  "categories": ["roofing_contractor"],
  "description": "roofing contractor",
  "location_coordinate": "29.7604,-95.3698,30",
  "filters": [["address_info.country_code", "=", "US"]],
  "limit": 1000,
  "order_by": ["rating.value,desc"]
}
```

This returns roofing contractors within 30 km of Houston city center, US only.

## Before and After

We were building a contractor database for Kore Komfort Solutions LLC. The same workflow,
with one parameter name changed:

| Approach | Queries | Cost | Net-new records |
|---|---|---|---|
| `location_name` (broken) | 24 | ~$7 | 3 |
| `location_coordinate` (working) | 200 | ~$4 | 3,772 |

Same auth, same endpoint, same database, same dedup logic. The only difference is the
geographic parameter.

## Repository Contents

```
.
├── README.md                  This file
├── nightly_discover.sh        Main discovery script (working)
├── seed_metros.py             Seeds top US metros into a SQLite markets table
├── discover_batch.sh          Batch runner with budget cap
└── examples/
    ├── minimal.sh             Minimum viable working query
    └── diagnostic.sh          Two-query diagnostic to confirm location filter is working
```

## Quick Start

### 1. Set up DataForSEO credentials

```bash
mkdir -p ~/.openclaw/secrets
cat > ~/.openclaw/secrets/dataforseo.env <<'EOF'
DATAFORSEO_LOGIN=your-email@example.com
DATAFORSEO_PASSWORD=your-api-password
EOF
chmod 600 ~/.openclaw/secrets/dataforseo.env
```

### 2. Run the diagnostic to confirm the fix on your account

```bash
./examples/diagnostic.sh
```

This runs two queries against the same coordinate to verify the API behaves as expected.

### 3. Run a single discovery query

```bash
./nightly_discover.sh "Chicago" "IL" "roofing"
```

This requires a SQLite database at `~/.openclaw/kks.db` with a `markets` table seeded by
`seed_metros.py` and a `prospects` table (schema is at the top of `nightly_discover.sh`).

## Required Schema

The `nightly_discover.sh` script writes to a `prospects` table with these columns at minimum:

```sql
CREATE TABLE prospects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  market_id INTEGER,
  business_name TEXT NOT NULL,
  website_url TEXT,
  phone TEXT,
  address TEXT,
  zip TEXT,
  city TEXT,
  state TEXT,
  trade_type TEXT,
  status TEXT DEFAULT 'new',
  google_reviews_count INTEGER,
  source TEXT,
  notes TEXT
);
```

The `markets` table stores metro coordinates:

```sql
CREATE TABLE markets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  city TEXT,
  state TEXT NOT NULL,
  metro_area TEXT,
  latitude REAL,
  longitude REAL,
  search_radius_km INTEGER
);
```

## Pricing Notes

DataForSEO charges roughly $0.01 per task plus $0.0003 per row returned. A query that
returns 1,000 rows costs about $0.31. A query returning 50 rows costs about $0.025.

## Why I Wrote This

I am Mike Warner, founder of Kore Komfort Solutions LLC. I am building a contractor
intelligence database used internally for our Echelon Intelligence Reports product.
I spent roughly $8 figuring out this parameter name. The next person Googling "DataForSEO
business listings same results different cities" should not have to spend that.

The full writeup is at
[korekomfortsolutions.com/blog/dataforseo-business-listings-location-name-bug-fix/](https://korekomfortsolutions.com/blog/dataforseo-business-listings-location-name-bug-fix/).

## Disclaimers

- Not affiliated with DataForSEO.
- Behavior described is current as of May 2026. DataForSEO may update their API or docs;
  if you find this is no longer accurate, please open an issue.
- This repository contains no DataForSEO credentials. Bring your own.

## License

MIT. Use it however you want. Attribution appreciated but not required.
