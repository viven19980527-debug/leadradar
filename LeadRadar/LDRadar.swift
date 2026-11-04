import Foundation

// MARK: - 数据模型

struct Lead: Identifiable, Codable {
    var id: String { "\(platform)_\(uid)" }
    let platform: String          // bilibili
    let uid: String
    var name: String
    var profileURL: String
    var text: String
    var comments: Int
    var score: Int
    var tags: [String]
    var contact: String
    var postTitle: String
    var videoURL: String
    var createdAt: Int

    enum CodingKeys: String, CodingKey {
        case platform, uid, name, profileURL, text, comments, score, tags, contact, postTitle, videoURL, createdAt
    }
}

struct Video: Codable, Identifiable {
    var id: String { aid }
    let aid: String
    let bvid: String
    let title: String
    let url: String
    let comments: Int
}

// MARK: - 意图打分（与 PC 端同一套规则）

enum RadarScorer {

    static let phone = try! NSRegularExpression(pattern: "(?<!\\d)1[3-9]\\d{9}(?!\\d)")
    static let wechat = try! NSRegularExpression(pattern: "(?:微信|vx|VX|v信|威信|加v|加V)\\s*[：:＝=]?\\s*([A-Za-z0-9_\\-]{5,20})")
    static let vColon = try! NSRegularExpression(pattern: "(?:^|[\\s，。])[vV]\\s*[：:]\\s*([A-Za-z0-9_\\-]{5,20})")
    static let qq = try! NSRegularExpression(pattern: "(?:扣扣|QQ|qq)\\s*[：:]?\\s*(\\d{5,12})")

    struct Dict {
        let buy: [String]
        let compare: [String]
        let need: [String]
        let negative: [String]
        let urgent: [String]
        let tags: [(String, [String])]
    }

    static let ac = Dict(
        buy: ["多少钱","价格","报价","什么价","几钱","问个价","怎么收费","优惠","哪里买","在哪买","哪有卖",
              "求链接","求地址","有货吗","现货","想买","要买","打算买","准备买","准备装","想装","要装","下单",
              "入手","包安装","包含安装","上门安装","能上门","找师傅","求师傅","求施工","私信我","留个联系",
              "加个微信","加微信","微信多少","怎么联系","联系方式","求介绍","谁做这个","求带","值得入手",
              "入手吗","要不要装","打算装","准备换","想换新","求个价","私我","报个价","包安装吗","能开发票",
              "多久上门","今天能来","上门费","求报价单","怎么下单","支持分期","有意向","求购","批发价"],
        compare: ["买哪个","哪个好","选哪个","怎么选","值得买","推荐","求推荐","推荐一下","推荐个","哪款",
                  "对比","差别大吗","性价比","预算","适合","够用吗","匹数","一拖几","风管机","中央空调","壁挂",
                  "怎么装","装在","能装吗","层高","吊顶","出风口","静音吗","费电吗"],
        need: ["不制冷","不制热","制冷差","漏水","噪音大","异响","坏了","维修","加氟","移机","清洗","保养",
               "安装费","拆机","漏氟","跳闸","遥控失灵","外机不转","不启动","异味","结冰","报故障","维修费",
               "上门维修","换新机","旧机回收"],
        negative: ["同行","招代理","招学徒","刷单","兼职","日结","免费送","白嫖","骗子","投诉","差评","维权",
                   "举报","退款","退货","翻车","别买","不要买","垃圾","避雷","踩坑","上当","广告"],
        urgent: ["急","今天","明天","这周","本周","马上","现在就","尽快","年前","月初"],
        tags: [("询价", ["多少钱","价格","报价","什么价","几钱","问个价","怎么收费"]),
               ("求推荐", ["求推荐","推荐","哪个好","买哪个","怎么选","哪款"]),
               ("求安装", ["安装","师傅","上门","施工","包安装"]),
               ("求维修", ["不制冷","漏水","噪音","维修","加氟","移机","清洗","坏了"]),
               ("求联系", ["私信","联系","加微信","微信多少","留个联系"]),
               ("急单", ["急","今天","明天","马上","尽快"])]
    )

