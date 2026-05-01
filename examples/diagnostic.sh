#!/usr/bin/env bash
# diagnostic.sh
# ─────────────────────────────────────────────────────────────────────
# Confirms the DataForSEO Business Listings location parameter behavior.
#
# Runs three queries:
#   1. location_name = Houston    (BROKEN - returns global results)
#   2. location_name = Phoenix    (BROKEN - returns same global results)
#   3. location_coordinate = Houston center  (WORKING - returns Houston metro)
#
# If query 1 and query 2 return the same first record, location_name is
# being silently ignored. Query 3 should return actual Houston-area
# contractors, demonstrating that location_coordinate works correctly.
#
# Total cost: roughly $0.10 ($0.025 each for queries with limit=5).
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

source ~/.openclaw/secrets/dataforseo.env
AUTH=$(echo -n "${DATAFORSEO_LOGIN}:${DATAFORSEO_PASSWORD}" | base64 -w 0)

run_query() {
    local label="$1"
    local payload="$2"

    echo "─── $label ───"
    curl -s -X POST \
        "https://api.dataforseo.com/v3/business_data/business_listings/search/live" \
        -H "Authorization: Basic $AUTH" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        | jq -r '.tasks[0].result[0].items[] | "  \(.title) | \(.address // "no addr")"'
    echo
}

echo "═══════════════════════════════════════════════════════════════"
echo "DataForSEO Business Listings — location parameter diagnostic"
echo "═══════════════════════════════════════════════════════════════"
echo

# Query 1: location_name = Houston
run_query "Query 1: location_name=Houston,TX,United States (BROKEN)" \
'[{
  "categories": ["roofing_contractor"],
  "description": "roofing contractor",
  "location_name": "Houston,TX,United States",
  "limit": 5
}]'

# Query 2: location_name = Phoenix (different city, expect different results)
run_query "Query 2: location_name=Phoenix,AZ,United States (BROKEN)" \
'[{
  "categories": ["roofing_contractor"],
  "description": "roofing contractor",
  "location_name": "Phoenix,AZ,United States",
  "limit": 5
}]'

# Query 3: location_coordinate = Houston center, 30 km radius (WORKING)
run_query "Query 3: location_coordinate=29.7604,-95.3698,30 (WORKING)" \
'[{
  "categories": ["roofing_contractor"],
  "description": "roofing contractor",
  "location_coordinate": "29.7604,-95.3698,30",
  "filters": [["address_info.country_code", "=", "US"]],
  "limit": 5
}]'

echo "═══════════════════════════════════════════════════════════════"
echo "Expected outcome:"
echo "  Query 1 and Query 2 return identical lists (location_name is ignored)."
echo "  Query 3 returns Houston-area contractors only (location_coordinate works)."
echo "═══════════════════════════════════════════════════════════════"
