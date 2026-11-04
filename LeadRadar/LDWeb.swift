import SwiftUI
import WebKit

// MARK: - 平台

enum Platform: String, CaseIterable, Identifiable {
    case bilibili, weibo, douyin, kuaishou, xhs
    var id: String { rawValue }

    var name: String {
        switch self {
        case .bilibili: return "B站"
        case .weibo:    return "微博"
        case .douyin:   return "抖音"
        case .kuaishou: return "快手"
        case .xhs:      return "小红书"
        }
    }

    var native: Bool { self == .bilibili }

    /// houmen 协议桥只认识这两个
    var houmenKey: String? {
        switch self {
        case .douyin: return "douyin"
        case .xhs:    return "xiaohongshu"
        default:      return nil
        }
    }

    func searchURL(_ kw: String) -> String {
        let e = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kw
        switch self {
        case .bilibili: return "https://m.bilibili.com/search?keyword=\(e)"
        case .weibo:    return "https://m.weibo.cn/search?containerid=100103type%3D1%26q%3D\(e)"
        case .douyin:   return "https://www.douyin.com/search/\(e)"
        case .kuaishou: return "https://www.kuaishou.com/search/video?searchKey=\(e)"
        case .xhs:      return "https://www.xiaohongshu.com/search_result?keyword=\(e)"
        }
    }

    var loginURL: String {
        switch self {
        case .douyin:   return "https://www.douyin.com/hot"
        case .kuaishou: return "https://passport.kuaishou.com/pc/account/login"
        case .xhs:      return "https://www.xiaohongshu.com/login"
        case .weibo:    return "https://passport.weibo.cn/signin/login"
        case .bilibili: return "https://passport.bilibili.com/login"
        }
    }

    /// 搜索结果页里「作品详情」链接的选择器（按优先级）
    var contentSelectors: String {
        let list: [String]
        switch self {
        case .douyin:   list = ["a[href*='/video/']", "a[href*='modal_id=']"]
        case .xhs:      list = ["a[href*='/explore/']", "a[href*='/search_result/']", ".note-item a"]
        case .kuaishou: list = ["a[href*='/short-video/']", "a[href*='/profile/']", ".video-card a"]
        case .weibo:    list = ["a[href*='/detail/']", "a[href*='/status/']", ".card a"]
        default:        list = ["a[href*='/video/']"]
        }
    }

    /// 评论节点选择器（DOM 兜底）
    var domSelectors: String {
        let list: [String]
        switch self {
        case .douyin:   list = ["[data-e2e='comment-item']", ".comment-item", "[class*='commentItem']"]
        case .kuaishou: list = [".comment-item", "[class*='comment']", ".kwai-comment"]
        case .xhs:      list = [".comment-item", ".comment-inner", "[class*='commentItem']"]
        case .weibo:    list = [".item-content", ".card .m-text-cut", ".comment"]
        default:        list = [".comment-item", ".reply-item"]
        }
    }
}

// MARK: - 采集器：直接进详情页 + 协议桥 + DOM 兜底

struct HoumenCollector: UIViewRepresentable {
    let platform: Platform
    let keyword: String
    let target: Int
    var startURL: String? = nil
    var drive: Bool = true
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

        let key = platform.houmenKey ?? ""
        let taskId = "ldr-\(Int(Date().timeIntervalSince1970))"
        context.coordinator.taskId = taskId

        if !key.isEmpty {
            let bootstrap = """
            window.__houmenProtocolInitialTask = { platform: "\(key)", taskId: "\(taskId)" };
            """
            uc.addUserScript(WKUserScript(source: bootstrap,
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true))
            uc.addUserScript(WKUserScript(source: HoumenJS.protocolCapture(),
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: false))
        }

