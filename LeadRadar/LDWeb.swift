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

    /// houmen 协议桥认识的平台名（只支持这两个）
    var houmenKey: String? {
        switch self {
        case .douyin: return "douyin"
        case .xhs:    return "xiaohongshu"
        default:      return nil
        }
    }

    /// 用 houmen 采集脚本的平台（抖音 / 小红书）
    var usesHoumen: Bool { houmenKey != nil }

    var protocolKey: String {
        switch self {
        case .douyin:   return "douyin"
        case .xhs:      return "xhs"
        case .weibo:    return "weibo"
        case .kuaishou: return "kuaishou"
        case .bilibili: return "bilibili"
        }
    }

    /// 搜索页（houmen 脚本要求 /search/<关键词> 这种路径）
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

    /// 登录页（实测可用）
    var loginURL: String {
        switch self {
        case .douyin:   return "https://www.douyin.com/hot"
        case .kuaishou: return "https://passport.kuaishou.com/pc/account/login"
        case .xhs:      return "https://www.xiaohongshu.com/login"
        case .weibo:    return "https://passport.weibo.cn/signin/login"
        case .bilibili: return "https://passport.bilibili.com/login"
        }
    }

    var domSelectors: String {
        let list: [String]
        switch self {
        case .douyin:   list = ["[data-e2e='comment-item']", ".comment-item", "[class*='commentItem']"]
        case .kuaishou: list = [".comment-item", "[class*='comment']"]
        case .xhs:      list = [".comment-item", ".comment-inner", "[class*='commentItem']"]
        case .weibo:    list = [".item-content", ".card .m-text-cut"]
        default:        list = [".comment-item", ".reply-item"]
        }
        return "[" + list.map { "'" + $0 + "'" }.joined(separator: ",") + "]"
    }
}

// MARK: - 用 houmen 脚本驱动的采集 WebView

struct HoumenCollector: UIViewRepresentable {
    let platform: Platform
    let keyword: String
    let target: Int
    var startURL: String? = nil
    var drive: Bool = true                     // true=开始采集，false=只加载页面供登录
    @Binding var running: Bool
    let onBatch: ([Lead]) -> Void
    let onLog: (String) -> Void

    func makeCoordinator() -> Coord {
        Coord(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let uc = WKUserContentController()
        uc.add(context.coordinator, name: "ldr")
        cfg.userContentController = uc
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default()

        let key = platform.houmenKey ?? platform.rawValue
        let taskId = "ldr-\(Int(Date().timeIntervalSince1970))"

        // 协议桥：注入初始任务，再注入拦截脚本（顺序不能反）
        let bootstrap = """
        window.__houmenProtocolInitialTask = { platform: "\(key)", taskId: "\(taskId)" };
        """
        uc.addUserScript(WKUserScript(source: bootstrap,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true))
        uc.addUserScript(WKUserScript(source: HoumenJS.protocolCapture(),
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false))

        // DOM 采集脚本
        let collector = (platform == .xhs) ? HoumenJS.collectorXHS() : HoumenJS.collectorIOS()
        uc.addUserScript(WKUserScript(source: collector,
                                      injectionTime: .atDocumentEnd,
                                      forMainFrameOnly: true))

        // 登录模式下自动点「登录」按钮
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
        context.coordinator.taskId = taskId

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
        private var round = 0
        private var seen = Set<String>()
        private var got = 0
        private var phase = 0        // 0=准备搜索 1=滚动搜索 2=进详情 3=读评论
        private var openedVideos = 0

        init(_ p: HoumenCollector) { parent = p }

        func stop() {
            timer?.invalidate(); timer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if parent.startURL != nil {
                parent.onLog("页面已加载（登录模式）")
                return
            }
            parent.onLog("页面已加载，启动 houmen 采集器…")
            startDriving()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLog("加载失败：\(error.localizedDescription)")
        }

        private func startDriving() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }

        private func js(_ code: String, _ done: @escaping (Any?) -> Void) {
            webView?.evaluateJavaScript(code) { result, err in
                if let err = err {
                    self.parent.onLog("JS 错误：\(err.localizedDescription)")
                    done(nil); return
                }
                done(result)
            }
        }

        private func callCollector(_ command: String, _ done: @escaping ([String: Any]?) -> Void) {
            let fn = (parent.platform == .xhs) ? "collectXiaohongshuPage" : "collectAudioPage"
            let kw = parent.keyword.replacingOccurrences(of: "\"", with: "\\\"")
            let code = """
            (function(){
              try {
                if (typeof \(fn) !== 'function') return JSON.stringify({state:'blocked',message:'采集器未注入'});
                return JSON.stringify(\(fn)({
                  command: "\(command)",
                  keyword: "\(kw)",
                  maxCandidates: 20,
                  maxComments: \(parent.target),
                  sourceWindowDays: 7,
                  industry: ""
                }) || {});
              } catch (e) { return JSON.stringify({state:'blocked',message:'JS异常:'+e}); }
            })();
            """
            js(code) { result in
                guard let s = result as? String,
                      let d = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    done(nil); return
                }
                done(obj)
            }
        }

