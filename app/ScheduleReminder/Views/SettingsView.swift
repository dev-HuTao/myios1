import SwiftUI

struct SettingsView: View {
    @AppStorage("firstClassAlertEnabled") private var firstClassAlertEnabled = true
    @AppStorage("firstClassAlertMinutes") private var firstClassAlertMinutes = 30
    @AppStorage("defaultAlertMinutes") private var defaultAlertMinutes = 20
    @AppStorage("autoLiveActivity") private var autoLiveActivity = true
    @AppStorage("skipPermissionAlert") private var skipPermissionAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("每天首节课") {
                    Toggle("提前响铃", isOn: $firstClassAlertEnabled)
                    if firstClassAlertEnabled {
                        Stepper("提前 \(firstClassAlertMinutes) 分钟响铃", value: $firstClassAlertMinutes, in: 1...120)
                    }
                    Text("每天最早的一节课会按此时长提前响铃；若该课已单独设置提醒则以其为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("单课默认") {
                    Stepper("新增课程默认提前 \(defaultAlertMinutes) 分钟", value: $defaultAlertMinutes, in: 1...120)
                }
                Section("灵动岛") {
                    Toggle("到达提前提醒时间自动上灵动岛", isOn: $autoLiveActivity)
                    Text("上岛时机 = 该课设置的提前提醒分钟（首节课按首节课规则）。倒计时由系统每秒自动刷新；自动上岛需 App 处于前台时触发。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("权限") {
                    Toggle("启动时提示缺失权限", isOn: Binding(
                        get: { !skipPermissionAlert },
                        set: { skipPermissionAlert = !$0 }
                    ))
                    Text("关闭后，启动时不再弹出权限提醒；可随时重新打开。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") {
                    Text("迟到判定：以上课时间（如 10:00）为迟到线，倒计时归零即视为迟到。未开启提醒的课程不会响铃、也不全屏。")
                        .font(.footnote)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
