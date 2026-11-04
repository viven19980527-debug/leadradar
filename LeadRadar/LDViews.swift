import SwiftUI
import UniformTypeIdentifiers

@main
struct LeadRadarApp: App {
    var body: some Scene {
        WindowGroup { RadarRoot() }
    }
}

// MARK: - 主界面

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
    @State var webQueue: [Platform] = []
    @State var logs: [String] = []
    @State var allLeads: [Lead] = []
    @State var groupMode = 0
    @AppStorage("target") var target = 50
    @AppStorage("onlyQuestion") var onlyQuestion = false
    @AppStorage("onlyContact") var onlyContact = false
    @AppStorage("cityFilter") var cityFilter = ""

    private var enabledPlatforms: [Platform] {
        Platform.allCases.filter { platformsRaw.contains($0.rawValue) }
    }

    private var filtered: [Lead] {
        allLeads.filter { l in
            guard l.score >= minScore else { return false }
            if onlyQuestion && !l.isQuestion { return false }
            if onlyContact && l.contact.isEmpty && l.ocrContact.isEmpty { return false }
            if !cityFilter.isEmpty {
                let c = l.city.isEmpty ? "" : l.city
                if c.isEmpty { return false }
                if !IPLocation.matches(c, cityFilter) { return false }
            }
            return true
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

    var body: some View {
        NavigationStack {
            List {
                searchSection
                platformSection
                if !logs.isEmpty { logSection }
                if !filtered.isEmpty { resultSection }
                filterSection
                settingsSection
                if filtered.isEmpty && logs.isEmpty && client.errorText.isEmpty {
                    emptySection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("获客雷达")
            .sheet(isPresented: $showCSV) {
                ShareSheet(items: [csvURL()])
            }
            .sheet(item: $webPlatform, onDismiss: { openNextWeb() }) { p in
                WebCollectSheet(platform: p, keyword: keyword,
                                running: $webRunning,
                                onBatch: { batch in merge(batch) },
                                onLog: { line in logs.append(line) })
            }
        }
        .onAppear { if keyword.isEmpty { keyword = lastKeyword } }
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
            Button(action: runAll) {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                    Text(webRunning || client.running ? "采集中…" : "一键全平台采集")
                        .font(.headline)
                    Spacer()
                    if webRunning || client.running { ProgressView() }
                }
            }
            .disabled(webRunning || client.running ||
                      keyword.trimmingCharacters(in: .whitespaces).isEmpty)

            Picker("最低分", selection: $minScore) {
                Text("全部").tag(0)
                Text("50+").tag(50)
                Text("70+").tag(70)
                Text("80+").tag(80)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("B站走原生接口（免登录）；微博/抖音/快手/小红书用内置浏览器，先登录再点「开始采集」。")
                .font(.caption2)
        }
    }

    private var platformSection: some View {
        Section("平台") {
            ForEach(Platform.allCases) { p in
                Button { toggle(p) } label: {
                    HStack {
                        Image(systemName: enabledPlatforms.contains(p) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(enabledPlatforms.contains(p) ? Color.blue : Color.secondary)
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
            ForEach(Array(logs.suffix(8).enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            if !client.progress.isEmpty {
                Text(client.progress).font(.caption2.monospaced()).foregroundStyle(Color.blue)
            }
        }
    }

    private var resultSection: some View {
        Group {
            Picker("分组", selection: $groupMode) {
                Text("按平台").tag(0)
                Text("按标签").tag(1)
            }
            .pickerStyle(.segmented)

            if groupMode == 0 {
                ForEach(Platform.allCases) { p in
                    platformGroup(p)
                }
            } else {
                ForEach(tagGroups, id: \.0) { pair in
                    tagGroup(pair)
                }
            }
        }
    }

    @ViewBuilder
    private func platformGroup(_ p: Platform) -> some View {
        let rows = filtered.filter { $0.platform == p.rawValue }
        if !rows.isEmpty {
            Section("\(p.name)（\(rows.count)）") {
                ForEach(rows) { lead in
                    NavigationLink { LeadDetail(lead: lead) } label: { LeadRow(lead: lead) }
                }
            }
        }
    }

    @ViewBuilder
    private func tagGroup(_ pair: (String, [Lead])) -> some View {
        Section("\(pair.0)（\(pair.1.count)）") {
            ForEach(pair.1) { lead in
                NavigationLink { LeadDetail(lead: lead) } label: { LeadRow(lead: lead) }
            }
        }
    }

    private var filterSection: some View {
        Section("筛选") {
            Toggle("只看提问者（吗/多少/求推荐…）", isOn: $onlyQuestion)
            Toggle("只看有联系方式的", isOn: $onlyContact)
            HStack {
                Text("城市")
                TextField("如：深圳（留空=不限）", text: $cityFilter)
                    .multilineTextAlignment(.trailing)
            }
            Text("当前命中 \(filtered.count) / \(allLeads.count) 条")
                .font(.caption2).foregroundStyle(.secondary)
        }
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
            Stepper("目标条数：\(target)", value: $target, in: 20...300, step: 10)
            Button { showCSV = true } label: {
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

    private var emptySection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 34)).foregroundStyle(.secondary)
                Text("还没有线索").font(.headline)
                Text("输入关键词 → 勾选平台 → 一键全平台采集")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
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

        webQueue = enabledPlatforms.filter { !$0.native }
        let names = webQueue.map { $0.name }.joined(separator: "、")
        logs.append("待采集 web 平台：" + (names.isEmpty ? "无" : names))

        if enabledPlatforms.contains(.bilibili) {
            logs.append("B站：开始原生抓取…")
            Task {
                await client.search(keyword: kw, pages: 3, industry: industry, target: target)
                merge(client.leads)
                logs.append("B站：\(client.leads.count) 条线索（目标 \(target)）")
                openNextWeb()
            }
        } else {
            openNextWeb()
        }
    }

    private func openNextWeb() {
        guard let next = webQueue.first else {
            logs.append("全部结束，共 \(allLeads.count) 条线索")
            return
        }
        webQueue.removeFirst()
        logs.append("\(next.name)：弹出页面后先登录，再点「开始采集」")
        webPlatform = next
    }

    private func merge(_ batch: [Lead]) {
        var map: [String: Lead] = [:]
        for l in allLeads { map[l.id] = l }
        for l in batch {
            if var old = map[l.id] {
                old.comments += l.comments
                if l.score > old.score {
                    old.score = l.score
                    old.text = l.text
                    old.tags = l.tags
                }
                if !l.contact.isEmpty { old.contact = l.contact }
                map[l.id] = old
            } else {
                map[l.id] = l
            }
        }
        allLeads = map.values.sorted { $0.score > $1.score }
    }

    private func csvURL() -> URL {
        var out = "平台,昵称,UID,评分,标签,联系方式,评论,来源\n"
        for l in filtered {
            let t = l.text.replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(l.platform),\"\(l.name)\",\(l.uid),\(l.score),\"\(l.tags.joined(separator: "/"))\",\"\(l.contact)\",\"\(t)\",\"\(l.postTitle)\"\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leads.csv")
        try? ("\u{FEFF}" + out).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - 线索行

struct LeadRow: View {
    let lead: Lead

    private var color: Color {
        lead.score >= 80 ? .red : (lead.score >= 50 ? .orange : .secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(lead.score)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
                Text(lead.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                if lead.isQuestion {
                    Text("问")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.orange.opacity(0.25))
                        .clipShape(Capsule())
                }
                ForEach(lead.tags.prefix(2), id: \.self) { t in
                    Text(t).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text(lead.text)
                .font(.footnote)
                .lineLimit(3)
                .foregroundStyle(Color.primary.opacity(0.9))
            HStack(spacing: 8) {
                if !lead.contact.isEmpty {
                    Label(lead.contact, systemImage: "phone.fill")
                        .font(.caption2).foregroundStyle(Color.green)
                }
                if !lead.city.isEmpty {
                    Text(lead.city).font(.caption2).foregroundStyle(.secondary)
                }
                Text(lead.postTitle).font(.caption2)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 详情

struct LeadDetail: View {
    let lead: Lead
    @Environment(\.openURL) var openURL
    @AppStorage("industry") var industry = "空调/家电"
    @AppStorage("cityFilter") var cityFilter = ""

    @State private var ocrText: String = ""
    @State private var ocrContact: String = ""
    @State private var ocrRunning = false
    @State private var showScript = false

    private var scoreColor: Color {
        lead.score >= 80 ? .red : (lead.score >= 50 ? .orange : .secondary)
    }

    private var effectiveContact: String {
        if !ocrContact.isEmpty { return ocrContact }
        if !lead.contact.isEmpty { return lead.contact }
        return ""
    }

    var body: some View {
        List {
            // 分数 + 标签
            Section {
                HStack {
                    Text("\(lead.score)").font(.largeTitle.bold()).foregroundStyle(scoreColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lead.name).font(.headline)
                        HStack(spacing: 4) {
                            if lead.isQuestion {
                                Text("提问者").font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.25)).clipShape(Capsule())
                            }
                            if !lead.city.isEmpty {
                                Text(lead.city).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.green.opacity(0.18)).clipShape(Capsule())
                            }
                        }
                        if !lead.tags.isEmpty {
                            Text(lead.tags.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // D1/D2/D3 触达
            Section("触达") {
                if !effectiveContact.isEmpty {
                    HStack {
                        Text(effectiveContact).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("复制") { ContactActions.copy(effectiveContact) }
                    }
                    if ContactActions.canCall(effectiveContact) {
                        Button {
                            ContactActions.call(effectiveContact)
                        } label: { Label("直接拨号", systemImage: "phone.arrow.up.right.fill") }
                    }
                    if effectiveContact.hasPrefix("wechat") {
                        Button {
                            ContactActions.openWeChat(copying: ContactActions.phoneNumber(effectiveContact).isEmpty
                                                      ? effectiveContact.components(separatedBy: ":").last ?? ""
                                                      : ContactActions.phoneNumber(effectiveContact))
                        } label: { Label("复制微信号并打开微信", systemImage: "message.fill") }
                    }
                } else {
                    Text("这条还没有联系方式").font(.footnote).foregroundStyle(.secondary)
                }

                Button {
                    showScript = true
                } label: { Label("生成开场白话术", systemImage: "text.bubble.fill") }
            }

            // B1 简介
            if !lead.bio.isEmpty {
                Section("作者简介") {
                    Text(lead.bio).font(.footnote).textSelection(.enabled)
                    let hits = BioParser.extract(lead.bio)
                    if !hits.isEmpty {
                        ForEach(hits, id: \.label) { h in
                            HStack {
                                Text(h.label).font(.caption.monospaced())
                                Spacer()
                                Button("复制") { ContactActions.copy(h.value) }
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            // B3 头像 OCR
            Section("头像识别（离线 OCR）") {
                if ocrRunning {
                    HStack { ProgressView(); Text("识别中…").font(.footnote) }
                } else if !ocrText.isEmpty {
                    Text(ocrText).font(.caption.monospaced()).textSelection(.enabled)
                    if !ocrContact.isEmpty {
                        HStack {
                            Text("发现：\(ocrContact)").font(.caption).foregroundStyle(.green)
                            Spacer()
                            Button("用它联系") {
                                ContactActions.copy(ocrContact)
                            }.font(.caption)
                        }
                    }
                }
                Button {
                    runOCR()
                } label: {
                    Label(lead.avatar.isEmpty ? "无头像可识别" : "识别头像里的文字",
                          systemImage: "text.viewfinder")
                }
                .disabled(lead.avatar.isEmpty || ocrRunning)
            }

            Section("评论原文") {
                Text(lead.text).font(.body).textSelection(.enabled)
            }

            Section("来源") {
                Text(lead.postTitle).font(.footnote)
                if !lead.profileURL.isEmpty {
                    Button("打开作者主页") {
                        if let u = URL(string: lead.profileURL) { openURL(u) }
                    }
                }
                if !lead.videoURL.isEmpty {
                    Button("打开来源页面") {
                        if let u = URL(string: lead.videoURL) { openURL(u) }
                    }
                }
            }
        }
        .navigationTitle("线索详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScript) {
            ScriptSheet(lead: lead, industry: industry, city: cityFilter)
        }
    }

    private func runOCR() {
        ocrRunning = true
        Task {
            let text = await AvatarOCR.recognize(
                await AvatarOCR.download(lead.avatar) ?? UIImage())
            let hits = BioParser.extract(text)
            await MainActor.run {
                ocrText = text.isEmpty ? "（未识别到文字）" : text
                ocrContact = BioParser.best(hits) ?? ""
                ocrRunning = false
            }
        }
    }
}

// MARK: - 话术面板

struct ScriptSheet: View {
    let lead: Lead
    let industry: String
    let city: String
    @Environment(\.dismiss) var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section("开场白") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.body)
                }
                Section("追问") {
                    Text(ScriptGenerator.followUp(for: lead, industry: industry))
                        .font(.footnote)
                }
                Section {
                    Button {
                        ContactActions.copy(text)
                    } label: { Label("复制开场白", systemImage: "doc.on.doc") }
                    if !lead.contact.isEmpty {
                        Button {
                            ContactActions.openWeChat(copying: lead.contact.components(separatedBy: ":").last ?? "")
                        } label: { Label("复制并打开微信", systemImage: "message.fill") }
                    }
                }
            }
            .navigationTitle("话术")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if text.isEmpty {
                    text = ScriptGenerator.opening(for: lead, industry: industry, city: city)
                }
            }
        }
    }
}

// MARK: - 分享

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    @State private var useLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                banner
                browser
            }
            .navigationTitle("\(platform.name) · \(keyword)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        Button("登录") { useLogin = true; reloadKey = UUID() }
                        Button("重新加载") { useLogin = false; reloadKey = UUID() }
                    }
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

    @ViewBuilder
    private var browser: some View {
        if started {
            WebGrabber(platform: platform, keyword: keyword,
                       startURL: useLogin ? platform.loginURL : nil,
                       running: $running,
                       onBatch: { batch in
                           shown += batch.count
                           onBatch(batch)
                       },
                       onLog: onLog)
            .id(reloadKey)
        } else {
            WebGrabber(platform: platform, keyword: keyword,
                       startURL: useLogin ? platform.loginURL : nil,
                       running: .constant(false),
                       onBatch: { _ in },
                       onLog: { _ in })
            .id(reloadKey)
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if started {
                Text("采集中：自动滚动并抓接口 · 已捕获 \(shown) 条")
                    .font(.caption).bold()
                Text("看到数据后点右上角「完成」，会自动进入下一个平台")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("第 1 步：在下方页面登录（不登录大多看不到评论）")
                    .font(.caption).bold()
                Text("第 2 步：点右上角「开始采集」")
                    .font(.caption).bold()
                Text("登录一次即长期有效，cookie 会保留。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(started ? Color.green.opacity(0.14) : Color.blue.opacity(0.14))
    }
}
