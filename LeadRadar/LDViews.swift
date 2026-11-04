import SwiftUI
import UniformTypeIdentifiers

@main
struct LeadRadarApp: App {
    var body: some Scene {
        WindowGroup { RadarRoot() }
    }
}

import SwiftUI

// MARK: - 全平台聚合视图（替换原 LDViews 里的 RadarRoot）

struct RadarRoot: View {
    @StateObject var client = BiliClient()

    @AppStorage("industry") var industry = "空调/家电"
    @AppStorage("lastKeyword") var lastKeyword = ""
    @AppStorage("platforms") var platformsRaw = "bilibili"
    @State var keyword = ""
    @State var minScore = 0
    @State var showCSV = false
    @State var webPlatform: Platform? = nil
    @State var webRunning = false
    @State var logs: [String] = []
    @State var allLeads: [Lead] = []
    @State var groupMode = 0        // 0=平台 1=标签

    var enabledPlatforms: [Platform] {
        Platform.allCases.filter { platformsRaw.contains($0.rawValue) }
    }

    var filtered: [Lead] {
        allLeads.filter { $0.score >= minScore }
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection
                platformSection
                if !logs.isEmpty { logSection }
                if !filtered.isEmpty { resultSection }
                settingsSection
                if filtered.isEmpty && logs.isEmpty && client.errorText.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 34)).foregroundStyle(.secondary)
                            Text("还没有线索").font(.headline)
                            Text("输入关键词 → 勾选平台 → 一键全平台采集")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("获客雷达")
            .sheet(isPresented: $showCSV) { ShareSheet(items: [csvURL()]) }
            .sheet(item: $webPlatform, onDismiss: { openNextWeb() }) { p in
                WebCollectSheet(platform: p, keyword: keyword,
                                running: $webRunning,
                                onBatch: { batch in merge(batch) },
                                onLog: { logs.append($0) })
            }
        }
        .onAppear { if keyword.isEmpty { keyword = lastKeyword } }
    }

    private var settingsSection: some View {
        Section("设置与导出") {
            HStack {
                Text("行业词典")
                Spacer()
                Picker("", selection: $industry) {
                    Text("空调/家电").tag("空调/家电")
                    Text("音响/影音").tag("音响/影音")
                }
                .pickerStyle(.menu)
            }
            Button {
                showCSV = true
            } label: {
                Label("导出 CSV（\(filtered.count) 条）", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                allLeads = []
                logs = []
            } label: {
                Label("清空结果", systemImage: "trash")
            }
        }
    }

    // MARK: 搜索

    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("关键词，如：空调安装多少钱", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit { runAll() }
            }
            Button { runAll() } label: {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                    Text(webRunning || client.running ? "采集中…" : "一键全平台采集")
                        .font(.headline)
                    Spacer()
                    if webRunning || client.running { ProgressView() }
                }
            }
            .disabled(webRunning || client.running || keyword.trimmingCharacters(in: .whitespaces).isEmpty)

            Picker("最低分", selection: $minScore) {
                Text("全部").tag(0); Text("50+").tag(50); Text("70+").tag(70); Text("80+").tag(80)
            }.pickerStyle(.segmented)
        } footer: {
            Text("B站 走原生接口（无需登录）；微博/抖音/快手/小红书 用内置浏览器抓（首次可能需要在页面里登录一次）。")
                .font(.caption2)
        }
    }

    private var platformSection: some View {
        Section("平台") {
            ForEach(Platform.allCases) { p in
                Button {
                    toggle(p)
                } label: {
                    HStack {
                        Image(systemName: enabledPlatforms.contains(p) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(enabledPlatforms.contains(p) ? .blue : .secondary)
                        Text(p.name)
                        Spacer()
                        Text(p.native ? "原生" : "内置浏览器")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var logSection: some View {
        Section("采集日志") {
            ForEach(Array(logs.suffix(6).enumerated()), id: \.offset) { _, l in
                Text(l).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            if !client.progress.isEmpty {
                Text(client.progress).font(.caption2.monospaced()).foregroundStyle(.blue)
            }
        }
    }

    private var resultSection: some View {
        Group {
            Picker("分组", selection: $groupMode) {
                Text("按平台").tag(0); Text("按标签").tag(1)
            }.pickerStyle(.segmented)

            if groupMode == 0 {
                ForEach(Platform.allCases) { p in
                    let rows = filtered.filter { $0.platform == p.rawValue }
                    if !rows.isEmpty {
                        Section("\(p.name)（\(rows.count)）") {
                            ForEach(rows) { lead in
                                NavigationLink { LeadDetail(lead: lead) } label: { LeadRow(lead: lead) }
                            }
                        }
                    }
                }
            } else {
                ForEach(tagGroups, id: \.0) { pair in
                    Section("\(pair.0)（\(pair.1.count)）") {
                        ForEach(pair.1) { lead in
                            NavigationLink { LeadDetail(lead: lead) } label: { LeadRow(lead: lead) }
                        }
                    }
                }
            }
        }
    }

    private var tagGroups: [(String, [Lead])] {
        var map: [String: [Lead]] = [:]
        for l in filtered {
            let key = l.tags.first ?? "其他"
            map[key, default: []].append(l)
        }
        return map.map { ($0.key, $0.value.sorted { $0.score > $1.score }) }
                  .sorted { $0.1.count > $1.1.count }
    }

    // MARK: 动作

    private func toggle(_ p: Platform) {
        var set = Set(enabledPlatforms)
        if set.contains(p) { set.remove(p) } else { set.insert(p) }
        platformsRaw = set.map { $0.rawValue }.joined(separator: ",")
    }

    private func runAll() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }
        lastKeyword = kw
        allLeads = []
        logs = []

        // 待处理的 web 平台队列（按需逐个打开）
        webQueue = enabledPlatforms.filter { !$0.native }
        logs.append("待采集 web 平台：" + (webQueue.map { $0.name }.joined(separator: "、").isEmpty
                    ? "无" : webQueue.map { $0.name }.joined(separator: "、")))

        if enabledPlatforms.contains(.bilibili) {
            logs.append("B站：开始原生抓取…")
            Task {
                await client.search(keyword: kw, pages: 2, industry: industry)
                merge(client.leads)
                logs.append("B站：\(client.leads.count) 条线索")
                openNextWeb()
            }
        } else {
            openNextWeb()
        }
    }

    private func openNextWeb() {
        guard let next = webQueue.first else {
            logs.append("全部平台采集结束，共 \(allLeads.count) 条线索")
            return
        }
        webQueue.removeFirst()
        logs.append("\(next.name)：请在弹出页面里「先登录 → 再点开始采集」")
        webPlatform = next
    }

    private func merge(_ batch: [Lead]) {
        var map = Dictionary(uniqueKeysWithValues: allLeads.map { ($0.id, $0) })
        for l in batch {
            if var old = map[l.id] {
                old.comments += l.comments
                if l.score > old.score { old.score = l.score; old.text = l.text; old.tags = l.tags }
                if !l.contact.isEmpty { old.contact = l.contact }
                map[l.id] = old
            } else {
                map[l.id] = l
            }
        }
        allLeads = map.values.sorted { $0.score > $1.score }
    }

    private func csvURL() -> URL {
        var s = "平台,昵称,UID,评分,标签,联系方式,评论,来源\n"
        for l in filtered {
            let t = l.text.replacingOccurrences(of: "\"", with: "\"\"")
            s += "\(l.platform),\"\(l.name)\",\(l.uid),\(l.score),\"\(l.tags.joined(separator: "/"))\",\"\(l.contact)\",\"\(t)\",\"\(l.postTitle)\"\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leads.csv")
        try? ("\u{FEFF}" + s).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - 内置浏览器采集面板（先登录 → 再采集）

struct WebCollectSheet: View {
    let platform: Platform
    let keyword: String
    @Binding var running: Bool
    let onBatch: ([Lead]) -> Void
    let onLog: (String) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var shown = 0
    @State private var started = false
    @State private var reloadKey = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banner

                if started {
                    WebGrabber(platform: platform, keyword: keyword, running: $running,
                               onBatch: { batch in
                                   shown += batch.count
                                   onBatch(batch)
                               },
                               onLog: onLog)
                        .id(reloadKey)
                } else {
                    // 未开始采集时，只显示网页供登录/浏览
                    WebGrabber(platform: platform, keyword: keyword, running: .constant(false),
                               onBatch: { _ in },
                               onLog: { _ in })
                        .id(reloadKey)
                }
            }
            .navigationTitle("\(platform.name) · \(keyword)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("重新加载") { reloadKey = UUID() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(started ? "完成" : "开始采集") {
                        if started {
                            dismiss()
                        } else {
                            started = true
                            reloadKey = UUID()
                            onLog("\(platform.name)：开始采集（自动滚动 + 抓接口）")
                        }
                    }
                    .bold()
                }
            }
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if started {
                Text("采集中：自动滚动页面并抓取接口数据 · 已捕获 \(shown) 条")
                    .font(.caption)
            } else {
                Text("第 1 步：在下方页面登录/浏览（很多平台不登录看不到评论）")
                    .font(.caption).bold()
                Text("第 2 步：点右上角「开始采集」，自动滚动并抓取")
                    .font(.caption)
                Text("提示：微博/抖音/快手/小红书建议先在页面内登录一次，cookie 会保留。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(started ? Color.green.opacity(0.12) : Color.blue.opacity(0.12))
    }
}
