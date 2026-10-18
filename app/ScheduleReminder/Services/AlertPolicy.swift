import Foundation

/// 统一的提醒策略：闹钟与实时活动共用同一套判断，避免两边逻辑不一致。
///
/// 规则：
/// 1) 单课显式设置了 `alertMinutes` → 用它；
/// 2) 否则，若该课是当天首节课且开启了「首节课提醒」→ 用首节课分钟（默认 30）；
/// 3) 否则 → 不提醒（nil）。
enum AlertPolicy {
    static var firstClassEnabled: Bool {
        let d = UserDefaults.standard
        return d.object(forKey: "firstClassAlertEnabled") != nil
            ? d.bool(forKey: "firstClassAlertEnabled")
            : true
    }

    static var firstClassMinutes: Int {
        let d = UserDefaults.standard
        return d.object(forKey: "firstClassAlertMinutes") != nil
            ? d.integer(forKey: "firstClassAlertMinutes")
            : 30
    }

    /// 是否为所属星期的首节课
    static func isFirstOfDay(_ s: Schedule, among all: [Schedule]) -> Bool {
        let day = all.filter { $0.isEnabled && $0.weekday == s.weekday }
        guard let first = day.min(by: { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }) else {
            return false
        }
        return first.id == s.id
    }

    /// 该课应在课前多少分钟提醒；nil = 不提醒。
    /// 实时活动的启动窗口也直接用这个值。
    static func leadMinutes(for s: Schedule, among all: [Schedule]) -> Int? {
        if let m = s.alertMinutes { return m }
        if isFirstOfDay(s, among: all), firstClassEnabled {
            let m = firstClassMinutes
            return m > 0 ? m : nil
        }
        return nil
    }
}
