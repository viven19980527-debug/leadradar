import Foundation
import Vision
import UIKit

// MARK: - A1 提问者识别

enum QuestionDetector {

    /// 强疑问特征（这个人大概率在问、在求）
    private static let strongMarkers = [
        "多少钱", "多少钱啊", "价格多少", "怎么卖", "什么价", "几钱", "怎么收费",
        "哪里买", "在哪买", "哪有卖", "求推荐", "求推荐个", "推荐一下", "有推荐吗",
        "怎么联系", "联系方式", "加个微信", "微信多少", "私信我", "怎么找你",
        "有没有人", "有人知道", "求告知", "求解答", "求问", "请问",
        "能装吗", "能上门吗", "包安装吗", "有货吗", "还有货吗",
        "哪个好", "买哪个", "怎么选", "值得买吗", "值得入手吗",
    ]

    /// 弱疑问特征
    private static let weakMarkers = [
        "吗", "呢", "么", "怎么", "多少", "哪", "什么", "为啥", "为什么",
        "能不能", "可不可以", "需不需要", "要不要", "是不是", "有没有",
        "求", "想", "准备", "打算",
    ]

    static func isQuestion(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 3 else { return false }
        for m in strongMarkers where t.contains(m) { return true }

        // 弱特征：需要出现疑问标点，或 weak 命中 >= 2 个
        var weak = 0
        for m in weakMarkers where t.contains(m) { weak += 1 }
        if t.contains("?") || t.contains("？") { return weak >= 1 }
        return weak >= 2
    }
}

// MARK: - B1 简介 / 文本里的联系方式

struct ContactHit {
    let kind: String     // phone / wechat / qq / email / oa
    let value: String
    var label: String { "\(kind):\(value)" }
}

enum BioParser {

    private static let phoneRx = try! NSRegularExpression(pattern: "(?<!\\d)(1[3-9]\\d{9})(?!\\d)")
    private static let wechatRx = try! NSRegularExpression(
        pattern: "(?:微信|vx|v信|威信|薇信|加v|加V|V信|WX|wx)\\s*[：:＝=号]?\\s*([A-Za-z][A-Za-z0-9_\\-]{5,19})")
    private static let wechatRawRx = try! NSRegularExpression(
        pattern: "(?:^|[\\s，,。;；])([A-Za-z][A-Za-z0-9_\\-]{5,19})\\s*(?:$|[\\s，,。;；])")
    private static let qqRx = try! NSRegularExpression(pattern: "(?:QQ|扣扣|qq)\\s*[：:号]?\\s*(\\d{5,12})")
    private static let emailRx = try! NSRegularExpression(
        pattern: "([A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,})")
    private static let oaRx = try! NSRegularExpression(pattern: "(?:公众号|公众号搜索|关注公众号)\\s*[：:＝=]?\\s*([\\u4e00-\\u9fa5A-Za-z0-9_\\-]{2,20})")
    private static let telRx = try! NSRegularExpression(pattern: "(?<!\\d)(0\\d{2,3}-?\\d{7,8})(?!\\d)")

    static func extract(_ text: String) -> [ContactHit] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        var out: [ContactHit] = []
        var seen = Set<String>()

        func add(_ kind: String, _ value: String) {
            let key = "\(kind)_\(value)"
            guard !seen.contains(key), !value.isEmpty else { return }
            seen.insert(key)
            out.append(ContactHit(kind: kind, value: value))
        }

        func grab(_ rx: NSRegularExpression, kind: String, group: Int = 1) {
            for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges > group else { continue }
                let r = m.range(at: group)
                guard r.location != NSNotFound else { continue }
                add(kind, ns.substring(with: r))
            }
        }

        grab(phoneRx, kind: "phone", group: 1)
        grab(wechatRx, kind: "wechat", group: 1)
        grab(qqRx, kind: "qq", group: 1)
        grab(emailRx, kind: "email", group: 1)
        grab(oaRx, kind: "公众号", group: 1)
        grab(telRx, kind: "座机", group: 1)

        // 没写"微信"但有纯英数字符串 → 当作疑似微信号
        if !out.contains(where: { $0.kind == "wechat" }) {
            for m in wechatRawRx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard m.numberOfRanges > 1 else { continue }
                let r = m.range(at: 1)
                guard r.location != NSNotFound else { continue }
                let v = ns.substring(with: r)
                // 排除明显不是微信号的
                if v.lowercased().contains("http") { continue }
                if out.contains(where: { $0.value == v }) { continue }
                add("wechat?", v)
                break
            }
        }
        return out
    }

    /// 取第一个最值钱的联系方式（phone > wechat > qq > email > 公众号）
    static func best(_ hits: [ContactHit]) -> String? {
        let order = ["phone", "wechat", "qq", "email", "公众号", "座机", "wechat?"]
        for k in order {
            if let h = hits.first(where: { $0.kind == k }) { return h.label }
        }
        return nil
    }
}

