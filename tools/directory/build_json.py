import json, re, os, collections

STATES={'Alabama':'AL','Alaska':'AK','Arizona':'AZ','Arkansas':'AR','California':'CA','Colorado':'CO',
'Connecticut':'CT','Delaware':'DE','Florida':'FL','Georgia':'GA','Hawaii':'HI','Idaho':'ID','Illinois':'IL',
'Indiana':'IN','Iowa':'IA','Kansas':'KS','Kentucky':'KY','Louisiana':'LA','Maine':'ME','Maryland':'MD',
'Massachusetts':'MA','Michigan':'MI','Minnesota':'MN','Mississippi':'MS','Missouri':'MO','Montana':'MT',
'Nebraska':'NE','Nevada':'NV','New Hampshire':'NH','New Jersey':'NJ','New Mexico':'NM','New York':'NY',
'North Carolina':'NC','North Dakota':'ND','Ohio':'OH','Oklahoma':'OK','Oregon':'OR','Pennsylvania':'PA',
'Rhode Island':'RI','South Carolina':'SC','South Dakota':'SD','Tennessee':'TN','Texas':'TX','Utah':'UT',
'Vermont':'VT','Virginia':'VA','Washington':'WA','West Virginia':'WV','Wisconsin':'WI','Wyoming':'WY',
'District of Columbia':'DC'}
ABBR=set(STATES.values())

def st(v):
    if not v: return None
    v=v.strip()
    if v.upper() in ABBR: return v.upper()
    return STATES.get(v.title()) or STATES.get(v)

rev={}
if os.path.exists('nom_out.jsonl'):
    for line in open('nom_out.jsonl'):
        try: d=json.loads(line)
        except Exception: continue
        r=d.get('r') or {}
        a=(r.get('address') or {})
        rev[d['osm']]={
            'city': a.get('city') or a.get('town') or a.get('village') or a.get('hamlet')
                    or a.get('suburb') or a.get('municipality') or a.get('county'),
            'state': st(a.get('state')),
        }

import sys; sys.path.insert(0,'/tmp')
from exclude import drop as drop_reason

recs=json.load(open('deduped.json'))
out=[]; dropped=[]; reasons=collections.Counter()
for r in recs:
    why=drop_reason(r['name'])
    if why:
        reasons[why]+=1; continue
    t=r['tags']
    fb=rev.get(r['osm'],{})
    city=(t.get('addr:city') or fb.get('city') or '').strip()
    state=st(t.get('addr:state')) or fb.get('state')
    if not city or not state:
        # No US state resolved. This is also the country filter: the bounding
        # box that fetched these reaches into Ontario, Quebec and British
        # Columbia, and a Montreal salle d'escalade resolves to no US state.
        reasons['outside the US, or no city and state found']+=1
        dropped.append((r['name'], r['osm'], city, state)); continue

    num=(t.get('addr:housenumber') or '').strip()
    road=(t.get('addr:street') or '').strip()
    street=(f'{num} {road}'.strip() if road else None) or None

    web=(t.get('website') or t.get('contact:website') or '').strip()
    if web and not web.startswith('http'): web='https://'+web
    if not web: web=None

    out.append({
        'id': r['osm'],
        'name': re.sub(r'\s+',' ', r['name']).strip(),
        'city': re.sub(r'\s+',' ', city),
        'state': state,
        'street': street,
        'website': web,
        'latitude': round(r['lat'], 6),
        'longitude': round(r['lon'], 6),
    })

# Two entries with the same name in the same city and the same street (or no
# street on either) are one gym mapped twice. Two with different streets are two
# branches of a chain, which is what most of these are, and both must stay.
seen = {}
merged = 0
unique = []
for v in out:
    key = (v['name'].lower(), v['city'].lower(), v['state'], (v['street'] or '').lower())
    if key in seen:
        merged += 1
        # Keep whichever carries more.
        kept = seen[key]
        for f in ('street', 'website'):
            if not kept[f] and v[f]: kept[f] = v[f]
        continue
    seen[key] = v
    unique.append(v)
out = unique
if merged: reasons['the same gym mapped twice'] = merged

out.sort(key=lambda v:(v['state'], v['city'], v['name']))
json.dump(out, open('gyms.json','w'), indent=0, ensure_ascii=False)

print('kept   ', len(out))
for k,v in reasons.most_common(): print(f'  dropped {v:4d}  {k}')
print('states ', len(set(v['state'] for v in out)))
print('with street ', sum(1 for v in out if v['street']))
print('with website', sum(1 for v in out if v['website']))
print()
for s,n in collections.Counter(v['state'] for v in out).most_common(10): print(f'  {s} {n}')
