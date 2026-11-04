import SwiftUI
import WebKit

// MARK: - 平台定义

enum Platform: String, CaseIterable, Identifiable {
    case bilibili, weibo, douyin, kuaishou, xhs
    var id: String { rawValue }

    var name: String {
        switch self {
        case .bilibili: return "B站"
        case .weibo: return "微博"
        case .douyin: return "抖音"
        case .kuaishou: return "快手"
        case .xhs: return "小红书"
        }
    }
    var color: Color {
        switch self {
        case .bilibili: return .pink
        case .weibo: return .orange
        case .douyin: return .primary
        case .kuaishou: return .red
        case .xhs: return .red
        }
    }
    var native: Bool { self == .bilibili }

    /// 协议解析器使用的平台标识
    var protocolKey: String {
        switch self {
        case .douyin:   return "douyin"
        case .xhs:      return "xhs"
        case .weibo:    return "weibo"
        case .kuaishou: return "kuaishou"
        case .bilibili: return "bilibili"
        }
    }

    /// 评论节点的 CSS 选择器（按优先级，取第一个有结果的）
    var domSelectors: String {
        let list: [String]
        switch self {
        case .douyin:
            list = ["[data-e2e='comment-item']", ".comment-item", "[class*='commentItem']",
                    "[class*='CommentItem']", ".rIYSC", ".comment"]
        case .kuaishou:
            list = [".comment-item", "[class*='comment']", ".kwai-comment", ".comment"]
        case .xhs:
            list = [".comment-item", ".comment-inner", "[class*='commentItem']",
                    ".note-comment", ".comment"]
        case .weibo:
            list = [".comment-item", ".item-content", ".m-container-max .card9",
                    ".card .m-text-cut", ".comment"]
        default:
            list = [".comment-item", ".reply-item", ".comment"]
        }
        return "[" + list.map { "'" + $0 + "'" }.joined(separator: ",") + "]"
    }

    /// 该平台的登录页（放进内置浏览器让用户登）
    var loginURL: String {
        switch self {
        case .douyin:   return "https://www.douyin.com/"
        case .kuaishou: return "https://www.kuaishou.com/"
        case .xhs:      return "https://www.xiaohongshu.com/explore"
        case .weibo:    return "https://passport.weibo.cn/signin/login"
        case .bilibili: return "https://passport.bilibili.com/login"
        }
    }

    /// WebView 搜索页地址
    func searchURL(_ kw: String) -> String {
        let e = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kw
        switch self {
        case .bilibili: return "https://m.bilibili.com/search?keyword=\(e)"
        case .weibo:    return "https://m.weibo.cn/search?containerid=100103type%3D1%26q%3D\(e)"
        case .douyin:   return "https://www.douyin.com/search/\(e)?type=video"
        case .kuaishou: return "https://www.kuaishou.com/search/video?searchKey=\(e)"
        case .xhs:      return "https://www.xiaohongshu.com/search_result?keyword=\(e)"
        }
    }
}

// MARK: - WebView 抓取器（hook fetch / XHR，拿页面自己签好名的接口数据）

