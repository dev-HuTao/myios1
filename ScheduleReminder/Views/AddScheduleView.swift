import SwiftUI
import SwiftData

/// 新增 / 编辑课程。`editing == nil` 为新增，否则为编辑。
struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultAlertMinutes") private var defaultAlertMinutes = 20

    let editing: Schedule?

    @State private var subject = ""
    @State private var weekday = 2          // 默认周二（用户视角 1=周一）
    @State private var hour = 10
    @State private var minute = 0
    @State private var location = ""
    @State private var alertOn = false
    @State private var alertMinutes = 20
    @State private var didLoad = false

    init(editing: Schedule? = nil) {
        self.editing = editing
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("科目", text: $subject)
                Picker("星期", selection: $weekday) {
                    ForEach(1...7, id: \.self) { Text(Schedule.weekdayNames[$0 - 1]) }
                }
                Picker("小时", selection: $hour) {
                    ForEach(0..<24, id: \.self) { Text("\($0)") }
                }
                Picker("分钟", selection: $minute) {
                    ForEach(0..<60, id: \.self) { Text("\($0)") }
                }
                TextField("地点（可选）", text: $location)
                Section("上课提醒") {
                    Toggle("上课前提醒", isOn: $alertOn)
                    if alertOn {
                        Stepper("提前 \(alertMinutes) 分钟响铃", value: $alertMinutes, in: 1...120)
                    }
                }
            }
            .navigationTitle(editing == nil ? "添加课程" : "编辑课程")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(); dismiss() }.disabled(subject.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let e = editing {
            subject = e.subject
            weekday = e.weekday
            hour = e.hour
            minute = e.minute
            location = e.location ?? ""
            alertOn = e.alertMinutes != nil
            alertMinutes = e.alertMinutes ?? defaultAlertMinutes
        } else {
            alertMinutes = defaultAlertMinutes
        }
    }

    private func save() {
        if let e = editing {
            e.subject = subject
            e.weekday = weekday
            e.hour = hour
            e.minute = minute
            e.location = location.isEmpty ? nil : location
            e.alertMinutes = alertOn ? alertMinutes : nil
        } else {
            let s = Schedule(subject: subject,
                             weekday: weekday,
                             hour: hour,
                             minute: minute,
                             location: location.isEmpty ? nil : location,
                             alertMinutes: alertOn ? alertMinutes : nil)
            modelContext.insert(s)
        }
        rescheduleAll()
    }

    private func rescheduleAll() {
        try? modelContext.save()
        let all = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        Task { await AlarmKitService.shared.scheduleAll(schedules: all) }
    }
}
