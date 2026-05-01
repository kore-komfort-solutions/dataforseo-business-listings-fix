#!/usr/bin/env python3
"""
seed_metros.py
─────────────────────────────────────────────────────────────────────
Adds latitude, longitude, and search_radius_km columns to the markets
table (if not already present) and seeds the top 50 US metros with
coordinates suitable for DataForSEO Business Listings location_coordinate
queries.

Search radius is set per-metro based on metropolitan area size:
  - Mega metros (NYC, LA, Chicago, DFW, Houston): 50 km
  - Major metros (most top-30): 35 km
  - Secondary metros (smaller cities): 25 km

Existing markets are updated with coordinates if they match by city+state.
─────────────────────────────────────────────────────────────────────
"""

import sqlite3
import os

DB = os.path.expanduser("~/.openclaw/kks.db")

# (city, state, latitude, longitude, search_radius_km, metro_area)
# Coordinates are city center per Wikipedia. Population centers chosen to
# maximize coverage of the metro area within radius.
METROS = [
    # Mega metros — large radius
    ("New York", "NY", 40.7128, -74.0060, 50, "New York Metro"),
    ("Los Angeles", "CA", 34.0522, -118.2437, 50, "Greater Los Angeles"),
    ("Chicago", "IL", 41.8781, -87.6298, 50, "Chicago Metro"),
    ("Houston", "TX", 29.7604, -95.3698, 50, "Greater Houston"),
    ("Dallas", "TX", 32.7767, -96.7970, 50, "DFW Metro"),
    ("Fort Worth", "TX", 32.7555, -97.3308, 35, "DFW Metro"),
    ("Phoenix", "AZ", 33.4484, -112.0740, 50, "Phoenix Metro"),
    ("Philadelphia", "PA", 39.9526, -75.1652, 35, "Philadelphia Metro"),

    # Major metros — 35km radius
    ("San Antonio", "TX", 29.4241, -98.4936, 35, "San Antonio Metro"),
    ("San Diego", "CA", 32.7157, -117.1611, 35, "San Diego Metro"),
    ("Austin", "TX", 30.2672, -97.7431, 35, "Austin Metro"),
    ("Jacksonville", "FL", 30.3322, -81.6557, 35, "Jacksonville Metro"),
    ("Indianapolis", "IN", 39.7684, -86.1581, 35, "Indianapolis Metro"),
    ("Columbus", "OH", 39.9612, -82.9988, 35, "Columbus Metro"),
    ("Charlotte", "NC", 35.2271, -80.8431, 35, "Charlotte Metro"),
    ("San Francisco", "CA", 37.7749, -122.4194, 35, "Bay Area"),
    ("San Jose", "CA", 37.3382, -121.8863, 35, "Bay Area South"),
    ("Seattle", "WA", 47.6062, -122.3321, 35, "Seattle Metro"),
    ("Denver", "CO", 39.7392, -104.9903, 35, "Denver Metro"),
    ("Washington", "DC", 38.9072, -77.0369, 35, "DC Metro"),
    ("Boston", "MA", 42.3601, -71.0589, 35, "Boston Metro"),
    ("Nashville", "TN", 36.1627, -86.7816, 35, "Nashville Metro"),
    ("Memphis", "TN", 35.1495, -90.0490, 35, "Memphis Metro"),
    ("Portland", "OR", 45.5152, -122.6784, 35, "Portland Metro"),
    ("Oklahoma City", "OK", 35.4676, -97.5164, 35, "OKC Metro"),
    ("Las Vegas", "NV", 36.1699, -115.1398, 35, "Las Vegas Metro"),
    ("Louisville", "KY", 38.2527, -85.7585, 35, "Louisville Metro"),
    ("Baltimore", "MD", 39.2904, -76.6122, 30, "Baltimore Metro"),
    ("Milwaukee", "WI", 43.0389, -87.9065, 30, "Milwaukee Metro"),
    ("Albuquerque", "NM", 35.0844, -106.6504, 30, "Albuquerque Metro"),
    ("Tucson", "AZ", 32.2226, -110.9747, 30, "Tucson Metro"),
    ("Fresno", "CA", 36.7378, -119.7871, 30, "Fresno Metro"),
    ("Sacramento", "CA", 38.5816, -121.4944, 30, "Sacramento Metro"),
    ("Mesa", "AZ", 33.4152, -111.8315, 25, "Phoenix East"),
    ("Kansas City", "MO", 39.0997, -94.5786, 35, "Kansas City Metro"),
    ("Atlanta", "GA", 33.7490, -84.3880, 35, "Atlanta Metro"),
    ("Miami", "FL", 25.7617, -80.1918, 35, "Miami Metro"),
    ("Tampa", "FL", 27.9506, -82.4572, 30, "Tampa Bay"),
    ("Orlando", "FL", 28.5383, -81.3792, 30, "Orlando Metro"),
    ("Minneapolis", "MN", 44.9778, -93.2650, 35, "Twin Cities"),
    ("Detroit", "MI", 42.3314, -83.0458, 35, "Detroit Metro"),
    ("Cleveland", "OH", 41.4993, -81.6944, 30, "Cleveland Metro"),
    ("New Orleans", "LA", 29.9511, -90.0715, 30, "New Orleans Metro"),
    ("Pittsburgh", "PA", 40.4406, -79.9959, 30, "Pittsburgh Metro"),
    ("Cincinnati", "OH", 39.1031, -84.5120, 30, "Cincinnati Metro"),
    ("Salt Lake City", "UT", 40.7608, -111.8910, 30, "SLC Metro"),
    ("Raleigh", "NC", 35.7796, -78.6382, 30, "Raleigh-Durham"),
    ("Richmond", "VA", 37.5407, -77.4360, 30, "Richmond Metro"),
    ("Birmingham", "AL", 33.5186, -86.8104, 30, "Birmingham Metro"),
    ("St. Louis", "MO", 38.6270, -90.1994, 35, "St. Louis Metro"),
    ("Tulsa", "OK", 36.1540, -95.9928, 25, "Tulsa Metro"),
]


