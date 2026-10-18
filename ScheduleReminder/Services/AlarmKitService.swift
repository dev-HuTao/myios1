import Foundation
import AlarmKit
import SwiftUI

/// 用 AlarmKit 实现「提前提醒 / 别迟到」的硬提醒。
/// 相比本地通知：即使 App 被杀、锁屏、被 Focus 静音，系统级闹钟依然可靠触发。
///
/// 前置要求：
/// 1. 部署目标 iOS 26.0+（AlarmKit 自 iOS 26 起提供）
/// 2. Info.plist 提供 NSAlarmKitUsageDescription；分发时 App Target 需有 AlarmKit 能力
///
/// 说明：AlarmKit 没有 `Alarm.Metadata` / `Alarm.Configuration`，
/// 元数据要自定义类型遵循 `AlarmMetadata`，配置用 `AlarmManager.AlarmConfiguration`，
/// 排程/取消分别是 `schedule(id:configuration:)` 与 `cancel(id:)`。
@available(iOS 26.0, *)
struct AlarmKitMetadata: AlarmMetadata {
    var subject: String
    var time: String
    var place: String
}

@available(iOS 26.0, *)
struct AlarmKitService {
    static let shared = AlarmKitService()
    private init() {}

    /// 请求闹钟授权。返回 false 时无法排程。
    func requestAuthorization() async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch {
            print("AlarmKit 授权失败: \(error)")
            return false
        }
    }

    /// 重新排程全部课程的提醒闹钟（先清空，再按 `AlertPolicy` 统一规则重建）。
    func scheduleAll(schedules: [Schedule]) async {
        await cancelAll()
        let enabled = schedules.filter { $0.isEnabled }
        for s in enabled {
            if let minutes = AlertPolicy.leadMinutes(for: s, among: enabled) {
                await schedule(s, minutesBefore: minutes)
            }
        }
    }

    /// 滚动排程的周数：AlarmKit 闹钟是一次性的，这里一次排好未来 N 周；
    /// App 每次启动/回前台都会重建，覆盖范围足够。
    private let rollingWeeks = 2

    /// 为单条课程在「上课时间 - 提前分钟」排未来 N 周的系统闹钟。
    /// 已过去的触发点直接跳过（不排过期闹钟）；重复靠滚动重排，系统不会自动续。
    func schedule(_ s: Schedule, minutesBefore: Int) async {
        let occurrences = s.upcomingOccurrences(weeks: rollingWeeks)
        let subtitle = "\(s.timeText) 上课" + (s.location.map { " · \($0)" } ?? "")

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "\(s.subject) · \(minutesBefore) 分钟后上课"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let presentation = AlarmPresentation(alert: alert, countdown: nil, paused: nil)
        let attributes = AlarmAttributes<AlarmKitMetadata>(
            presentation: presentation,
            metadata: AlarmKitMetadata(subject: s.subject,
                                       time: s.timeText,
                                       place: s.location ?? ""),
            tintColor: .orange
        )

        for occ in occurrences {
            let fire = occ.addingTimeInterval(-Double(minutesBefore) * 60)
            guard fire > Date() else { continue }   // 跳过过期触发点
            let config = AlarmManager.AlarmConfiguration<AlarmKitMetadata>(
                countdownDuration: nil,
                schedule: .fixed(fire),
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: nil
            )
            do {
                let alarm = try await AlarmManager.shared.schedule(id: UUID(), configuration: config)
                print("已排程闹钟 \(s.subject) 提前\(minutesBefore)分 @ \(fire) \(subtitle) -> \(alarm.id)")
            } catch {
                print("AlarmKit 排程失败 \(s.subject) @ \(fire): \(error)")
            }
        }
    }

    /// 取消所有已排程的闹钟。
    func cancelAll() async {
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        for alarm in alarms {
            do {
                try await AlarmManager.shared.cancel(id: alarm.id)
            } catch {
                print("取消闹钟 \(alarm.id) 失败: \(error)")
            }
        }
    }
}
