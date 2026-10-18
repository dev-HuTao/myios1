import Foundation
import ActivityKit

/// 灵动岛 / 锁屏 Live Activity 的数据结构。
/// 此文件需同时加入 App Target 与 Widget Target。
public struct ScheduleLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startTime: Date      // 上课时间（迟到线）
        public var updatedAt: Date       // 最近刷新时间
        public init(startTime: Date, updatedAt: Date) {
            self.startTime = startTime
            self.updatedAt = updatedAt
        }
    }

    public var scheduleID: String
    public var subject: String
    public var location: String

    public init(scheduleID: String, subject: String, location: String) {
        self.scheduleID = scheduleID
        self.subject = subject
        self.location = location
    }
}
