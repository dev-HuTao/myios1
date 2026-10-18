import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var status = ""
    @State private var showPicker = false
    @State private var jsonText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("从 JSON 文件导入") {
                    Button("选择 .json 文件") { showPicker = true }
                }
                Section("或粘贴 JSON 文本") {
                    TextEditor(text: $jsonText)
                        .frame(minHeight: 200)
                    Button("解析并导入") { importFromText() }
                }
                if !status.isEmpty {
                    Section { Text(status).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("导入课程表")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    // 从「文件」App 选出的 URL 需要安全作用域授权，否则读取可能失败
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        try importData(data)
                    } catch {
                        status = "导入失败：\(error.localizedDescription)"
                    }
                case .failure(let err):
                    status = "选择失败：\(err.localizedDescription)"
                }
            }
        }
    }

    func importFromText() {
        guard let data = jsonText.data(using: .utf8) else {
            status = "文本无法编码为 UTF-8"
            return
        }
        do { try importData(data) } catch { status = "解析失败：\(error.localizedDescription)" }
    }

    func importData(_ data: Data) throws {
        let incoming = try ScheduleImporter.import(data: data)
        let existing = try modelContext.fetch(FetchDescriptor<Schedule>())

        // 去重：已存在或本批次内重复的（科目+星期+时间）跳过
        var seen = Set(existing.map { $0.dedupKey })
        var inserted = 0
        var skipped = 0
        for s in incoming {
            if seen.contains(s.dedupKey) {
                skipped += 1
                continue
            }
            seen.insert(s.dedupKey)
            modelContext.insert(s)
            inserted += 1
        }

        try modelContext.save()
        if skipped > 0 {
            status = "成功导入 \(inserted) 条，跳过 \(skipped) 条重复"
        } else {
            status = "成功导入 \(inserted) 条课程"
        }

        let all = try modelContext.fetch(FetchDescriptor<Schedule>())
        Task { await AlarmKitService.shared.scheduleAll(schedules: all) }
    }
}
