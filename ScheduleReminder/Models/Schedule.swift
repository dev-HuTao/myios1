import Foundation
import SwiftData

/// 一条课程/日程。按「星期 + 时间」每周循环，上课时间即为迟到线。
@Model
final class Schedule: Identifiable {
    var id: UUID
    var subject: String
    /// 1 = 周一 ... 7 = 周日（用户视角）
    var weekday: Int
    var hour: Int
    var minute: Int
    var location: String?
    /// 上课前提醒分钟；nil = 不提醒（不全屏、不响铃）
    var alertMinutes: Int?
    var isEnabled: Bool

    init(id: UUID = UUID(),
         subject: String,
         weekday: Int,
         hour: Int,
         minute: Int,
         location: String? = nil,
         alertMinutes: Int? = nil,
         isEnabled: Bool = true) {
        self.id = id
        self.subject = subject
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.location = location
        self.alertMinutes = alertMinutes
        self.isEnabled = isEnabled
    }

    static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 防御性取值：即使导入脏数据也不会数组越界崩溃
    private var clampedWeekday: Int { min(max(weekday, 1), 7) }
    private var clampedHour: Int { min(max(hour, 0), 23) }
    private var clampedMinute: Int { min(max(minute, 0), 59) }

    var weekdayName: String { Self.weekdayNames[clampedWeekday - 1] }
    var timeText: String { String(format: "%02d:%02d", clampedHour, clampedMinute) }

    /// 导入去重键：科目（忽略大小写与首尾空白）+ 星期 + 时间
    var dedupKey: String {
        let name = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(name)|\(clampedWeekday)|\(clampedHour)|\(clampedMinute)"
    }

    /// 从指定时间起，下一次上课时间（含今天，最多向后看 8 天）
    func nextOccurrence(from date: Date = .now) -> Date? {
        let cal = Calendar.current
        for dayOffset in 0...7 {
            guard let base = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: date)) else { continue }
            var comp = DateComponents()
            comp.year = cal.component(.year, from: base)
            comp.month = cal.component(.month, from: base)
            comp.day = cal.component(.day, from: base)
            comp.hour = clampedHour
            comp.minute = clampedMinute
            comp.second = 0
            guard let candidate = cal.date(from: comp) else { continue }
            // DateComponents.weekday: 1=周日 ... 7=周六
            let targetWeekday = (clampedWeekday % 7) + 1
            guard cal.component(.weekday, from: candidate) == targetWeekday else { continue }
            if candidate >= date { return candidate }
        }
        return nil
    }

    /// 未来 `weeks` 周内所有上课时间点。AlarmKit 闹钟是一次性的，
    /// 需要一次排好多个未来时间点，避免「只响一次、下周不响」。
    func upcomingOccurrences(weeks: Int = 2, from date: Date = .now) -> [Date] {
        let cal = Calendar.current
        var result: [Date] = []
        let days = max(1, weeks) * 7
        for dayOffset in 0...days {
            guard let base = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: date)) else { continue }
            var comp = DateComponents()
            comp.year = cal.component(.year, from: base)
            comp.month = cal.component(.month, from: base)
            comp.day = cal.component(.day, from: base)
            comp.hour = clampedHour
            comp.minute = clampedMinute
            comp.second = 0
            guard let candidate = cal.date(from: comp) else { continue }
            let targetWeekday = (clampedWeekday % 7) + 1
            guard cal.component(.weekday, from: candidate) == targetWeekday else { continue }
            if candidate >= date { result.append(candidate) }
        }
        return result
    }
}
