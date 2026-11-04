import requests, json

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")

cands = [
    "https://passport.weibo.cn/signin/login",
    "https://passport.weibo.com/sso/signin",
    "https://m.weibo.cn/login",
    "https://www.douyin.com/",
    "https://sso.douyin.com/",
    "https://www.douyin.com/login",
    "https://www.kuaishou.com/",
    "https://passport.kuaishou.com/pc/account/login",
    "https://www.xiaohongshu.com/explore",
    "https://www.xiaohongshu.com/login",
    "https://passport.bilibili.com/login",
    "https://m.bilibili.com/",
]

for u in cands:
    try:
        r = requests.get(u, headers={"User-Agent": UA}, timeout=12, allow_redirects=True)
        body = r.text[:3000].lower()
        has_login = any(k in body for k in ["登录", "login", "扫码", "signin", "验证码"])
        has_404 = any(k in body for k in ["404", "页面不存在", "not found", "已删除"])
        print(f"{r.status_code}  {'登录要素✓' if has_login else '无登录要素'}  "
              f"{'疑似404' if has_404 else ''}  {u}")
        print(f"      最终: {r.url[:100]}")
    except Exception as e:
        print(f"ERR  {u}  {str(e)[:60]}")