struct WebGrabber: UIViewRepresentable {
    let platform: Platform
    let keyword: String
    var startURL: String? = nil
    @Binding var running: Bool
    let onBatch: ([Lead]) -> Void
    let onLog: (String) -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "ldr")
        cfg.userContentController = uc
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default()

        let hook = """
        (function(){
          if(window.__ldrHooked) return; window.__ldrHooked = 1;
          function send(url, body){
            try{ window.webkit.messageHandlers.ldr.postMessage({u: url||'', b: (body||'').slice(0,300000)}); }catch(e){}
          }
          const of = window.fetch;
          window.fetch = function(){
            const args = arguments;
            return of.apply(this, args).then(function(r){
              try{ const c = r.clone(); c.text().then(function(t){ send((args[0]&&args[0].url)||String(args[0]||''), t); }); }catch(e){}
              return r;
            });
          };
          const oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(m,u){ this.__u=u; return oo.apply(this, arguments); };
          XMLHttpRequest.prototype.send = function(){
            const self=this;
            this.addEventListener('load', function(){ try{ send(self.__u||'', self.responseText||''); }catch(e){} });
            return os.apply(this, arguments);
          };
        })();
        """
        uc.addUserScript(WKUserScript(source: hook, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false
        context.coordinator.webView = wv
        if let url = URL(string: startURL ?? platform.searchURL(keyword)) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coord) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeAllUserScripts()
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: WebGrabber
        weak var webView: WKWebView?
        private var scrollTimer: Timer?
        private var seen = Set<String>()
        private var rounds = 0

        init(_ p: WebGrabber) { parent = p }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLog("页面已加载，开始自动滚动采集…")
            startScrolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 40) { [weak self] in self?.finish() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLog("页面加载失败：\(error.localizedDescription)")
        }

        private func startScrolling() {
            scrollTimer?.invalidate()
            scrollTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { [weak self] _ in
                guard let self, let wv = self.webView else { return }
                self.rounds += 1
                if self.rounds > 14 { self.finish(); return }
                wv.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight); 'ok'", completionHandler: nil)
                self.scrapeDOM(wv)
                // 打开第一条内容，触发评论接口
                if self.rounds == 3 || self.rounds == 7 {
                    wv.evaluateJavaScript("""
                    (function(){
                      var sels=['a[href*="/video/"]','a[href*="/note/"]','a[href*="/detail"]','a[href*="/short-video/"]','.note-item a','.video-card a'];
                      for(var i=0;i<sels.length;i++){var el=document.querySelector(sels[i]); if(el){el.click(); return 'clicked';}}
                      return 'none';
                    })();
                    """, completionHandler: nil)
                }
            }
        }

        /// 从渲染后的 DOM 直接读评论文本（抓不到接口时的兜底）
        private func scrapeDOM(_ wv: WKWebView) {
            let js = """
            (function(){
              var sels = %@;
              var out = [];
              for (var i=0;i<sels.length;i++){
                var nodes = document.querySelectorAll(sels[i]);
                for (var j=0;j<nodes.length && out.length<120;j++){
                  var t = (nodes[j].innerText||'').trim();
                  if (t.length>4 && t.length<400) out.push(t);
                }
                if (out.length>0) break;
              }
              return JSON.stringify(out);
            })();
            """.replacingOccurrences(of: "%@", with: parent.platform.domSelectors)
            wv.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self,
                      let str = result as? String,
                      let data = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return }
                var batch: [Lead] = []
                for raw in arr {
                    let key = String(raw.prefix(30))
                    if self.seen.contains(key) { continue }
                    self.seen.insert(key)
                    let (score, tags, contact) = RadarScorer.score(raw, industry: "空调/家电")
                    guard score > 0 else { continue }
                    batch.append(Lead(platform: self.parent.platform.rawValue,
                                      uid: key, name: String(raw.prefix(12)),
                                      profileURL: "", text: raw, comments: 1,
                                      score: score, tags: tags, contact: contact,
                                      postTitle: self.parent.keyword, videoURL: "", createdAt: 0))
                }
                if !batch.isEmpty {
                    DispatchQueue.main.async { self.parent.onBatch(batch) }
                    self.parent.onLog("DOM 抓到 \(batch.count) 条")
                }
            }
        }

        private func finish() {
            scrollTimer?.invalidate(); scrollTimer = nil
            DispatchQueue.main.async { self.parent.running = false }
            parent.onLog("采集结束")
        }

        // 收到页面接口数据
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let url = dict["u"] as? String,
                  let body = dict["b"] as? String else { return }
            // 只关心像评论/搜索结果的接口
            guard body.count > 200, body.hasPrefix("{") || body.hasPrefix("[") else { return }

            // 协议级解析：端点白名单 → 打分兜底 → 分页三层合并 → 大整数保护
            let text = body
            var page: CapturePage?
            do {
                page = try LDProtocol.parse(body: text,
                                            platform: parent.platform.protocolKey,
                                            captureURL: url)
            } catch CaptureError.unsupportedEndpoint(let ep) {
                // 已知平台但端点不是评论接口 → 忽略（比如推荐流、用户信息接口）
                self.parent.onLog("跳过非评论接口 \(ep)")
                return
            } catch CaptureError.businessError(let m) {
                self.parent.onLog("接口业务错误：\(m)")
                return
            } catch {
                // 端点未知时退回通用启发式
                page = nil
            }

            let parsed: [CapturedComment]
            if let pg = page, !pg.comments.isEmpty {
                parsed = pg.comments
                if pg.hasMore || !pg.cursor.isEmpty {
                    self.parent.onLog("分页：cursor=\(pg.cursor.prefix(16)) hasMore=\(pg.hasMore) total=\(pg.total)")
                }
            } else {
                // 兜底：老逻辑（结构未知的 JSON）
                let anyJSON = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? [String: Any]()
                let items = CommentParser.extract(anyJSON)
                parsed = items.map {
                    CapturedComment(id: $0.uid + "_" + String($0.text.prefix(20)),
                                    parentID: "", userID: $0.uid, name: $0.name,
                                    handle: "", text: $0.text, likeCount: 0,
                                    createTime: "", sourceID: "", sourceURL: "")
                }
            }

            var batch: [Lead] = []
            for it in parsed {
                let key = it.id.isEmpty ? String(it.text.prefix(24)) : it.id
                if seen.contains(key) { continue }
                seen.insert(key)
                let (score, tags, contact) = RadarScorer.score(it.text, industry: "空调/家电")
                guard score > 0 else { continue }
                batch.append(Lead(platform: parent.platform.rawValue,
                                  uid: it.userID.isEmpty ? it.name : it.userID,
                                  name: it.name,
                                  profileURL: it.sourceURL.isEmpty ? "" : it.sourceURL,
                                  text: it.text, comments: 1, score: score,
                                  tags: tags, contact: contact,
                                  postTitle: parent.keyword,
                                  videoURL: it.sourceURL,
                                  createdAt: 0))
            }

            if !batch.isEmpty {
                let n = batch.count
                DispatchQueue.main.async { self.parent.onBatch(batch) }
                parent.onLog("捕获 \(n) 条（来自 \(url.prefix(50))…）")
            }
        }
    }
}

