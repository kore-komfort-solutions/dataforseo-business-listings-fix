#!/usr/bin/env bash
# discover_batch.sh
# ─────────────────────────────────────────────────────────────────────
# Runs nightly_discover.sh across multiple metros and trades in one pass.
# Tracks cumulative cost and stops if budget exceeded.
#
# Usage:
#   ./discover_batch.sh [BUDGET_USD]
#   ./discover_batch.sh 8.00     # spend up to $8 tonight
#
# Safe to abort with Ctrl-C between queries.
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

BUDGET="${1:-8.00}"
DB="$HOME/.openclaw/kks.db"
LOG_DIR="$HOME/.openclaw/logs/discovery"
TS=$(date +%Y%m%d_%H%M%S)
SUMMARY_LOG="$LOG_DIR/${TS}_batch_summary.log"

mkdir -p "$LOG_DIR"

echo "════════════════════════════════════════════════════════════════"
echo "KKS Discovery Batch Runner — $(date)"
echo "Budget cap: \$$BUDGET"
echo "════════════════════════════════════════════════════════════════"
echo

# Get all metros with coordinates, ordered by largest radius first
# (mega metros first = densest population = most contractors per query)
METROS=$(sqlite3 "$DB" "SELECT city || '|' || state FROM markets WHERE latitude IS NOT NULL AND longitude IS NOT NULL ORDER BY search_radius_km DESC, city LIMIT 50;")

if [[ -z "$METROS" ]]; then
    echo "ERROR: No metros with coordinates in markets table."
    echo "Run seed_metros.py first."
    exit 1
fi

TRADES=("roofing" "hvac" "plumbing" "electrical")
SPENT="0.00"
QUERIES_RUN=0
QUERIES_SKIPPED=0
NET_NEW_TOTAL=0

START_DB_TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM prospects;")
echo "Starting database total: $START_DB_TOTAL prospects"
echo

# Average cost per query is roughly $0.27 — this lets us estimate before running
COST_PER_QUERY="0.31"

# Iterate metros
while IFS= read -r metro_state; do
    city="${metro_state%|*}"
    state="${metro_state#*|}"

    for trade in "${TRADES[@]}"; do
        # Check budget before each query
        # Compare floats with awk
        if awk -v s="$SPENT" -v c="$COST_PER_QUERY" -v b="$BUDGET" 'BEGIN { exit !(s + c > b) }'; then
            echo "Budget cap reached (\$$SPENT / \$$BUDGET). Stopping."
            break 2
        fi

        echo "── [$((QUERIES_RUN + 1))] $city, $state — $trade  (spent so far: \$$SPENT) ──"

        # Run discovery, capture output
        TMPLOG=$(mktemp)
        if ~/openclaw/scripts/nightly_discover.sh "$city" "$state" "$trade" > "$TMPLOG" 2>&1; then
            # Extract cost and count from output
            QUERY_COST=$(grep -oP 'Cost:\s+\$\K[0-9.]+' "$TMPLOG" | tail -1 || echo "0")
            ADDED=$(grep -oP 'Records added:\s+\K[0-9]+' "$TMPLOG" | tail -1 || echo "0")

            # Append to running totals
            SPENT=$(awk -v s="$SPENT" -v c="$QUERY_COST" 'BEGIN { printf "%.2f", s + c }')
            NET_NEW_TOTAL=$((NET_NEW_TOTAL + ADDED))
            QUERIES_RUN=$((QUERIES_RUN + 1))

            echo "  ✓ $ADDED net-new  |  cost: \$$QUERY_COST  |  cumulative: \$$SPENT"
        else
            echo "  ✗ Query failed (likely no metro coords or API error)"
            QUERIES_SKIPPED=$((QUERIES_SKIPPED + 1))
            tail -3 "$TMPLOG" | sed 's/^/      /'
        fi

        rm -f "$TMPLOG"
        sleep 2
    done
done <<< "$METROS"

# ── Final summary ────────────────────────────────────────────────────
END_DB_TOTAL=$(sqlite3 "$DB" "SELECT COUNT(*) FROM prospects;")
ACTUAL_NEW=$((END_DB_TOTAL - START_DB_TOTAL))

echo
echo "════════════════════════════════════════════════════════════════"
echo "BATCH COMPLETE"
echo "════════════════════════════════════════════════════════════════"
echo "Queries run:        $QUERIES_RUN"
echo "Queries skipped:    $QUERIES_SKIPPED"
echo "Net-new (counted):  $NET_NEW_TOTAL"
echo "Net-new (verified): $ACTUAL_NEW (DB grew from $START_DB_TOTAL to $END_DB_TOTAL)"
echo "Total spent:        \$$SPENT"
echo "Budget remaining:   \$$(awk -v b="$BUDGET" -v s="$SPENT" 'BEGIN { printf "%.2f", b - s }')"
echo

# Tonight's geographic breakdown
echo "── Top 15 cities discovered tonight (v4 source) ──"
sqlite3 -header -column "$DB" <<SQL
SELECT
  city,
  state,
  COUNT(*) as n
FROM prospects
WHERE source LIKE '%v4%'
  AND city IS NOT NULL
  AND date(created_at) = date('now')
GROUP BY city, state
ORDER BY n DESC
LIMIT 15;
SQL

echo
echo "── State distribution ──"
sqlite3 -header -column "$DB" <<SQL
SELECT
  COALESCE(state, 'NULL') as state,
  COUNT(*) as n
FROM prospects
WHERE source LIKE '%v4%'
  AND date(created_at) = date('now')
GROUP BY state
ORDER BY n DESC
LIMIT 15;
SQL

echo
echo "Summary log: $SUMMARY_LOG"