        private func readProtocol(_ done: @escaping ([String: Any]?) -> Void) {
            guard let key = parent.platform.houmenKey else { done(nil); return }
            let code = """
            (function(){
              try {
                if (!window.__houmenProtocol) return 'null';
                return JSON.stringify(window.__houmenProtocol.read({
                  platform: "\(key)",
                  sourceUrl: location.href
                }) || {});
              } catch (e) { return 'null'; }
            })();
            """
            js(code) { result in
                guard let s = result as? String, s != "null", s != "",
                      let d = s.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    done(nil); return
                }
                done(obj)
            }
        }

        private func tick() {
            round += 1
            if got >= parent.target || round > 90 {
                finish(); return
            }

            switch phase {
            case 0:
                callCollector("prepare_search") { st in
                    guard let st = st else { return }
                    let state = st["state"] as? String ?? ""
                    if state == "blocked" {
                        let msg = st["message"] as? String ?? "被拦截"
                        self.parent.onLog("抖音/小红书：\(msg)")
                        if (st["code"] as? String) == "login" {
                            self.parent.onLog("需要登录：点左上角「① 登录页」")
                            self.finish()
                        } else {
                            self.phase = 1     // 继续尝试滚动
                        }
                        return
                    }
                    if state == "ready" {
                        self.parent.onLog("搜索页就绪（已确认最新排序）")
                        self.phase = 1
                    }
                }

            case 1:
                callCollector("search_advance") { st in
                    guard let st = st else { return }
                    let vids = (st["videos"] as? [[String: Any]]) ?? []
                    if !vids.isEmpty {
                        self.parent.onLog("搜索到 \(vids.count) 个候选视频")
                        self.phase = 2
                        self.openFirstVideo(vids)
                    } else if (st["state"] as? String) == "blocked" {
                        self.parent.onLog("搜索被拦截：\(st["message"] as? String ?? "")")
                        self.finish()
                    }
                }

            case 2:
                // 进详情后读评论
                readProtocol { page in
                    self.collectRows(page)
                }
                self.drainComments()

            case 3:
                readProtocol { page in self.collectRows(page) }

            default:
                break
            }
        }

        private func openFirstVideo(_ vids: [[String: Any]]) {
            guard openedVideos < 5 else { finish(); return }
            guard let url = vids[min(openedVideos, vids.count - 1)]["sourceUrl"] as? String,
                  !url.isEmpty else { finish(); return }
            openedVideos += 1
            parent.onLog("打开视频 \(openedVideos)：\(url.suffix(24))")
            phase = 3
            if let u = URL(string: url) {
                webView?.load(URLRequest(url: u))
            }
        }

        /// 反复调用 read 命令让页面滚动加载评论，协议桥自动收集
        private func drainComments() {
            guard phase == 3 else { return }
            callCollector("read") { _ in }
            callCollector("advance") { _ in }
        }

        private func collectRows(_ page: [String: Any]?) {
            guard let page = page else { return }
            let rows = (page["rows"] as? [[String: Any]])
                ?? (page["comments"] as? [[String: Any]])
                ?? []

            var batch: [Lead] = []
            for r in rows {
                let text = (r["text"] as? String) ?? (r["content"] as? String) ?? ""
                guard text.count >= 2 else { continue }
                let id = (r["id"] as? String) ?? "\(text.prefix(24))"
                if seen.contains(id) { continue }
                seen.insert(id)

                let (score, tags, contact) = RadarScorer.score(text, industry: "空调/家电")
                guard score > 0 else { continue }

                var lead = Lead(platform: parent.platform.rawValue,
                                uid: (r["userId"] as? String) ?? id,
                                name: (r["name"] as? String) ?? "匿名",
                                profileURL: (r["profileUrl"] as? String) ?? "",
                                text: text, comments: 1, score: score,
                                tags: tags, contact: contact,
                                postTitle: parent.keyword,
                                videoURL: (r["sourceUrl"] as? String) ?? "",
                                createdAt: 0)
                lead.bio = (r["bio"] as? String) ?? ""
                lead.avatar = (r["avatar"] as? String) ?? ""
                lead.city = (r["ipLocation"] as? String) ?? (r["city"] as? String) ?? ""
                lead.isQuestion = QuestionDetector.isQuestion(text)

                if let best = BioParser.best(BioParser.extract(lead.bio)) {
                    lead.contact = best
                    lead.score = min(100, lead.score + 25)
                    if !lead.tags.contains("简介有联系方式") { lead.tags.append("简介有联系方式") }
                }
                batch.append(lead)
            }

            if !batch.isEmpty {
                got += batch.count
                parent.onLog("捕获 \(batch.count) 条（累计 \(got)）")
                DispatchQueue.main.async { self.parent.onBatch(batch) }
            }

            if let paging = page["paging"] as? [String: Any],
               let more = paging["hasMore"] as? Bool, more {
                callCollector("advance") { _ in }
            }
            if page["endOfComments"] as? Bool == true {
                parent.onLog("该视频评论已到底")
                if openedVideos < 5 { phase = 1 } else { finish() }
            }
        }

        private func finish() {
            stop()
            DispatchQueue.main.async { self.parent.running = false }
            parent.onLog("采集结束，共 \(got) 条")
        }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {}
    }
}