// MARK: - 通用评论解析（启发式，适配各平台 JSON 差异）

struct ParsedComment {
    let uid: String
    let name: String
    let text: String
    let profile: String
}

enum CommentParser {

    static func extract(_ json: Any) -> [ParsedComment] {
        var out: [ParsedComment] = []
        walk(json, &out, depth: 0)
        return out
    }

    private static func walk(_ node: Any, _ out: inout [ParsedComment], depth: Int) {
        if depth > 8 || out.count > 400 { return }
        if let arr = node as? [Any] {
            for x in arr { walk(x, &out, depth: depth + 1) }
            return
        }
        guard let d = node as? [String: Any] else { return }

        // 找评论文本字段
        let textKeys = ["content", "text", "comment_text", "content_text", "message"]
        var text: String?
        for k in textKeys {
            if let s = d[k] as? String, s.count >= 4, !s.hasPrefix("http") {
                text = s; break
            }
        }
        if let t = text, looksLikeComment(d) {
            let uid = firstString(d, ["uid", "user_id", "userId", "id", "mid", "author_id", "uid_str"]) ?? ""
            let name = userName(d) ?? "匿名"
            let prof = profileURL(d) ?? ""
            out.append(ParsedComment(uid: uid.isEmpty ? name : uid, name: name,
                                     text: stripHTML(t), profile: prof))
        }
        for (_, v) in d { walk(v, &out, depth: depth + 1) }
    }

    private static func looksLikeComment(_ d: [String: Any]) -> Bool {
        // 有 user 类字段、或评论特有字段
        let keys = Set(d.keys.map { $0.lowercased() })
        if keys.contains("user") || keys.contains("userinfo") || keys.contains("author") { return true }
        if keys.contains("like_count") || keys.contains("likecount") || keys.contains("reply_count") { return true }
        if keys.contains("commentid") || keys.contains("cid") || keys.contains("comment_id") { return true }
        return false
    }

    private static func firstString(_ d: [String: Any], _ keys: [String]) -> String? {
        for k in keys {
            if let v = d[k] as? String { return v }
            if let v = d[k] as? Int { return String(v) }
        }
        return nil
    }

    private static func userName(_ d: [String: Any]) -> String? {
        if let n = d["name"] as? String { return n }
        for k in ["user", "userInfo", "author", "user_info"] {
            if let u = d[k] as? [String: Any] {
                for nk in ["screen_name", "nickname", "name", "user_name", "uname"] {
                    if let s = u[nk] as? String { return s }
                }
            }
        }
        return nil
    }

    private static func profileURL(_ d: [String: Any]) -> String? {
        for k in ["user", "userInfo", "author"] {
            if let u = d[k] as? [String: Any] {
                for pk in ["profile_url", "homepage", "url", "profileUrl"] {
                    if let s = u[pk] as? String, s.hasPrefix("http") { return s }
                }
                if let uid = u["uid"] as? String { return "https://weibo.com/u/\(uid)" }
            }
        }
        return nil
    }

    static func stripHTML(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
        while let a = t.range(of: "<"), let b = t.range(of: ">", range: a.upperBound..<t.endIndex) {
            t.removeSubrange(a.lowerBound..<b.upperBound)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