def main():
    if not os.path.exists(DB):
        print(f"ERROR: {DB} not found")
        return 1

    conn = sqlite3.connect(DB)
    cur = conn.cursor()

    # Add columns if missing
    cur.execute("PRAGMA table_info(markets)")
    existing_cols = {row[1] for row in cur.fetchall()}

    if "latitude" not in existing_cols:
        print("Adding 'latitude' column to markets table...")
        cur.execute("ALTER TABLE markets ADD COLUMN latitude REAL")
    if "longitude" not in existing_cols:
        print("Adding 'longitude' column to markets table...")
        cur.execute("ALTER TABLE markets ADD COLUMN longitude REAL")
    if "search_radius_km" not in existing_cols:
        print("Adding 'search_radius_km' column to markets table...")
        cur.execute("ALTER TABLE markets ADD COLUMN search_radius_km INTEGER")

    print()
    print(f"Seeding {len(METROS)} metros...")
    print()

    inserted = 0
    updated = 0

    for city, state, lat, lng, radius, metro_area in METROS:
        # Check if exists
        cur.execute(
            "SELECT id FROM markets WHERE city = ? AND state = ? LIMIT 1",
            (city, state)
        )
        row = cur.fetchone()

        if row:
            cur.execute(
                """UPDATE markets
                   SET latitude = ?, longitude = ?, search_radius_km = ?,
                       metro_area = COALESCE(metro_area, ?)
                   WHERE id = ?""",
                (lat, lng, radius, metro_area, row[0])
            )
            updated += 1
            print(f"  Updated: {city}, {state} (id={row[0]}) — {lat},{lng}, r={radius}km")
        else:
            cur.execute(
                """INSERT INTO markets
                   (city, state, latitude, longitude, search_radius_km, metro_area,
                    target_trades, competition_level)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (city, state, lat, lng, radius, metro_area,
                 '["HVAC","plumbing","roofing","electrical"]', "unknown")
            )
            inserted += 1
            new_id = cur.lastrowid
            print(f"  Inserted: {city}, {state} (id={new_id}) — {lat},{lng}, r={radius}km")

    conn.commit()

    print()
    print(f"Summary: {inserted} new metros inserted, {updated} existing metros updated.")

    # Show final state
    cur.execute(
        """SELECT COUNT(*) FROM markets
           WHERE latitude IS NOT NULL AND longitude IS NOT NULL"""
    )
    geocoded = cur.fetchone()[0]

    cur.execute("SELECT COUNT(*) FROM markets")
    total = cur.fetchone()[0]

    print(f"Markets with coordinates: {geocoded} / {total}")
    print()
    print("Sample of seeded metros:")
    cur.execute(
        """SELECT city, state, latitude, longitude, search_radius_km
           FROM markets
           WHERE latitude IS NOT NULL
           ORDER BY id
           LIMIT 10"""
    )
    for row in cur.fetchall():
        print(f"  {row[0]}, {row[1]}: ({row[2]}, {row[3]}) r={row[4]}km")

    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
