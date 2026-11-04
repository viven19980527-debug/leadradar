import SwiftUI
import UniformTypeIdentifiers

@main
struct LeadRadarApp: App {
    var body: some Scene {
        WindowGroup { RadarRoot() }
    }
}

struct RadarRoot: View {
    @StateObject var client = BiliClient()
    @AppStorage("industry") var industry = "空调/家电"
    @AppStorage("lastKeyword") var lastKeyword = ""
    @State var keyword = ""
    @State var minScore = 0
    @State var showCSV = false

    var filtered: [Lead] {
        client.leads.filter { $0.score >= minScore }
    }

    var body: some View {
        NavigationStack {
            List {
                searchSection
                if client.running { progressSection }
                if !client.errorText.isEmpty { errorSection }
                if !filtered.isEmpty { resultSection }
                if !client.running && filtered.isEmpty && !client.errorText.isEmpty {
                    EmptyView()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("获客雷达")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("行业", selection: $industry) {
                            Text("空调/家电").tag("空调/家电")
                            Text("音响/影音").tag("音响/影音")
                        }
                        Button("导出 CSV") { showCSV = true }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showCSV) {
                ShareSheet(items: [csvURL()])
            }
        }
        .onAppear {
            if keyword.isEmpty { keyword = lastKeyword }
        }
    }

    // MARK: 搜索区

    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入关键词实时抓取，如：空调安装多少钱", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit { run() }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                run()
            } label: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(client.running ? "抓取中…" : "实时抓取")
                    Spacer()
                    if client.running { ProgressView() }
                }
                .font(.headline)
            }
            .disabled(client.running || keyword.trimmingCharacters(in: .whitespaces).isEmpty)

            Picker("最低分", selection: $minScore) {
                Text("全部").tag(0)
                Text("50+").tag(50)
                Text("70+").tag(70)
                Text("80+").tag(80)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("直连 B 站公开接口，从你输入的关键词开始搜视频、抓评论、现算意向分。不经过任何服务器。")
                .font(.caption2)
        }
    }

    private var progressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(client.scannedComments), total: Double(max(1, client.scannedComments + 30)))
                    .progressViewStyle(.linear)
                Text(client.progress).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text("已抓评论 \(client.scannedComments) 条 · 线索 \(client.leads.count) 条")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var errorSection: some View {
        Section {
            Text(client.errorText).font(.footnote).foregroundStyle(.orange)
        }
    }

    private var resultSection: some View {
        Section("线索 \(filtered.count) 条") {
            ForEach(filtered) { lead in
                NavigationLink {
                    LeadDetail(lead: lead)
                } label: {
                    LeadRow(lead: lead)
                }
            }
        }
    }

    private func run() {
        lastKeyword = keyword
        Task { await client.search(keyword: keyword, pages: 2, industry: industry) }
    }

    private func csvURL() -> URL {
        var s = "昵称,UID,评分,标签,联系方式,评论,视频,主页\n"
        for l in filtered {
            let t = l.text.replacingOccurrences(of: "\"", with: "\"\"")
            s += "\"\(l.name)\",\(l.uid),\(l.score),\"\(l.tags.joined(separator: "/"))\",\"\(l.contact)\",\"\(t)\",\"\(l.postTitle)\",\(l.profileURL)\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leads.csv")
        try? ("\u{FEFF}" + s).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - 行

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
                Text("评论\(lead.comments)条").font(.caption2).foregroundStyle(.secondary)
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
                Button("打开视频") { if let u = URL(string: lead.videoURL) { openURL(u) } }
                Button("打开作者主页") { if let u = URL(string: lead.profileURL) { openURL(u) } }
            }
        }
        .navigationTitle("线索详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 分享 CSV

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
