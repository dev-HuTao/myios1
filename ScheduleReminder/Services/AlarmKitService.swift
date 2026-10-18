import Foundation
import AlarmKit

/// 用 AlarmKit 实现「提前提醒 / 别迟到」的硬提醒。
/// 相比本地通知：即使 App 被杀、锁屏、被 Focus 静音，系统级闹钟依然可靠触发。
///
/// 前置要求：
/// 1. 部署目标 iOS 26.0+（AlarmKit 自 iOS 26 起提供）
/// 2. 在 App Target 的 Signing & Capabilities 添加 **AlarmKit** 能力
///    （对应授权 com.apple.developer.alarmkit，真机/分发可能需 Apple 批准）
///
/// 注意：下方 API 基于 iOS 26 AlarmKit 公开接口编写；若 SDK 版本间有命名差异，
/// 以 Xcode 自动补全为准微调（例如 alarms 的取值方式、Metadata 构造参数）。
@available(iOS 26.0, *)
struct AlarmKitService {
    static let shared = AlarmKitService()
    private init() {}

    /// 请求闹钟授权。返回 false 时无法排程。
    func requestAuthorization() async -> Bool {
        do {
            return try await AlarmManager.shared.requestAuthorization()
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
        let metadata = Alarm.Metadata(title: s.subject, subtitle: subtitle)

        for occ in occurrences {
            let fire = occ.addingTimeInterval(-Double(minutesBefore) * 60)
            guard fire > Date() else { continue }   // 跳过过期触发点
            let config = Alarm.Configuration(alertAt: fire, metadata: metadata)
            do {
                let id = try await AlarmManager.shared.schedule(config)
                print("已排程闹钟 \(s.subject) 提前\(minutesBefore)分 @ \(fire) -> \(id)")
            } catch {
                print("AlarmKit 排程失败 \(s.subject) @ \(fire): \(error)")
            }
        }
    }

    /// 取消所有已排程的闹钟。
    func cancelAll() async {
        do {
            // 遍历当前闹钟并逐个取消；若 SDK 中 alarms 的取法不同请按补全调整。
            for alarm in try await AlarmManager.shared.alarms {
                try await AlarmManager.shared.cancel(alarm.id)
            }
        } catch {
            print("取消闹钟失败: \(error)")
        }
    }
}
