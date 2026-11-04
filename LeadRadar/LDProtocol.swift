import Foundation

// MARK: - 协议级评论解析（移植自 protocol-capture.js 的工程思路）
//
// 三个关键机制：
//   1. 端点白名单映射：只解析「已知是评论接口」的响应，其他一律丢弃
//   2. 打分兜底：端点未知时，按「分页字段 / 路径含 comment / 样本命中数 / 数组长度 / 嵌套深度」打分定位
//   3. 分页三层合并：cursor / has_more / total 可能分散在不同嵌套层，逐层找
//
// 另有两点防坑：
//   · 大整数保护：抖音 comment id 超过 JS/JSON 安全整数范围，先转成字符串再解析
//   · 未知分页值保持 unknown，绝不当成「已结束」

struct CapturedComment {
    let id: String
    let parentID: String
    let userID: String
    let name: String
    let handle: String
    let text: String
    let likeCount: Int
    let createTime: String
    let sourceID: String
    let sourceURL: String
    var bio: String = ""
    var avatar: String = ""
    var city: String = ""
}

struct CapturePage {
    let comments: [CapturedComment]
    let cursor: String
    let hasMore: Bool
    let total: Int
}

enum CaptureError: Error {
    case unsupportedEndpoint(String)
    case businessError(String)
    case sourceMismatch(String)
    case empty
}

enum LDProtocol {

    // MARK: 端点 → 数组路径
    // 与 protocol-capture.js 的 ROOT_PATHS 对应

    private static let douyinPaths: [String: [String]] = [
        "/aweme/v1/web/comment/list":       ["comments"],
        "/aweme/v1/web/comment/list/reply": ["comments"],
        "/aweme/v1/web/aweme/detail":       ["aweme_detail"],
    ]
    private static let xhsPaths: [String: [String]] = [
        "/api/sns/web/v1/comment/page":     ["comments", "data.comments"],
        "/api/sns/web/v1/comment/sub/page": ["comments", "data.comments"],
        "/api/sns/web/v1/feed":             ["items", "data.items"],
    ]
    private static let weiboPaths: [String: [String]] = [
        "/comments/hotflow":  ["data", "data.data"],
        "/comments/show":     ["data"],
        "/api/container/getIndex": ["data.cards"],
    ]

    static func endpoint(for platform: String, url: URL) -> String? {
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        switch platform {
        case "douyin":   return douyinPaths[path] != nil ? path : nil
        case "xhs":      return xhsPaths[path] != nil ? path : nil
        case "weibo":    return weiboPaths[path] != nil ? path : nil
        default:         return nil
        }
    }

    private static func rootPaths(platform: String, endpoint: String) -> [String] {
        switch platform {
        case "douyin": return douyinPaths[endpoint] ?? []
        case "xhs":    return xhsPaths[endpoint] ?? []
        case "weibo":  return weiboPaths[endpoint] ?? []
        default:       return []
        }
    }

    // MARK: 大整数保护

