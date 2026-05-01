#!/usr/bin/env bash
# minimal.sh
# ─────────────────────────────────────────────────────────────────────
# Minimum viable working query for DataForSEO Business Listings Search.
# Demonstrates the location_coordinate fix in the smallest possible script.
#
# Replace LAT, LNG, RADIUS_KM, and CATEGORY with your values.
# Make sure ~/.openclaw/secrets/dataforseo.env exports your credentials.
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

# Load credentials
source ~/.openclaw/secrets/dataforseo.env
AUTH=$(echo -n "${DATAFORSEO_LOGIN}:${DATAFORSEO_PASSWORD}" | base64 -w 0)

# Houston, TX center coordinates with 30 km radius
LAT="29.7604"
LNG="-95.3698"
RADIUS_KM="30"

# Google Maps category ID — see DataForSEO docs for the full list
CATEGORY="roofing_contractor"

# Run the query
curl -s -X POST \
    "https://api.dataforseo.com/v3/business_data/business_listings/search/live" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    -d "[{
      \"categories\": [\"$CATEGORY\"],
      \"description\": \"roofing contractor\",
      \"location_coordinate\": \"$LAT,$LNG,$RADIUS_KM\",
      \"filters\": [[\"address_info.country_code\", \"=\", \"US\"]],
      \"limit\": 10,
      \"order_by\": [\"rating.value,desc\"]
    }]" \
    | jq -r '.tasks[0].result[0].items[] | "\(.title) | \(.address // "no address") | \(.rating.votes_count // 0) reviews"'