        if startURL != nil {
            let autoClick = """
            (function(){
              var texts = ['登录','立即登录','注册/登录','扫码登录'];
              var tries = 0;
              var t = setInterval(function(){
                if (++tries > 15) { clearInterval(t); return; }
                var nodes = document.querySelectorAll('button, a, div[role=button], span');
                for (var i=0;i<nodes.length;i++){
                  var s = (nodes[i].innerText||'').trim();
                  if (texts.indexOf(s) >= 0 && nodes[i].getBoundingClientRect().width > 0) {
                    nodes[i].click(); clearInterval(t); return;
                  }
                }
              }, 900);
            })();
            """
            uc.addUserScript(WKUserScript(source: autoClick,
                                          injectionTime: .atDocumentEnd,
                                          forMainFrameOnly: true))
        }

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        context.coordinator.webView = wv

        if let url = URL(string: startURL ?? platform.searchURL(keyword)) {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coord) {
        coordinator.stop()
        uiView.stopLoading()
        uiView.configuration.userContentController.removeAllUserScripts()
    }

    // MARK: - 驱动器

    final class Coord: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: HoumenCollector
        weak var webView: WKWebView?
        var taskId = ""

        private var timer: Timer?
        private var ticks = 0
        private var seen = Set<String>()
        private var got = 0

        private var links: [String] = []
        private var linkIndex = -1
        private var pageTicks = 0
        private var finished = false

        init(_ p: HoumenCollector) { parent = p }

