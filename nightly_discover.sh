#!/usr/bin/env bash
# nightly_discover.sh (v4 — location_coordinate, country filter, real geography)
# ─────────────────────────────────────────────────────────────────────
# Nightly contractor discovery via DataForSEO Business Listings Search.
#
# v4 fixes from v3:
#   - DataForSEO's business_listings/search/live endpoint silently ignores
#     the location_name parameter. Their docs only show location_coordinate
#     as the geographic filter. v4 uses location_coordinate=lat,lng,radius.
#   - Adds country_code="US" filter at the API request level so non-US
#     records never enter the response.
#   - Requires lat/lng/radius from the metros table for each city queried.
#
# Usage:
#   ./nightly_discover.sh "Chicago" "IL" "roofing"
#   ./nightly_discover.sh "Houston" "TX" "hvac"
#
# Prerequisites:
#   - metros table must contain rows with city, state, latitude, longitude,
#     search_radius_km. Run seed_metros.py first if not yet seeded.
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

CITY="${1:-Chicago}"
STATE="${2:-IL}"
TRADE="${3:-roofing}"
DB="$HOME/.openclaw/kks.db"
LOG_DIR="$HOME/.openclaw/logs/discovery"
TS=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/${TS}_${CITY// /_}_${TRADE}.log"

mkdir -p "$LOG_DIR"
exec > >(tee "$LOG_FILE") 2>&1

echo "════════════════════════════════════════════════════════════════"
echo "KKS Nightly Discovery v4 — $(date)"
echo "Search: $CITY, $STATE  |  Trade: $TRADE"
echo "(coordinate-based geography, country-filtered)"
echo "════════════════════════════════════════════════════════════════"

# ── Credentials ──────────────────────────────────────────────────────
ENV_FILE="$HOME/.openclaw/secrets/dataforseo.env"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: credentials not found at $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

LOGIN="${DATAFORSEO_LOGIN:-${DFS_LOGIN:-}}"
PASSWORD="${DATAFORSEO_PASSWORD:-${DFS_PASSWORD:-}}"
[[ -n "$LOGIN" && -n "$PASSWORD" ]] || { echo "ERROR: no credentials"; exit 1; }
AUTH=$(echo -n "${LOGIN}:${PASSWORD}" | base64 -w 0)

# ── Trade mapping ────────────────────────────────────────────────────
case "$TRADE" in
    roofing)        CATEGORY="roofing_contractor"   ; KEYWORDS="roofing contractor" ;;
    hvac)           CATEGORY="hvac_contractor"      ; KEYWORDS="hvac contractor heating cooling" ;;
    plumbing)       CATEGORY="plumber"              ; KEYWORDS="plumber plumbing contractor" ;;
    electrical)     CATEGORY="electrician"          ; KEYWORDS="electrician electrical contractor" ;;
    remodeling)     CATEGORY="general_contractor"   ; KEYWORDS="remodeling contractor" ;;
    *)              echo "ERROR: Unsupported trade: $TRADE" ; exit 1 ;;
esac

# ── Look up market_id, latitude, longitude, radius ───────────────────
COORDS=$(sqlite3 "$DB" "SELECT id || '|' || latitude || '|' || longitude || '|' || COALESCE(search_radius_km, 30) FROM markets WHERE city = '$CITY' AND state = '$STATE' AND latitude IS NOT NULL AND longitude IS NOT NULL LIMIT 1;" 2>/dev/null || echo "")

if [[ -z "$COORDS" ]]; then
    echo "ERROR: No coordinates found in markets table for $CITY, $STATE."
    echo "       Run seed_metros.py to populate, or add this metro manually:"
    echo "       sqlite3 $DB \"INSERT INTO markets (city, state, latitude, longitude, search_radius_km) VALUES ('$CITY', '$STATE', LAT, LNG, 30);\""
    exit 1
fi

