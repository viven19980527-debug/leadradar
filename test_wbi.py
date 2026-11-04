# -*- coding: utf-8 -*-
"""验证 B站 wbi 签名：哈希输入该用「原始串」还是「URL 编码串」"""
import hashlib, time, urllib.parse, requests, json

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
s = requests.Session()
s.headers.update({"User-Agent": UA, "Referer": "https://www.bilibili.com/"})
s.get("https://www.bilibili.com/", timeout=10)

nav = s.get("https://api.bilibili.com/x/web-interface/nav", timeout=10).json()
wbi = nav["data"]["wbi_img"]
img = wbi["img_url"].rsplit("/", 1)[-1].split(".")[0]
sub = wbi["sub_url"].rsplit("/", 1)[-1].split(".")[0]
TAB = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,
       37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]
raw = img + sub
mixin = "".join(raw[i] for i in TAB)[:32]
print("mixin:", mixin)

kw = "空调安装多少钱"
params = {"search_type": "video", "keyword": kw, "page": "1", "page_size": "20", "order": "totalrank"}

def build(encoded_hash: bool):
    p = dict(params)
    p["wts"] = str(int(time.time()))
    items = sorted(p.items())
    items = [(k, "".join(c for c in v if c not in "!'()*")) for k, v in items]
    raw_q = "&".join(f"{k}={v}" for k, v in items)                       # 未编码
    enc_q = "&".join(f"{k}={urllib.parse.quote(v, safe='')}" for k, v in items)  # RFC3986
    target = enc_q if encoded_hash else raw_q
    rid = hashlib.md5((target + mixin).encode()).hexdigest()
    return f"https://api.bilibili.com/x/web-interface/wbi/search/type?{enc_q}&w_rid={rid}", rid

for mode, name in [(True, "编码串哈希"), (False, "原始串哈希")]:
    url, rid = build(mode)
    r = s.get(url, timeout=15)
    try:
        j = r.json()
    except Exception:
        print(f"{name}: 非 JSON {r.status_code}")
        continue
    n = len((j.get("data") or {}).get("result") or []) if j.get("data") else 0
    print(f"{name}: code={j.get('code')} msg={j.get('message')} 结果数={n}  rid={rid[:12]}")
