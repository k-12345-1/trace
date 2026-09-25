import re, unicodedata

# Things OpenStreetMap tags as sport=climbing on a sports_centre that are not
# indoor climbing gyms: Scout COPE towers, ropes and challenge courses, zip
# lines, and outdoor crags that someone mapped as a facility.
EXCLUDE = re.compile(r"""
    \b(
      ropes?\s*course | teams?\s*course | challenge\s*course | ropes?\s*challenge
    | cope | zip\s*-?\s*line | canopy | aerial\s+(adventure|challenge)
    | via\s+ferrata | rappell?ing | rappel\s*(area|tower)
    | adventure\s+(park|tour) | tree\s*top | ninja\s+course | obstacle\s+course
    | climbing\s+area | bouldering\s+area | boulder\s+field | crag
    | climbing\s+tower | rock\s+garden
    )\b
""", re.I | re.X)

# A name that tells the user nothing and cannot be told apart from its neighbors.
GENERIC = {"climbing", "climbing wall", "climbing gym", "bouldering", "boulder",
           "rock climbing", "gym", "wall", "tower", "rock wall", "climbing boulder",
           "bouldering wall", "rock climbing wall", "climbing walls", "boulders"}

def _flat(name):
    """Punctuation out, so C.O.P.E. and COPE are the same word."""
    n = unicodedata.normalize('NFKD', name)
    n = ''.join(ch for ch in n if not unicodedata.combining(ch))
    return re.sub(r'[^A-Za-z0-9]+', ' ', n).strip()

def drop(name):
    """Returns the reason to drop, or None to keep."""
    flat = _flat(name)
    if EXCLUDE.search(flat):
        return "ropes course, zip line or outdoor crag"
    if flat.lower() in GENERIC:
        return "name says nothing"
    if len(flat) < 3:
        return "name too short"
    return None
