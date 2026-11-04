import requests

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

cands = [
    "https://www.douyin.com/user/self",
    "https://www.douyin.com/passport/web/login/",
    "https://www.douyin.com/discover",
    "https://www.douyin.com/?recommend=1",
    "https://www.kuaishou.com/new-reco",
    "https://passport.kuaishou.com/pc/account/login",
    "https://www.xiaohongshu.com/login",
    "https://www.xiaohongshu.com/explore?channel_id=homefeed_recommend",
]

for u in cands:
    try:
        r = requests.get(u, headers={"User-Agent": UA}, timeout=12, allow_redirects=True)
        body = r.text.lower()
        marks = []
        for k in ["扫码", "登录", "login", "signin", "二维码", "验证码", "qrcode"]:
            if k in body:
                marks.append(k)
        print(f"{r.status_code}  {u}")
        print(f"    最终: {r.url[:110]}")
        print(f"    登录要素: {marks[:4]}  长度: {len(r.text)}")
    except Exception as e:
        print(f"ERR {u}: {str(e)[:60]}")