// MARK: - B6 IP 属地

enum IPLocation {

    /// 从 JSON 里找属地字段（抖音 ip_label / 微博 ip_location / 通用 location）
    static func find(in dict: [String: Any]) -> String {
        for k in ["ip_label", "ip_location", "ipLocation", "location", "region", "city"] {
            if let s = dict[k] as? String, !s.isEmpty, s.count <= 20 { return s }
        }
        return ""
    }

    /// 归一化：去掉"省""市"等后缀，用于同城匹配
    static func normalize(_ s: String) -> String {
        var t = s
        for suffix in ["壮族自治区", "回族自治区", "维吾尔自治区", "自治区", "特别行政区",
                       "省", "市", "地区", "自治州"] {
            t = t.replacingOccurrences(of: suffix, with: "")
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let x = normalize(a), y = normalize(b)
        if x.isEmpty || y.isEmpty { return false }
        return x.contains(y) || y.contains(x)
    }
}

// MARK: - B3 头像 OCR（Vision，全离线）

enum AvatarOCR {

    static func download(_ urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// 识别图片文字；返回拼好的文本
    static func recognize(_ image: UIImage) async -> String {
        guard let cg = image.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                guard let obs = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: "")
                    return
                }
                let lines = obs.compactMap { $0.topCandidates(1).first?.string }
                cont.resume(returning: lines.joined(separator: " "))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { cont.resume(returning: "") }
            }
        }
    }

    /// 头像 URL → OCR → 联系方式
    static func contactFromAvatar(_ urlString: String) async -> String? {
        guard !urlString.isEmpty, let img = await download(urlString) else { return nil }
        let text = await recognize(img)
        guard !text.isEmpty else { return nil }
        let hits = BioParser.extract(text)
        return BioParser.best(hits)
    }
}

// MARK: - D3 话术生成

enum ScriptGenerator {

    /// 根据线索生成开场白（本地模板，不联网）
    static func opening(for lead: Lead, industry: String, city: String = "") -> String {
        let name = lead.name.isEmpty ? "你好" : "\(lead.name)你好"
        let tags = lead.tags.joined(separator: "/")
        let excerpt = lead.text.prefix(30)

        var body: String
        if lead.tags.contains("询价") {
            body = "看到你在评论区问「\(excerpt)」，我这边是做\(industry)的，给你报个实价，不玩虚的。"
        } else if lead.tags.contains("求安装") || lead.tags.contains("求维修") {
            body = "看到你在问「\(excerpt)」，我们师傅就在\(city.isEmpty ? "本地" : city)，上门看一眼不收钱，先给你说清楚问题再报价。"
        } else if lead.tags.contains("求推荐") {
            body = "看到你在挑「\(excerpt)」，我这边做了几年\(industry)，把你的户型和预算说一下，我给你两个方案对比，不合适也不勉强。"
        } else if lead.tags.contains("急单") {
            body = "看到你比较急「\(excerpt)」，今天能安排，先告诉我地址和大概情况。"
        } else {
            body = "看到你提到「\(excerpt)」，我这边专门做\(industry)，有需要可以问我，问价不收费。"
        }

        return "\(name)，\(body)"
    }

    /// 追问话术
    static func followUp(for lead: Lead, industry: String) -> String {
        if lead.tags.contains("询价") {
            return "方便说下平方数和楼层吗？我给你算个准价，含安装和辅材。"
        }
        if lead.tags.contains("求维修") {
            return "机器是什么牌子、用了几年？不制冷还是不启动？我大概能判断个方向。"
        }
        return "你大概什么时候要？我好安排时间。"
    }
}

// MARK: - D1/D2 一键触达

import SwiftUI

enum ContactActions {

    static func canCall(_ contact: String) -> Bool {
        contact.hasPrefix("phone:") || contact.hasPrefix("座机:")
    }

    static func phoneNumber(_ contact: String) -> String {
        contact.components(separatedBy: ":").last?
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    static func call(_ contact: String) {
        let num = phoneNumber(contact)
        guard !num.isEmpty, let url = URL(string: "tel://\(num)") else { return }
        UIApplication.shared.open(url)
    }

    /// 微信：先复制到剪贴板，再跳微信（微信不支持直接加好友深链）
    static func openWeChat(copying value: String) {
        UIPasteboard.general.string = value
        if let url = URL(string: "weixin://") {
            UIApplication.shared.open(url)
        }
    }

    static func copy(_ s: String) {
        UIPasteboard.general.string = s
    }
}
