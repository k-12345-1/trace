# Rebuilding the gym directory

`Climbing App/Climbing App/Resources/gyms.json` is generated, not hand written.
It comes from OpenStreetMap, filtered here, and reverse geocoded for city and
state. Rebuild it when the list gets stale.

1. **Pull.** POST `q2.txt` and `q3.txt` to `https://overpass-api.de/api/interpreter` with a
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

`q3.txt` is the second sweep: `climbing=indoor`, `climbing:boulder`, gyms whose
name reads like a climbing gym, and sports shops and gyms carrying a climbing
sport tag. It found sixty seven the first query missed, including every Hangar
18, several Touchstone branches and Movement LIC.

A name sweep needs a second signal or it is useless. Matching "boulder" in a
name returns Boulder City Pool, Boulder Karate and Colorado Athletic Club
Boulder, because Boulder is a city and boulder is a word. A candidate is kept
only if it also carries a climbing tag or its name says "climb" or
"bouldering", and an explicit list rejects ski areas, pools, martial arts and
sporting goods stores.

## What it will not fix

OpenStreetMap only has what volunteers put in it. Stone Summit, a real chain in
Atlanta, is still absent from the source after both sweeps. That is a coverage
gap, not a bug in any of this, and the only fix is to map it upstream.