    /// 把 JSON 文本里超过 15 位的整数加上引号，避免 Double 精度丢失
    static func quoteBigIntegers(_ s: String) -> String {
        guard let rx = try? NSRegularExpression(
            pattern: "([:\\[,]\\s*)(-?\\d{16,})(\\s*[,}\\]])") else { return s }
        let ns = s as NSString
        var out = s
        let matches = rx.matches(in: s, range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            guard m.numberOfRanges >= 4 else { continue }
            let big = ns.substring(with: m.range(at: 2))
            let repl = "\"\(big)\""
            let full = ns.substring(with: m.range)
            let fixed = full.replacingOccurrences(of: big, with: repl)
            if let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: fixed)
            }
        }
        return out
    }

    // MARK: 通用取值

    private static func str(_ v: Any?) -> String {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case let d as Double: return String(Int64(d))
        case let i as Int: return String(i)
        default: return ""
        }
    }

    private static func pick(_ d: [String: Any], _ keys: [String]) -> Any? {
        for k in keys { if let v = d[k] { return v } }
        return nil
    }

    private static func nested(_ d: [String: Any], _ path: String) -> Any? {
        var cur: Any = d
        for part in path.split(separator: ".") {
            guard let dict = cur as? [String: Any], let next = dict[String(part)] else { return nil }
            cur = next
        }
        return cur
    }

    // MARK: 字段键（多平台统一）

    private static let TEXT_KEYS  = ["text", "content", "comment_text", "message", "note"]
    private static let ID_KEYS    = ["cid", "comment_id", "id", "commentId", "rpid"]
    private static let USER_KEYS  = ["user", "user_info", "userInfo", "author", "member"]
    private static let NAME_KEYS  = ["nickname", "screen_name", "name", "user_name", "uname"]
    private static let UID_KEYS   = ["uid", "user_id", "userId", "mid", "id_str", "sec_uid"]
    private static let HANDLE_KEYS = ["unique_id", "short_id", "red_id", "douyin_id", "handle"]
    private static let LIKE_KEYS  = ["digg_count", "like_count", "likeCount", "like", "liked_count"]
    private static let TIME_KEYS  = ["create_time", "createTime", "created_at", "time", "ctime"]
    private static let REPLY_KEYS = ["reply_comment", "replies", "sub_comments", "subComments"]
    private static let BIO_KEYS   = ["signature", "sign", "desc", "description", "introduction", "bio"]
    private static let AVATAR_KEYS = ["avatar", "avatar_url", "avatarUrl", "avatar_larger", "profile_image_url", "head_img"]
    private static let CITY_KEYS  = ["ip_label", "ip_location", "ipLocation", "location", "region"]

    // MARK: 单条评论识别与映射

    private static func looksLikeComment(_ item: [String: Any]) -> Bool {
        var hasText = false
        for k in TEXT_KEYS where !str(item[k]).isEmpty { hasText = true; break }
        guard hasText else { return false }

        for k in USER_KEYS where item[k] is [String: Any] { return true }
        for k in NAME_KEYS where !str(item[k]).isEmpty { return true }
        for k in UID_KEYS where !str(item[k]).isEmpty { return true }
        return false
    }

    private static func mapComment(_ item: [String: Any], platform: String,
                                   sourceID: String, sourceURL: String,
                                   parentID: String = "") -> CapturedComment? {
        var user: [String: Any] = [:]
        for k in USER_KEYS {
            if let u = item[k] as? [String: Any] { user = u; break }
        }
        var text = ""
        for k in TEXT_KEYS where !str(item[k]).isEmpty { text = str(item[k]); break }
        guard !text.isEmpty else { return nil }

        var name = ""
        for k in NAME_KEYS where !str(user[k]).isEmpty { name = str(user[k]); break }
        if name.isEmpty { for k in NAME_KEYS where !str(item[k]).isEmpty { name = str(item[k]); break } }

        var uid = ""
        for k in UID_KEYS where !str(user[k]).isEmpty { uid = str(user[k]); break }
        if uid.isEmpty { for k in UID_KEYS where !str(item[k]).isEmpty { uid = str(item[k]); break } }

        guard !name.isEmpty || !uid.isEmpty else { return nil }

        var handle = ""
        for k in HANDLE_KEYS where !str(user[k]).isEmpty { handle = str(user[k]); break }

        var cid = ""
        for k in ID_KEYS where !str(item[k]).isEmpty { cid = str(item[k]); break }

        var like = 0
        for k in LIKE_KEYS {
            if let v = item[k] as? NSNumber { like = v.intValue; break }
            if let v = item[k] as? Int { like = v; break }
        }

        var created = ""
        for k in TIME_KEYS where !str(item[k]).isEmpty { created = str(item[k]); break }

        if cid.isEmpty { cid = "\(uid)_\(text.prefix(24))" }

        var bio = ""
        for k in BIO_KEYS where !str(user[k]).isEmpty { bio = str(user[k]); break }
        if bio.isEmpty { for k in BIO_KEYS where !str(item[k]).isEmpty { bio = str(item[k]); break } }

        var avatar = ""
        for k in AVATAR_KEYS where !str(user[k]).isEmpty { avatar = str(user[k]); break }
        if avatar.isEmpty {
            if let imgs = user["image_urls"] as? [String], let first = imgs.first { avatar = first }
        }

        var city = IPLocation.find(in: user)
        if city.isEmpty { city = IPLocation.find(in: item) }

        return CapturedComment(id: cid, parentID: parentID, userID: uid, name: name,
                               handle: handle, text: text, likeCount: like,
                               createTime: created, sourceID: sourceID, sourceURL: sourceURL,
                               bio: bio, avatar: avatar, city: city)
    }

    // MARK: 打分兜底：在未知 JSON 里找评论数组

    private static func scoreArray(_ arr: [Any], path: String, parent: [String: Any]?) -> Int {
        let sample = Array(arr.prefix(5))
        let matched = sample.compactMap { $0 as? [String: Any] }.filter(looksLikeComment).count
        guard matched > 0 else { return 0 }

        var score = 0
        if let p = parent, hasPaging(p) { score += 500 }
        if path.lowercased().contains("comment") { score += 200 }
        score += matched * 10
        score += min(arr.count, 50)
        score -= path.split(separator: ".").count * 5
        return score
    }

    private static func hasPaging(_ d: [String: Any]) -> Bool {
        for k in ["cursor", "next_cursor", "nextCursor", "has_more", "hasMore",
                  "max_id", "pcursor", "total", "comment_count"] where d[k] != nil { return true }
        return false
    }

    private static func findCommentArray(_ root: Any) -> (array: [Any], path: String)? {
        var best: (score: Int, array: [Any], path: String)? = nil
        var queue: [(Any, String, [String: Any]?, Int)] = [(root, "$", nil, 0)]

        while let (node, path, parent, depth) = queue.first {
            queue.removeFirst()
            if depth > 8 { continue }

            if let arr = node as? [Any] {
                let sc = scoreArray(arr, path: path, parent: parent)
                if sc > 0, best == nil || sc > best!.score {
                    best = (sc, arr, path)
                }
                for (i, v) in arr.prefix(6).enumerated() {
                    queue.append((v, "\(path)[\(i)]", nil, depth + 1))
                }
                continue
            }
            if let d = node as? [String: Any] {
                for (k, v) in d {
                    queue.append((v, "\(path).\(k)", d, depth + 1))
                }
            }
        }
        guard let b = best else { return nil }
        return (b.array, b.path)
    }

    // MARK: 分页三层合并

    private static func pagingValue(_ layers: [[String: Any]], _ keys: [String]) -> Any? {
        for layer in layers {
            for k in keys where layer[k] != nil { return layer[k] }
        }
        return nil
    }

    private static func collectLayers(_ root: [String: Any]) -> [[String: Any]] {
        var layers: [[String: Any]] = [root]
        if let d = root["data"] as? [String: Any] {
            layers.append(d)
            if let d2 = d["data"] as? [String: Any] { layers.append(d2) }
        }
        return layers
    }

    // MARK: 主入口

    static func parse(body: String, platform: String, captureURL: String) throws -> CapturePage {
        let cleaned = quoteBigIntegers(body)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw CaptureError.empty
        }

        var root: [String: Any] = [:]
        if let d = json as? [String: Any] {
            root = d
        } else if let arr = json as? [Any] {
            root = ["list": arr]
        }

        // 业务错误
        for k in ["status_code", "code"] {
            if let v = root[k] as? NSNumber, v.intValue != 0 {
                let msg = str(root["status_msg"] ?? root["message"] ?? root["msg"])
                throw CaptureError.businessError(msg.isEmpty ? "code=\(v)" : msg)
            }
        }

        // 来源标识
        let url = URL(string: captureURL)
        let sourceID = sourceIDFrom(url: url, platform: platform, root: root)
        let sourceURL = sourceLink(platform: platform, sourceID: sourceID)

        // 定位评论数组：优先端点白名单，其次打分兜底
        var arrays: [[Any]] = []
        if let u = url, let ep = endpoint(for: platform, url: u) {
            for p in rootPaths(platform: platform, endpoint: ep) {
                if let v = nested(root, p) as? [Any] { arrays.append(v) }
            }
            if arrays.isEmpty { throw CaptureError.unsupportedEndpoint(ep) }
        } else {
            if let found = findCommentArray(root) { arrays.append(found.array) }
        }
        guard !arrays.isEmpty else { throw CaptureError.empty }

        // 映射（含子评论展开）
        var out: [CapturedComment] = []
        var seen = Set<String>()

        func add(_ item: [String: Any], parent: String) {
            guard let c = mapComment(item, platform: platform, sourceID: sourceID,
                                     sourceURL: sourceURL, parentID: parent) else { return }
            if seen.contains(c.id) { return }
            seen.insert(c.id)
            out.append(c)
            for k in REPLY_KEYS {
                if let subs = item[k] as? [[String: Any]] {
                    for s in subs { add(s, parent: c.id) }
                }
            }
        }

        for arr in arrays {
            for el in arr {
                if let d = el as? [String: Any] { add(d, parent: "") }
                else if let nestedArr = el as? [Any] {
                    for x in nestedArr {
                        if let d = x as? [String: Any] { add(d, parent: "") }
                    }
                }
            }
        }

        // 分页
        let layers = collectLayers(root)
        let cursor = str(pagingValue(layers, ["cursor", "next_cursor", "nextCursor", "max_id", "pcursor"]))
        let hasMoreRaw = pagingValue(layers, ["has_more", "hasMore"])
        var hasMore = false
        if let n = hasMoreRaw as? NSNumber { hasMore = n.boolValue }
        else if let b = hasMoreRaw as? Bool { hasMore = b }
        else if let s = hasMoreRaw as? String { hasMore = (s == "1" || s.lowercased() == "true") }
        var total = 0
        if let n = pagingValue(layers, ["total", "comment_count"]) as? NSNumber { total = n.intValue }

        return CapturePage(comments: out, cursor: cursor, hasMore: hasMore, total: total)
    }

    // MARK: 来源标识

    private static func sourceIDFrom(url: URL?, platform: String, root: [String: Any]) -> String {
        if let u = url {
            let parts = u.pathComponents
            if let idx = parts.firstIndex(where: { ["video", "note", "explore", "detail"].contains($0) }),
               idx + 1 < parts.count {
                return parts[idx + 1]
            }
            if platform == "douyin", let aweme = u.query?.components(separatedBy: "aweme_id=").last,
               u.query?.contains("aweme_id=") == true {
                return aweme.components(separatedBy: "&").first ?? ""
            }
        }
        for k in ["aweme_id", "note_id", "item_id", "id"] {
            if let v = root[k] as? String, !v.isEmpty { return v }
        }
        return ""
    }

    private static func sourceLink(platform: String, sourceID: String) -> String {
        guard !sourceID.isEmpty else { return "" }
        switch platform {
        case "douyin": return "https://www.douyin.com/video/\(sourceID)"
        case "xhs":    return "https://www.xiaohongshu.com/explore/\(sourceID)"
        case "weibo":  return "https://m.weibo.cn/detail/\(sourceID)"
        default:       return ""
        }
    }
}