    static let audio = Dict(
        buy: ["多少钱","价格","报价","什么价","几钱","问个价","怎么卖","优惠","哪里买","在哪买","哪有卖",
              "求链接","求地址","有货吗","现货","想买","要买","打算买","准备买","想入","入手","下单","预定",
              "私信我","留个联系","加个微信","加微信","微信多少","怎么联系","联系方式","求介绍","求带",
              "值得入手","入手吗","求个价","私我","报个价","能试听吗","可以试听","包邮吗","能开发票",
              "有意向","求购","批发价","量大","团购价","求推荐店","哪里有卖","求渠道"],
        compare: ["哪个好","买哪个","选哪个","怎么选","值得买","推荐","求推荐","推荐一下","推荐个","哪款",
                  "对比","差别大吗","性价比","预算","适合","够用吗","入门","进阶","声音怎么样","低音","解析",
                  "推力","搭配","书架箱","落地箱","功放","胆机","蓝牙音箱","回音壁","家庭影院","全景声","hifi","HiFi"],
        need: ["坏了","杂音","失真","一边不响","没声音","破音","电流声","维修","换喇叭","换线","煲机","调音",
               "接电视","接电脑","接手机","连不上","断连","延迟"],
        negative: ["同行","招代理","招学徒","刷单","兼职","日结","免费送","白嫖","骗子","假货","水货","翻新",
                   "投诉","差评","维权","举报","退款","退货","翻车","别买","不要买","智商税","避雷","踩坑","广告"],
        urgent: ["急","今天","明天","这周","本周","马上","现在就","尽快","双11","618"],
        tags: [("询价", ["多少钱","价格","报价","什么价","几钱","怎么卖","优惠"]),
               ("求推荐", ["求推荐","推荐","哪个好","买哪个","怎么选","哪款","入门"]),
               ("求试听", ["试听","能听","去店里","体验"]),
               ("求搭配", ["搭配","功放","推力","推得动","配什么"]),
               ("求联系", ["私信","联系","加微信","微信多少","留个联系"]),
               ("急单", ["急","今天","明天","马上","尽快","双11","618"])]
    )

    static func dict(for industry: String) -> Dict {
        industry.contains("音响") || industry.contains("影音") ? audio : ac
    }

    static func score(_ text: String, industry: String) -> (Int, [String], String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return (0, [], "") }
        let d = dict(for: industry)
        var s = 0
        var tags: [String] = []
        var contact = ""

        let buy = d.buy.filter { t.contains($0) }
        if !buy.isEmpty { s += min(45, 15 * buy.count + 10) }

        let cmp = d.compare.filter { t.contains($0) }
        if !cmp.isEmpty { s += min(30, 10 * cmp.count + 5) }

        let need = d.need.filter { t.contains($0) }
        if !need.isEmpty { s += min(30, 12 * need.count + 6) }

        let neg = d.negative.filter { t.contains($0) }
        if !neg.isEmpty { s -= min(50, 20 * neg.count) }

        // 联系方式
        if let m = firstMatch(phone, t) {
            s += 40
            contact = "phone:" + m
        } else if let m = firstMatch(wechat, t, group: 1) {
            s += 35
            contact = "wechat:" + m
        } else if let m = firstMatch(vColon, t, group: 1) {
            s += 30
            contact = "v:" + m
        } else if let m = firstMatch(qq, t, group: 1) {
            s += 25
            contact = "qq:" + m
        }

        if !d.urgent.filter({ t.contains($0) }).isEmpty { s += 15 }

        for (tag, words) in d.tags where words.contains(where: { t.contains($0) }) {
            tags.append(tag)
        }

        // 高意向兜底
        if contact.isEmpty {
            if t.count > 120 { s = min(s, 70) }
            if buy.count < 2 { s = min(s, 78) }
        }
        if t.count < 6 { s -= 5 }
        if t.hasPrefix("回复 @") && buy.isEmpty { s -= 5 }

        return (max(0, min(100, s)), tags, contact)
    }

    private static func firstMatch(_ rx: NSRegularExpression, _ s: String, group: Int = 0) -> String? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }
}

// MARK: - B 站客户端（wbi 签名，实时联网）

@MainActor
final class BiliClient: ObservableObject {

    @Published var running = false
    @Published var progress = ""
    @Published var leads: [Lead] = []
    @Published var videos: [Video] = []
    @Published var scannedComments = 0
    @Published var errorText = ""

