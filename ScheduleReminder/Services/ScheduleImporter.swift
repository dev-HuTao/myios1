import Foundation

/// JSON 导入对应的数据结构（与持久化模型解耦）。
/// 提醒分钟兼容两个字段名：`alertMinutes`（新）优先，其次 `remindBeforeMinutes`（旧）。
struct ScheduleImportDTO: Codable {
    let subject: String
    let weekday: Int
    let hour: Int
    let minute: Int
    let location: String?
    let remindBeforeMinutes: Int?
    let alertMinutes: Int?

    var effectiveAlertMinutes: Int? { alertMinutes ?? remindBeforeMinutes }
}

enum ScheduleImportError: LocalizedError {
    case empty
    case invalidField(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "JSON 数组为空，没有可导入的课程"
        case .invalidField(let message):
            return message
        }
    }
}

enum ScheduleImporter {
    /// 解析并校验 JSON，校验不通过时抛出可读错误，避免脏数据进入数据库。
    static func `import`(data: Data) throws -> [Schedule] {
        let dtos = try JSONDecoder().decode([ScheduleImportDTO].self, from: data)
        guard !dtos.isEmpty else { throw ScheduleImportError.empty }

        return try dtos.map { d in
            let subject = d.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subject.isEmpty else {
                throw ScheduleImportError.invalidField("subject 不能为空")
            }
            guard (1...7).contains(d.weekday) else {
                throw ScheduleImportError.invalidField("weekday 必须是 1~7（1=周一 … 7=周日）")
            }
            guard (0...23).contains(d.hour) else {
                throw ScheduleImportError.invalidField("hour 必须是 0~23")
            }
            guard (0...59).contains(d.minute) else {
                throw ScheduleImportError.invalidField("minute 必须是 0~59")
            }
            if let m = d.effectiveAlertMinutes, m <= 0 {
                throw ScheduleImportError.invalidField("提醒分钟必须大于 0")
            }

            return Schedule(subject: subject,
                            weekday: d.weekday,
                            hour: d.hour,
                            minute: d.minute,
                            location: d.location,
                            alertMinutes: d.effectiveAlertMinutes)
        }
    }
}
