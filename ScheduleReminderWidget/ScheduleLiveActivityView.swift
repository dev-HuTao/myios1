import WidgetKit
import SwiftUI
import ActivityKit

private func la_timeText(_ d: Date) -> String {
    let cal = Calendar.current
    return String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
}

/// 自更新倒计时：`Text(timerInterval:countsDown:)` 由系统每秒刷新，
/// 即使 App 挂起/被杀也继续走，无需推送或后台任务。
struct CountdownView: View {
    let startTime: Date

    var body: some View {
        let now = Date()
        if startTime > now.addingTimeInterval(0.5) {
            Text(timerInterval: now...startTime, countsDown: true)
                .font(.subheadline).bold()
                .monospacedDigit()
                .foregroundColor(.orange)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        } else {
            Text("已迟到")
                .font(.subheadline).bold()
                .foregroundColor(.red)
        }
    }
}

/// 锁屏 / 全屏 Live Activity
struct ScheduleLiveActivityView: View {
    let context: ActivityViewContext<ScheduleLiveActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.subject)
                    .font(.headline)
                if !context.attributes.location.isEmpty {
                    Text(context.attributes.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("距迟到")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                CountdownView(startTime: context.state.startTime)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.6))
    }
}

/// 灵动岛配置
struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleLiveActivityAttributes.self) { context in
            ScheduleLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.subject).font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownView(startTime: context.state.startTime)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.location.isEmpty ? "课程提醒" : context.attributes.location)
                        .font(.caption).foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("上课 " + la_timeText(context.state.startTime))
                        .font(.caption2)
                }
            } compactLeading: {
                Text(String(context.attributes.subject.prefix(1)))
            } compactTrailing: {
                CountdownView(startTime: context.state.startTime)
            } minimal: {
                Text(la_timeText(context.state.startTime))
            }
        }
    }
}