MARKET_ID=$(echo "$COORDS" | cut -d'|' -f1)
LAT=$(echo "$COORDS" | cut -d'|' -f2)
LNG=$(echo "$COORDS" | cut -d'|' -f3)
RADIUS=$(echo "$COORDS" | cut -d'|' -f4)

echo "Market ID:    $MARKET_ID"
echo "Coordinates:  $LAT, $LNG  (radius ${RADIUS}km)"
echo

# ── Build state-name to abbreviation lookup ──────────────────────────
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

cat > "$WORK_DIR/states.tsv" <<'STATES'
alabama	AL
alaska	AK
arizona	AZ
arkansas	AR
california	CA
colorado	CO
connecticut	CT
delaware	DE
florida	FL
georgia	GA
hawaii	HI
idaho	ID
illinois	IL
indiana	IN
iowa	IA
kansas	KS
kentucky	KY
louisiana	LA
maine	ME
maryland	MD
massachusetts	MA
michigan	MI
minnesota	MN
mississippi	MS
missouri	MO
montana	MT
nebraska	NE
nevada	NV
new hampshire	NH
new jersey	NJ
new mexico	NM
new york	NY
north carolina	NC
north dakota	ND
ohio	OH
oklahoma	OK
oregon	OR
pennsylvania	PA
rhode island	RI
south carolina	SC
south dakota	SD
tennessee	TN
texas	TX
utah	UT
vermont	VT
virginia	VA
washington	WA
west virginia	WV
wisconsin	WI
wyoming	WY
district of columbia	DC
STATES

# Build market lookup for cross-metro matching
sqlite3 "$DB" "SELECT id, city, state FROM markets WHERE city IS NOT NULL AND state IS NOT NULL;" \
    | awk -F'|' '{print tolower($2) "\t" toupper($3) "\t" $1}' \
    > "$WORK_DIR/market_lookup.tsv"

# ── Step 1: Query API with coordinate-based filter ───────────────────
PAYLOAD_FILE="$WORK_DIR/payload.json"
RESPONSE_FILE="$WORK_DIR/response.json"

cat > "$PAYLOAD_FILE" <<EOF
[
  {
    "categories": ["$CATEGORY"],
    "description": "$KEYWORDS",
    "location_coordinate": "$LAT,$LNG,$RADIUS",
    "filters": [["address_info.country_code", "=", "US"]],
    "limit": 1000,
    "order_by": ["rating.value,desc"]
  }
]
EOF

echo "── Step 1: Querying DataForSEO ──"
echo "Endpoint: business_data/business_listings/search/live"
echo "Filter:   coordinate=$LAT,$LNG,${RADIUS}km + US only"
echo

curl -s -X POST \
    "https://api.dataforseo.com/v3/business_data/business_listings/search/live" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json" \
    -d @"$PAYLOAD_FILE" \
    > "$RESPONSE_FILE"

STATUS=$(jq -r '.status_code' "$RESPONSE_FILE")
COST=$(jq -r '.cost' "$RESPONSE_FILE")

if [[ "$STATUS" != "20000" ]]; then
    echo "ERROR: API returned status $STATUS"
    jq '.status_message, .tasks[0].status_message' "$RESPONSE_FILE"
    exit 1
fi

ACTUAL_ITEMS=$(jq -r '.tasks[0].result[0].items | length // 0' "$RESPONSE_FILE")
TOTAL_AVAIL=$(jq -r '.tasks[0].result[0].total_count // 0' "$RESPONSE_FILE")
echo "API status: OK  |  Cost: \$$COST  |  Available: $TOTAL_AVAIL  |  Pulled: $ACTUAL_ITEMS"
echo

if [[ "$ACTUAL_ITEMS" == "0" ]]; then
    echo "Zero results returned. Check if coordinates are correct or radius is too small."
    exit 0
fi

# ── Step 2: Filter ────────────────────────────────────────────────────
FILTERED_FILE="$WORK_DIR/filtered.json"

