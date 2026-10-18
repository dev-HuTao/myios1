import Foundation
import ActivityKit
import SwiftUI

/// 管理灵动岛 / 锁屏 Live Activity。
///
/// 倒计时本身由 Widget 里的 `Text(timerInterval:countsDown:)` 负责，
/// 系统会每秒自动刷新，不依赖 App 持续运行；这里只负责启动/结束活动和必要刷新。
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    private var activity: Activity<ScheduleLiveActivityAttributes>?
    private var currentScheduleID: String?
    private var timer: Timer?
    private var isStarting = false

    var isActive: Bool { activity != nil }

    /// 临近下一节课时自动上灵动岛（受设置 `autoLiveActivity` 控制，默认开）。
    /// 说明：只有 App 处于前台时才会触发（系统限制，后台不能主动启动 Live Activity）。
    func autoStartIfNeeded(schedule: Schedule, allSchedules: [Schedule], now: Date = .now) {
        guard UserDefaults.standard.bool(forKey: "autoLiveActivity") else { return }

        // 课程开始超过 30 分钟后自动收掉活动，避免一直停在「已迟到」
        if let act = activity, now.timeIntervalSince(act.contentState.startTime) > 30 * 60 {
            Task { await endAll() }
            return
        }

        // 触发窗口 = 该课设置的「提前提醒分钟」（含首节课规则）；没设提醒则不上岛
        guard let lead = AlertPolicy.leadMinutes(for: schedule, among: allSchedules),
              lead > 0 else { return }

        guard let occ = schedule.nextOccurrence(from: now) else { return }
        let secondsUntil = occ.timeIntervalSince(now)
        guard secondsUntil > 0, secondsUntil <= Double(lead) * 60 else { return }

        let id = schedule.id.uuidString
        guard currentScheduleID != id else { return }   // 同一节课已在显示
        startActivity(subject: schedule.subject,
                      location: schedule.location ?? "",
                      startTime: occ,
                      scheduleID: id)
    }

    func startActivity(subject: String, location: String, startTime: Date, scheduleID: String) {
        guard !isStarting else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        isStarting = true

        let attrs = ScheduleLiveActivityAttributes(scheduleID: scheduleID,
                                                   subject: subject,
                                                   location: location)
        let state = ScheduleLiveActivityAttributes.ContentState(startTime: startTime, updatedAt: .now)

        Task {
            defer { self.isStarting = false }
            await endAll()   // 先结束旧的，再开新的，避免多个活动堆叠
            do {
                let act = try Activity.request(attributes: attrs, contentState: state, pushType: nil)
                self.activity = act
                self.currentScheduleID = scheduleID
                self.startTimer()
            } catch {
                print("Live Activity 启动失败: \(error)")
            }
        }
    }

    func update(startTime: Date) {
        guard let activity else { return }
        let state = ScheduleLiveActivityAttributes.ContentState(startTime: startTime, updatedAt: .now)
        Task { await activity.update(using: state) }
    }

    func refreshAll() {
        guard let activity else { return }
        let state = ScheduleLiveActivityAttributes.ContentState(startTime: activity.contentState.startTime,
                                                                updatedAt: .now)
        Task { await activity.update(using: state) }
    }

    func endAll() async {
        timer?.invalidate()
        timer = nil
        for act in Activity<ScheduleLiveActivityAttributes>.activities {
            await act.end(dismissalPolicy: .immediate)
        }
        activity = nil
        currentScheduleID = nil
    }

    /// 每分钟刷新一次状态（用于跨过迟到线后切换文案）；倒计时数字本身由系统 timer 负责。
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }
}
