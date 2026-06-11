#!/usr/bin/env python3
"""Full-fidelity round-trip proof for the booking catalog exchangers.
Seed full-field category+resource -> export -> delete -> import -> re-fetch -> compare every field."""
import json, urllib.request, urllib.error, io

BASE = "http://localhost:8080/api/v1"

def req(method, path, token=None, body=None, multipart=None):
    url = BASE + path
    headers = {}
    data = None
    if token: headers["Authorization"] = f"Bearer {token}"
    if multipart is not None:
        boundary = "----rtboundary"
        buf = io.BytesIO()
        fname, content = multipart
        buf.write(f'--{boundary}\r\nContent-Disposition: form-data; name="mode"\r\n\r\nupsert\r\n'.encode())
        buf.write(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{fname}"\r\nContent-Type: application/json\r\n\r\n'.encode())
        buf.write(content.encode()); buf.write(f'\r\n--{boundary}--\r\n'.encode())
        data = buf.getvalue()
        headers["Content-Type"] = f"multipart/form-data; boundary={boundary}"
    elif body is not None:
        data = json.dumps(body).encode(); headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw.strip().startswith(("{","[")) else raw)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

# 1. login
_, d = req("POST", "/auth/login", body={"email":"admin@example.com","password":"AdminPass123@"})
token = d.get("access_token") or d.get("token")
print("login:", "OK" if token else "FAIL")

# 2. seed full-field category + resource
CAT = {"name":"RT Grand Marina Hotel","slug":"rt-grand-marina","description":"Five-star marina-front hotel.",
       "image_url":"https://example.com/hotel.jpg","config":{"stars":5,"city":"Nice"},"sort_order":1,"is_active":True}
sc, cat = req("POST","/admin/booking/categories",token,CAT)
cat_id = cat.get("id") if isinstance(cat,dict) else None
print("create category:", sc, "id=", cat_id)

RES = {"name":"RT Deluxe Sea View Suite","slug":"rt-deluxe-sea-view",
       "description":"Spacious suite, sea view, balcony, king bed.","capacity":3,"slot_duration_minutes":1440,
       "price":"249.99","currency":"EUR","price_unit":"per_night",
       "availability":{"lead_time_hours":2,"max_advance_days":90,
         "schedule":{"mon":[{"start":"14:00","end":"23:59"}],"tue":[],"wed":[],"thu":[],"fri":[],"sat":[],"sun":[]}},
       "custom_fields_schema":{"fields":[{"key":"breakfast","type":"bool"}]},
       "image_url":"https://example.com/suite.jpg","config":{"floor":4,"amenities":["wifi","minibar","balcony"]},
       "is_active":True,"sort_order":7,"category_ids":[cat_id]}
sc, res = req("POST","/admin/booking/resources",token,RES)
res_id = res.get("id") if isinstance(res,dict) else None
print("create resource:", sc, "id=", res_id)

def fetch_resource(slug):
    _, lst = req("GET","/admin/booking/resources",token)
    items = lst.get("resources") or lst.get("items") or lst if isinstance(lst,(list,dict)) else []
    if isinstance(items,dict): items = items.get("resources") or items.get("items") or []
    for it in (items if isinstance(items,list) else []):
        if it.get("slug")==slug: return it
    return None

original = fetch_resource("rt-deluxe-sea-view")

# 3. export categories + resources via the unified data-exchange API
sc, cat_env = req("POST","/admin/data-exchange/booking_categories/export",token,{})
sc2, res_env = req("POST","/admin/data-exchange/booking_resources/export",token,{})
print("export categories:", sc, "| export resources:", sc2)

# 4. delete the resource + category (clean slate)
if res_id: print("delete resource:", req("DELETE",f"/admin/booking/resources/{res_id}",token)[0])
if cat_id: print("delete category:", req("DELETE",f"/admin/booking/categories/{cat_id}",token)[0])
print("resource after delete present?:", fetch_resource("rt-deluxe-sea-view") is not None)

# 5. import back (categories first, then resources) via file upload (as the UI does)
ic, ir1 = req("POST","/admin/data-exchange/booking_categories/import",token,multipart=("booking_categories.json", json.dumps(cat_env)))
ic2, ir2 = req("POST","/admin/data-exchange/booking_resources/import",token,multipart=("booking_resources.json", json.dumps(res_env)))
print("import categories:", ic, ir1 if isinstance(ir1,dict) else str(ir1)[:200])
print("import resources:", ic2, ir2 if isinstance(ir2,dict) else str(ir2)[:200])

# 6. re-fetch + compare every field
reimported = fetch_resource("rt-deluxe-sea-view")
fields = ["name","slug","description","capacity","slot_duration_minutes","price","currency","price_unit",
          "availability","custom_fields_schema","image_url","config","is_active","sort_order"]
print("\n=== FIELD-BY-FIELD ROUND-TRIP COMPARISON ===")
rows=[]
for f in fields:
    o = original.get(f) if original else None
    n = reimported.get(f) if reimported else None
    match = json.dumps(o,sort_keys=True)==json.dumps(n,sort_keys=True)
    rows.append({"field":f,"original":o,"reimported":n,"match":match})
    print(f"  {'OK ' if match else 'DIFF'} {f}: {json.dumps(o)[:60]} -> {json.dumps(n)[:60]}")
# category link
o_cats = sorted([c.get("slug") for c in (original.get("categories") or [])]) if original else []
n_cats = sorted([c.get("slug") for c in (reimported.get("categories") or [])]) if reimported else []
cat_match = o_cats==n_cats
rows.append({"field":"categories (by slug)","original":o_cats,"reimported":n_cats,"match":cat_match})
print(f"  {'OK ' if cat_match else 'DIFF'} categories: {o_cats} -> {n_cats}")

allok = all(r["match"] for r in rows)
print(f"\nRESULT: {'ALL FIELDS PRESERVED ✓' if allok else 'SOME FIELDS DIFFER ✗'}  ({sum(r['match'] for r in rows)}/{len(rows)})")

# 7. dump artifacts for the report
out = {"original":original,"reimported":reimported,"exported_resource_envelope":res_env,
       "exported_category_envelope":cat_env,"comparison":rows,"all_preserved":allok,
       "import_result_resources":ir2,"import_result_categories":ir1}
with open("/tmp/rt_result.json","w") as fh: json.dump(out,fh,indent=2,default=str)
print("artifacts -> /tmp/rt_result.json")