jq -r '
  .tasks[0].result[0].items
  | map(select(
      (.url != null) and (.url | length > 0) and
      (.phone != null) and
      (.title != null) and
      (.title | test("supply|wholesale|real estate|insurance|attorney|lawyer|architect|appraisal|inspector|mortgage|realty|property management|rental"; "i") | not)
    ))
  | map({
      title: .title,
      url: .url,
      phone: (.phone // ""),
      address: (.address // ""),
      record_city: (.address_info.city // null),
      record_region: (.address_info.region // null),
      record_zip: (.address_info.zip // null),
      country_code: (.address_info.country_code // null),
      rating_count: (.rating.votes_count // 0),
      latitude: (.latitude // null),
      longitude: (.longitude // null),
      place_id: (.place_id // null)
    })
' "$RESPONSE_FILE" > "$FILTERED_FILE"

FILTERED_COUNT=$(jq 'length' "$FILTERED_FILE")
echo "── Step 2: Filtered (contractor-only, websites required) ──"
echo "After filters: $FILTERED_COUNT records"
echo

# ── Step 3: Dedupe ────────────────────────────────────────────────────
echo "── Step 3: Deduplicating ──"

sqlite3 "$DB" "SELECT website_url FROM prospects WHERE website_url IS NOT NULL AND website_url != '';" \
    | sed -E 's|^https?://(www\.)?||; s|/.*||; s|:.*||' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u > "$WORK_DIR/existing_domains.txt"

sqlite3 "$DB" "SELECT business_name FROM prospects WHERE business_name IS NOT NULL;" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9 ]//g; s/  +/ /g; s/^ +//; s/ +$//' \
    | sort -u > "$WORK_DIR/existing_names.txt"

DEDUPED_FILE="$WORK_DIR/deduped.json"

jq -c '.[]' "$FILTERED_FILE" | while read -r record; do
    url=$(echo "$record" | jq -r '.url')
    domain=$(echo "$url" | sed -E 's|^https?://(www\.)?||; s|/.*||; s|:.*||' | tr '[:upper:]' '[:lower:]')
    name=$(echo "$record" | jq -r '.title' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9 ]//g; s/  +/ /g; s/^ +//; s/ +$//')

    grep -Fxq "$domain" "$WORK_DIR/existing_domains.txt" 2>/dev/null && continue
    grep -Fxq "$name" "$WORK_DIR/existing_names.txt" 2>/dev/null && continue

    echo "$record"
done > "$DEDUPED_FILE"

NEW_COUNT=$(wc -l < "$DEDUPED_FILE" | tr -d ' ')
echo "Net-new records: $NEW_COUNT"
echo

if [[ "$NEW_COUNT" -eq 0 ]]; then
    echo "No net-new records. Cost: \$$COST"
    exit 0
fi

# ── Step 4: Sample ────────────────────────────────────────────────────
echo "── Step 4: First 10 to insert (per-record geo) ──"
head -10 "$DEDUPED_FILE" | jq -r '"  \(.title) | \(.record_city // "??"), \(.record_region // "??") | \(.rating_count) reviews"'
echo

# ── Step 5: Insert ────────────────────────────────────────────────────
echo "── Step 5: Inserting ──"

INSERT_FILE="$WORK_DIR/insert.sql"
SOURCE_TAG="DataForSEO Business Listings $(date +%Y-%m-%d) v4"

state_abbrev() {
    local fullname="$1"
    if [[ -z "$fullname" || "$fullname" == "null" ]]; then
        echo ""
        return
    fi
    local lower
    lower=$(echo "$fullname" | tr '[:upper:]' '[:lower:]')
    awk -F'\t' -v s="$lower" '$1==s {print $2; exit}' "$WORK_DIR/states.tsv"
}

{
    echo "BEGIN TRANSACTION;"

    while IFS= read -r record; do
        title=$(echo "$record" | jq -r '.title' | sed "s/'/''/g")
        url=$(echo "$record" | jq -r '.url' | sed "s/'/''/g")
        phone=$(echo "$record" | jq -r '.phone // ""' | sed "s/'/''/g")
        address=$(echo "$record" | jq -r '.address // ""' | sed "s/'/''/g")
        rec_city=$(echo "$record" | jq -r '.record_city // ""' | sed "s/'/''/g")
        rec_region=$(echo "$record" | jq -r '.record_region // ""')
        rec_zip=$(echo "$record" | jq -r '.record_zip // ""' | sed "s/'/''/g")
        rating_count=$(echo "$record" | jq -r '.rating_count // 0')

        rec_state_code=$(state_abbrev "$rec_region")

        if [[ -z "$rec_city" || "$rec_city" == "null" ]]; then
            sql_city="NULL"
        else
            sql_city="'$(echo "$rec_city" | sed "s/'/''/g")'"
        fi

        if [[ -z "$rec_state_code" ]]; then
            sql_state="NULL"
        else
            sql_state="'$rec_state_code'"
        fi

        if [[ -z "$rec_zip" || "$rec_zip" == "null" ]]; then
            sql_zip="NULL"
        else
            sql_zip="'$rec_zip'"
        fi

        # market_id: prefer the one we queried for (since records are within radius),
        # but try matching record's own city/state first for accuracy
        if [[ -n "$rec_city" && "$rec_city" != "null" && -n "$rec_state_code" ]]; then
            rec_market_id=$(awk -F'\t' \
                -v c="$(echo "$rec_city" | tr '[:upper:]' '[:lower:]')" \
                -v s="$rec_state_code" \
                '$1==c && $2==s {print $3; exit}' \
                "$WORK_DIR/market_lookup.tsv")
            if [[ -z "$rec_market_id" ]]; then
                # No exact match — record's city is a suburb/satellite of queried metro
                # Tag with the queried market_id since they're geographically within radius
                sql_market_id="$MARKET_ID"
            else
                sql_market_id="$rec_market_id"
            fi
        else
            sql_market_id="$MARKET_ID"
        fi

        if [[ "$sql_city" == "NULL" ]]; then
            note_sql="'address unverified — DataForSEO returned no city'"
        else
            note_sql="NULL"
        fi

        cat <<SQL
INSERT INTO prospects (
  market_id, business_name, website_url, phone, address, zip,
  city, state, trade_type, status, google_reviews_count, source, notes
) VALUES (
  $sql_market_id,
  '$title',
  '$url',
  '$phone',
  '$address',
  $sql_zip,
  $sql_city,
  $sql_state,
  '$TRADE',
  'new',
  $rating_count,
  '$SOURCE_TAG',
  $note_sql
);
SQL
    done < "$DEDUPED_FILE"

    echo "COMMIT;"
} > "$INSERT_FILE"

sqlite3 "$DB" < "$INSERT_FILE"

NEW_TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM prospects;")

echo
echo "── Complete ──"
echo "Records added:    $NEW_COUNT"
echo "Database total:   $NEW_TOTAL"
echo "Cost:             \$$COST"
echo
echo "════════════════════════════════════════════════════════════════"

echo
echo "── Geographic breakdown of records just added ──"
sqlite3 -header -column "$DB" <<SQL
SELECT
  COALESCE(state, 'NULL') as state,
  COUNT(*) as n
FROM prospects
WHERE source = '$SOURCE_TAG' AND trade_type = '$TRADE'
  AND id > (SELECT MAX(id) - $NEW_COUNT FROM prospects)
GROUP BY state
ORDER BY n DESC
LIMIT 10;
SQL

echo
echo "── Top 10 cities tonight ──"
sqlite3 -header -column "$DB" <<SQL
SELECT
  COALESCE(city, 'NULL') as city,
  state,
  COUNT(*) as n
FROM prospects
WHERE source = '$SOURCE_TAG' AND trade_type = '$TRADE'
  AND id > (SELECT MAX(id) - $NEW_COUNT FROM prospects)
GROUP BY city, state
ORDER BY n DESC
LIMIT 10;
SQL
