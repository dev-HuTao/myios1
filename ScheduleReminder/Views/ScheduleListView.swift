import SwiftUI
import SwiftData
import ActivityKit
import UIKit

func formatRemaining(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    let h = s / 3600
    let m = (s % 3600) / 60
    return h > 0 ? "\(h)小时\(m)分" : "\(m)分"
}

/// 用单一枚举驱动弹窗，避免同一视图多个 `.sheet` 互相覆盖
enum ActiveSheet: Identifiable {
    case add
    case edit(Schedule)
    case importFile
    case settings

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let s): return "edit-\(s.id.uuidString)"
        case .importFile: return "import"
        case .settings: return "settings"
        }
    }
}

struct ScheduleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Schedule.weekday),
                  SortDescriptor(\Schedule.hour),
                  SortDescriptor(\Schedule.minute)])
    private var schedules: [Schedule]

    @Environment(\.scenePhase) private var scenePhase

    @State private var now = Date()
    @State private var activeSheet: ActiveSheet?

    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if let next = nextSchedule {
                    Section("即将开始") {
                        NextScheduleCard(schedule: next, now: now)
                    }
                }
                Section("课程表") {
                    ForEach(schedules) { s in
                        ScheduleRow(schedule: s,
                                    now: now,
                                    isFirstOfDay: firstOfDayIDs.contains(s.id),
                                    effectiveMinutes: effectiveAlerts[s.id])
                            .contentShape(Rectangle())
                            .onTapGesture { activeSheet = .edit(s) }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("课程提醒")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("添加", systemImage: "plus") { activeSheet = .add }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入", systemImage: "square.and.arrow.down") { activeSheet = .importFile }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("设置", systemImage: "gearshape") { activeSheet = .settings }
                }
            }
            .onReceive(timer) { value in
                now = value
                autoStartLiveIfNeeded()
            }
            .onAppear {
                reschedule()
                autoStartLiveIfNeeded()
            }
            .onChange(of: schedules.count) { _ in reschedule() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    reschedule()
                    autoStartLiveIfNeeded()
                }
            }
        }
        .task { await checkPermissions() }
        .alert("权限提醒", isPresented: $showPermissionAlert) {
            Button("去设置") { openSettings() }
            Button("不再提示", role: .destructive) {
                UserDefaults.standard.set(true, forKey: "skipPermissionAlert")
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(permissionMessage)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddScheduleView()
            case .edit(let s):
                AddScheduleView(editing: s)
            case .importFile:
                ImportView()
            case .settings:
                SettingsView()
            }
        }
    }

    var firstOfDayIDs: Set<UUID> {
        var ids = Set<UUID>()
        for w in 1...7 {
            let day = schedules.filter { $0.isEnabled && $0.weekday == w }
            if let f = day.min(by: { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }) {
                ids.insert(f.id)
            }
        }
        return ids
    }

    /// 每门课真正生效的提醒分钟（含首节课规则），用于列表准确展示
    var effectiveAlerts: [UUID: Int] {
        var map: [UUID: Int] = [:]
        let firsts = firstOfDayIDs
        for s in schedules where s.isEnabled {
            if let m = s.alertMinutes {
                map[s.id] = m
            } else if firsts.contains(s.id), AlertPolicy.firstClassEnabled, AlertPolicy.firstClassMinutes > 0 {
                map[s.id] = AlertPolicy.firstClassMinutes
            }
        }
        return map
    }

    var nextSchedule: Schedule? {
        schedules
            .filter { $0.isEnabled }
            .min(by: { a, b in
                (a.nextOccurrence() ?? .distantFuture) < (b.nextOccurrence() ?? .distantFuture)
            })
    }

    func delete(_ index: IndexSet) {
        for i in index { modelContext.delete(schedules[i]) }
        try? modelContext.save()
        // 用删除后的最新数据重排，避免把已删课程又排回去
        let all = (try? modelContext.fetch(FetchDescriptor<Schedule>())) ?? []
        Task { await AlarmKitService.shared.scheduleAll(schedules: all) }
    }

    func reschedule() {
        Task { await AlarmKitService.shared.scheduleAll(schedules: Array(schedules)) }
    }

    func autoStartLiveIfNeeded() {
        guard let next = nextSchedule else { return }
        LiveActivityManager.shared.autoStartIfNeeded(schedule: next,
                                                     allSchedules: Array(schedules),
                                                     now: now)
    }

    /// 检查闹钟与实时活动授权，被拒时给出可操作提示
    func checkPermissions() async {
        guard !UserDefaults.standard.bool(forKey: "skipPermissionAlert") else { return }
        var messages: [String] = []

        let alarmAuthorized = await AlarmKitService.shared.requestAuthorization()
        if !alarmAuthorized {
            messages.append("未获得「闹钟」权限，提前提醒不会响铃。请到「设置 → 本 App」开启。")
        }
        if !ActivityAuthorizationInfo().areActivitiesEnabled {
            messages.append("「实时活动」未开启，灵动岛倒计时不可用。请到「设置 → 本 App → 实时活动」开启。")
        }

        guard !messages.isEmpty else { return }
        permissionMessage = messages.joined(separator: "\n")
        showPermissionAlert = true
    }

    /// 跳转到本 App 的系统设置页
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// 即将开始课程的醒目卡片 + 「上灵动岛」按钮
struct NextScheduleCard: View {
    let schedule: Schedule
    let now: Date

    var body: some View {
        let occ = schedule.nextOccurrence() ?? Date()
        let remaining = occ.timeIntervalSince(now)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(schedule.subject).font(.title2.bold())
                Spacer()
                Text(schedule.timeText).foregroundStyle(.secondary)
            }
            if remaining > 0 {
                Text("距迟到还有 " + formatRemaining(remaining))
                    .font(.title3).foregroundStyle(.orange)
            } else {
                Text("已迟到 " + formatRemaining(-remaining))
                    .font(.title3).foregroundStyle(.red)
            }
            if let loc = schedule.location, !loc.isEmpty {
                Text(loc).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                LiveActivityManager.shared.startActivity(subject: schedule.subject,
                                                         location: schedule.location ?? "",
                                                         startTime: occ,
                                                         scheduleID: schedule.id.uuidString)
            } label: {
                Label("上灵动岛", systemImage: "wave.3.right")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

struct ScheduleRow: View {
    let schedule: Schedule
    let now: Date
    var isFirstOfDay: Bool = false
    var effectiveMinutes: Int? = nil

    var body: some View {
        let occ = schedule.nextOccurrence()
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(schedule.subject).font(.headline)
                    if isFirstOfDay {
                        Text("首节")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text(schedule.weekdayName + " " + schedule.timeText)
                    .font(.footnote).foregroundStyle(.secondary)
                if let loc = schedule.location, !loc.isEmpty {
                    Text(loc).font(.caption).foregroundStyle(.secondary)
                }
                if let m = effectiveMinutes {
                    Text("提前 \(m) 分响铃").font(.caption).foregroundStyle(.orange)
                } else {
                    Text("不提醒").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let occ {
                if occ > now {
                    Text("还有 " + formatRemaining(occ.timeIntervalSince(now)))
                        .font(.subheadline).foregroundStyle(.orange)
                } else {
                    Text("迟到 " + formatRemaining(-occ.timeIntervalSince(now)))
                        .font(.subheadline).foregroundStyle(.red)
                }
            }
        }
    }
}