        func stop() { timer?.invalidate(); timer = nil }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard parent.drive else { parent.onLog("页面已加载（登录模式）"); return }
            if timer == nil {
                parent.onLog("页面已加载，开始采集…")
                timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.tick()
                }
            }
        }

        private func js(_ code: String, _ done: @escaping (Any?) -> Void) {
            webView?.evaluateJavaScript(code) { result, err in
                if err != nil { done(nil); return }
                done(result)
            }
        }

        // MARK: 主循环

        private func tick() {
            guard !finished else { return }
            ticks += 1
            if ticks > 120 || got >= parent.target { finish(); return }

            if links.isEmpty && linkIndex < 0 {
                // 阶段 A：找搜索结果里的作品链接
                collectLinks { count in
                    if count == 0 {
                        if self.ticks > 6 {
                            self.parent.onLog("没找到作品链接：请确认已登录、且页面是搜索结果页")
                            self.finish()
                        }
                    } else {
                        self.parent.onLog("找到 \(count) 个作品，开始逐个进详情")
                        self.openNext()
                    }
                }
                return
            }

            // 阶段 B：在详情页收数据
            pageTicks += 1
            scrollPage()
            pollProtocol()
            scrapeDOM()
            if pageTicks >= 3 {
                if got >= parent.target || linkIndex + 1 >= min(links.count, 8) {
                    finish()
                } else {
                    openNext()
                }
            }
        }

        private func collectLinks(_ done: @escaping (Int) -> Void) {
            let sels = parent.platform.contentSelectors
            let code = """
            (function(){
              var out=[], seen={}, sels=\(sels);
              for (var i=0;i<sels.length;i++){
                var nodes=document.querySelectorAll(sels[i]);
                for (var j=0;j<nodes.length && out.length<40;j++){
                  var h=nodes[j].getAttribute('href')||'';
                  if(!h) continue;
                  if(h.indexOf('http')!==0) h = location.origin + h;
                  if(seen[h]) continue; seen[h]=1; out.push(h);
                }
                if(out.length>0) break;
              }
              return JSON.stringify(out);
            })();
            """
            js(code) { result in
                guard let s = result as? String,
                      let d = s.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: d) as? [String] else {
                    done(0); return
                }
                self.links = arr
                done(arr.count)
            }
        }

        private func openNext() {
            linkIndex += 1
            pageTicks = 0
            guard linkIndex < links.count else { finish(); return }
            let url = links[linkIndex]
            parent.onLog("进入详情 \(linkIndex + 1)/\(min(links.count, 8))：\(url.suffix(30))")
            if let u = URL(string: url) { webView?.load(URLRequest(url: u)) }
        }

        private func scrollPage() {
            let js = """
            (function(){
              var h = document.body.scrollHeight;
              window.scrollTo(0, h*0.6);
              setTimeout(function(){ window.scrollTo(0, document.body.scrollHeight); }, 700);
              return 'ok';
            })();
            """
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: 协议桥

        private func pollProtocol() {
            guard let key = parent.platform.houmenKey else { return }
            let code = """
            (function(){
              try {
                if (!window.__houmenProtocol) return 'null';
                return JSON.stringify(window.__houmenProtocol.read({
                  platform: "\(key)", sourceUrl: location.href
                }) || {});
              } catch(e){ return 'null'; }
            })();
            """
            js(code) { result in
                guard let s = result as? String, s != "null",
                      let d = s.data(using: .utf8),
                      let page = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
                let rows = (page["rows"] as? [[String: Any]])
                    ?? (page["comments"] as? [[String: Any]]) ?? []
                if !rows.isEmpty { self.parent.onLog("协议桥：\(rows.count) 条") }
                self.handle(rows.map { r in
                    (text: (r["text"] as? String) ?? "",
                     uid: (r["userId"] as? String) ?? "",
                     name: (r["name"] as? String) ?? "",
                     bio: (r["bio"] as? String) ?? "",
                     avatar: (r["avatar"] as? String) ?? "",
                     city: (r["ipLocation"] as? String) ?? "",
                     src: (r["sourceUrl"] as? String) ?? "")
                })
            }
        }

        // MARK: DOM 兜底

        private func scrapeDOM() {
            let js = """
            (function(){
              var sels=\(parent.platform.domSelectors), out=[];
              for (var i=0;i<sels.length;i++){
                var nodes=document.querySelectorAll(sels[i]);
                for (var j=0;j<nodes.length && out.length<80;j++){
                  var n=nodes[j];
                  var r=n.getBoundingClientRect();
                  if(r.width<=0||r.height<=0) continue;
                  var t=(n.innerText||'').trim();
                  if(t.length>4 && t.length<400) out.push(t);
                }
                if(out.length>0) break;
              }
              return JSON.stringify(out);
            })();
            """
            js(js) { _ in }
            webView?.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self, let s = result as? String,
                      let d = s.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: d) as? [String] else { return }
                if !arr.isEmpty { self.parent.onLog("DOM：\(arr.count) 条") }
                self.handle(arr.map { (text: $0, uid: "", name: "", bio: "", avatar: "", city: "", src: "") })
            }
        }

        // MARK: 统一处理

        private func handle(_ items: [(text: String, uid: String, name: String, bio: String,
                                       avatar: String, city: String, src: String)]) {
            var batch: [Lead] = []
            for it in items {
                let text = it.text
                guard text.count >= 4 else { continue }
                let key = String(text.prefix(30))
                if seen.contains(key) { continue }
                seen.insert(key)

                let (score, tags, contact) = RadarScorer.score(text, industry: "空调/家电")
                guard score > 0 else { continue }

                var lead = Lead(platform: parent.platform.rawValue,
                                uid: it.uid.isEmpty ? key : it.uid,
                                name: it.name.isEmpty ? "匿名" : it.name,
                                profileURL: "",
                                text: text, comments: 1, score: score,
                                tags: tags, contact: contact,
                                postTitle: parent.keyword,
                                videoURL: it.src.isEmpty ? (webView?.url?.absoluteString ?? "") : it.src,
                                createdAt: 0)
                lead.bio = it.bio
                lead.avatar = it.avatar
                lead.city = it.city
                lead.isQuestion = QuestionDetector.isQuestion(text)

                if let best = BioParser.best(BioParser.extract(it.bio)) {
                    lead.contact = best
                    lead.score = min(100, lead.score + 25)
                    if !lead.tags.contains("简介有联系方式") { lead.tags.append("简介有联系方式") }
                }
                batch.append(lead)
            }
            guard !batch.isEmpty else { return }
            got += batch.count
            parent.onLog("累计 \(got) 条")
            DispatchQueue.main.async { self.parent.onBatch(batch) }
        }

        private func finish() {
            guard !finished else { return }
            finished = true
            stop()
            DispatchQueue.main.async { self.parent.running = false }
            parent.onLog("采集结束，共 \(got) 条")
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {}
    }
}