    private var mixinKey = ""
    private let session: URLSession
    private static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    // 官方混排表
    private static let tab: [Int] = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52]

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = ["User-Agent": BiliClient.ua, "Referer": "https://www.bilibili.com/"]
        session = URLSession(configuration: cfg)
    }

    // MARK: 签名
    private func md5(_ s: String) -> String {
        let d = Insecure.MD5.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    private func loadMixinKey() async throws {
        if !mixinKey.isEmpty { return }
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/nav") else { return }
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let wbi = d["wbi_img"] as? [String: Any],
              let img = wbi["img_url"] as? String, let sub = wbi["sub_url"] as? String else { return }
        func key(_ u: String) -> String {
            let name = u.split(separator: "/").last.map(String.init) ?? u
            return name.split(separator: ".").first.map(String.init) ?? name
        }
        let raw = key(img) + key(sub)
        guard raw.count >= 64 else { return }
        let arr = Array(raw)
        mixinKey = String((0..<32).map { arr[BiliClient.tab[$0]] })
    }

    private func signed(_ params: [String: String]) -> String {
        var p = params
        p["wts"] = String(Int(Date().timeIntervalSince1970))
        let sorted = p.sorted { $0.key < $1.key }
        let query = sorted.map { k, v in
            let clean = v.filter { !"!'()*".contains($0) }
            return "\(k)=\(clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clean)"
        }.joined(separator: "&")
        let rid = md5(query + mixinKey)
        return query + "&w_rid=" + rid
    }

    private func get(_ urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { return [:] }
        let (data, _) = try await session.data(from: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: 主流程：关键词 → 实时抓取
    func search(keyword: String, pages: Int = 2, industry: String) async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        running = true
        errorText = ""
        leads = []
        videos = []
        scannedComments = 0
        defer { running = false }

        do {
            try await loadMixinKey()
            progress = "搜索视频…"

            var vids: [Video] = []
            for page in 1...max(1, pages) {
                let q = signed(["search_type": "video", "keyword": kw, "page": String(page),
                                "page_size": "20", "order": "totalrank"])
                let j = try await get("https://api.bilibili.com/x/web-interface/wbi/search/type?" + q)
                guard let data = j["data"] as? [String: Any],
                      let arr = data["result"] as? [[String: Any]] else { break }
                for it in arr {
                    let aid = String(it["aid"] as? Int ?? 0)
                    let bvid = it["bvid"] as? String ?? ""
                    let title = (it["title"] as? String ?? "")
                        .replacingOccurrences(of: "<em class=\"keyword\">", with: "")
                        .replacingOccurrences(of: "</em>", with: "")
                    let cnt = (it["review"] as? Int) ?? (it["video_review"] as? Int) ?? 0
                    vids.append(Video(aid: aid, bvid: bvid, title: title,
                                      url: "https://www.bilibili.com/video/\(bvid)", comments: cnt))
                }
                if arr.isEmpty { break }
            }

            vids = vids.filter { $0.comments >= 5 }
            videos = vids
            guard !vids.isEmpty else {
                errorText = "没搜到有评论的视频，换个关键词试试"
                progress = ""
                return
            }

            var byAuthor: [String: Lead] = [:]
            for (i, v) in vids.enumerated() {
                progress = "抓评论 \(i+1)/\(vids.count)：\(v.title.prefix(14))"
                let cs = try await comments(aid: v.aid)
                scannedComments += cs.count
                for c in cs {
                    let (sc, tags, contact) = RadarScorer.score(c.text, industry: industry)
                    guard sc > 0 else { continue }
                    let key = c.uid
                    if var old = byAuthor[key] {
                        old.comments += 1
                        if sc > old.score {
                            old.score = sc; old.text = c.text
                            old.tags = tags; old.contact = contact.isEmpty ? old.contact : contact
                        }
                        byAuthor[key] = old
                    } else {
                        byAuthor[key] = Lead(platform: "bilibili", uid: c.uid, name: c.name,
                                             profileURL: "https://space.bilibili.com/\(c.uid)",
                                             text: c.text, comments: 1, score: sc, tags: tags,
                                             contact: contact, postTitle: v.title,
                                             videoURL: v.url, createdAt: 0)
                    }
                }
                leads = byAuthor.values.sorted { $0.score > $1.score }
            }
            progress = "完成：\(scannedComments) 条评论 → \(leads.count) 条线索"
        } catch {
            errorText = "请求失败：\(error.localizedDescription)"
            progress = ""
        }
    }

    private struct Cmt { let uid: String; let name: String; let text: String }

    private func comments(aid: String) async throws -> [Cmt] {
        var out: [Cmt] = []
        var seen = Set<String>()

        func add(_ rp: [String: Any]) {
            guard let rpid = rp["rpid"] as? Int, !seen.contains(String(rpid)) else { return }
            seen.insert(String(rpid))
            let mid = String((rp["mid"] as? Int) ?? ((rp["member"] as? [String: Any])?["mid"] as? Int) ?? 0)
            let name = (rp["member"] as? [String: Any])?["uname"] as? String ?? "匿名"
            let text = ((rp["content"] as? [String: Any])?["message"] as? String) ?? ""
            out.append(Cmt(uid: mid, name: name, text: text))
        }

        // 一级评论
        let q = signed(["oid": aid, "type": "1", "mode": "3",
                        "pagination_str": "{\"offset\":\"\"}", "plat": "1", "web_location": "1315875"])
        let j = try await get("https://api.bilibili.com/x/v2/reply/wbi/main?" + q)
        let roots = ((j["data"] as? [String: Any])?["replies"] as? [[String: Any]]) ?? []
        roots.forEach(add)

        // 子评论（每页 20，可多页）
        for r in roots {
            guard let rpid = r["rpid"] as? Int else { continue }
            for pn in 1...3 {
                let q2 = "type=1&oid=\(aid)&root=\(rpid)&pn=\(pn)&ps=20&sort=2"
                let j2 = try await get("https://api.bilibili.com/x/v2/reply/reply?" + q2)
                let reps = ((j2["data"] as? [String: Any])?["replies"] as? [[String: Any]]) ?? []
                if reps.isEmpty { break }
                let before = out.count
                reps.forEach(add)
                if out.count == before { break }
                let total = ((j2["data"] as? [String: Any])?["page"] as? [String: Any])?["count"] as? Int ?? 0
                if pn * 20 >= total { break }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            if out.count > 120 { break }
        }
        return out
    }
}
