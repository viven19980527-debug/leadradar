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
            .sheet(item: $webPlatform) { p in
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

        // 1) B站：原生
        if enabledPlatforms.contains(.bilibili) {
            logs.append("B站：开始原生抓取…")
            Task {
                await client.search(keyword: kw, pages: 2, industry: industry)
                merge(client.leads)
                logs.append("B站：\(client.leads.count) 条线索")
                // 2) 其它平台：依次用内置浏览器抓
                for p in enabledPlatforms where !p.native {
                    logs.append("\(p.name)：打开页面采集…")
                    webPlatform = p
                    // 等用户/自动滚动完成（WebCollectSheet 内部 40 秒收尾）
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                }
            }
        } else {
            if let first = enabledPlatforms.first(where: { !$0.native }) {
                webPlatform = first
                logs.append("\(first.name)：打开页面采集…")
            }
        }
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

// MARK: - 内置浏览器采集面板

struct WebCollectSheet: View {
    let platform: Platform
    let keyword: String
    @Binding var running: Bool
    let onBatch: ([Lead]) -> Void
    let onLog: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var shown = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("\(platform.name)：\(keyword)").font(.footnote).lineLimit(1)
                    Spacer()
                    Text("\(shown) 条").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)

                WebGrabber(platform: platform, keyword: keyword, running: $running,
                           onBatch: { batch in
                               shown += batch.count
                               onBatch(batch)
                           },
                           onLog: onLog)
                .overlay(alignment: .bottom) {
                    Text("自动滚动中…如需更多数据可在页面内登录后再采集")
                        .font(.caption2).padding(6)
                        .background(.thinMaterial)
                }
            }
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}


// MARK: - 行 / 详情 / 分享

struct LeadRow: View {
    let lead: Lead
    var color: Color {
        lead.score >= 80 ? .red : lead.score >= 50 ? .orange : .secondary
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(lead.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
                Text(lead.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                ForEach(lead.tags.prefix(2), id: \.self) { t in
                    Text(t).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(lead.text).font(.footnote).lineLimit(3).foregroundStyle(.primary.opacity(0.9))
            HStack(spacing: 8) {
                if !lead.contact.isEmpty {
                    Label(lead.contact, systemImage: "phone.fill")
                        .font(.caption2).foregroundStyle(.green)
                }
                Text(lead.postTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct LeadDetail: View {
    let lead: Lead
    @Environment(\.openURL) var openURL
    var body: some View {
        List {
            Section {
                HStack {
                    Text("\(lead.score)").font(.largeTitle.bold())
                        .foregroundStyle(lead.score >= 80 ? .red : lead.score >= 50 ? .orange : .secondary)
                    VStack(alignment: .leading) {
                        Text(lead.name).font(.headline)
                        Text(lead.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("评论原文") {
                Text(lead.text).font(.body).textSelection(.enabled)
            }
            if !lead.contact.isEmpty {
                Section("联系方式") {
                    HStack {
                        Text(lead.contact).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("复制") { UIPasteboard.general.string = lead.contact }
                    }
                }
            }
            Section("来源") {
                Text(lead.postTitle).font(.footnote)
                if !lead.profileURL.isEmpty {
                    Button("打开作者主页") { if let u = URL(string: lead.profileURL) { openURL(u) } }
                }
                if !lead.videoURL.isEmpty {
                    Button("打开来源页面") { if let u = URL(string: lead.videoURL) { openURL(u) } }
                }
            }
        }
        .navigationTitle("线索详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
