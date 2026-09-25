# Rebuilding the gym directory

`Climbing App/Climbing App/Resources/gyms.json` is generated, not hand written.
It comes from OpenStreetMap, filtered here, and reverse geocoded for city and
state. Rebuild it when the list gets stale.

1. **Pull.** POST `q2.txt` to `https://overpass-api.de/api/interpreter` with a
   real `User-Agent`, saving `us_raw.json`. Overpass refuses a request without
   one. The tag to match is `leisure=sports_centre`, with an S: `sport_centre`
   returns nothing and looks like an empty country.
2. **Dedupe** by normalized name within 1.5 km, since a gym is often mapped as
   both a node and a building.
3. **Reverse geocode** everything without `addr:city` and `addr:state`, through
   Nominatim at no more than one request a second. That is their published
   limit and it is not negotiable; the run takes about an hour.
4. **Build** with `build_json.py`, which applies `exclude.py` and writes
   `gyms.json`.

## What the filters are for

The bounding box is a rectangle and the United States is not, so it reaches into
Ontario, Quebec and British Columbia. Requiring a resolved US state is what
excludes them; there is no separate country filter.

`exclude.py` removes what OpenStreetMap tags `sport=climbing` that is not an
indoor gym: Scout COPE towers, ropes and challenge courses, zip lines, and
outdoor crags mapped as facilities. Names are flattened before matching, because
`C.O.P.E.` and `COPE` are the same word and the first one slips a plain `\bcope\b`.

## What it will not fix

OpenStreetMap only has what volunteers put in it. Stone Summit, a real chain in
Atlanta, is absent from the source entirely. That is a coverage gap, not a bug
in any of this, and the only fix is to map it upstream.
