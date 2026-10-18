# 课程迟到提醒 (Schedule Reminder)

iOS 应用：导入课程表（JSON），用 **AlarmKit** 在「提前 N 分钟」做系统级可靠提醒，
以上课时间为迟到线；并通过 **灵动岛 / 锁屏 Live Activity** 实时显示「距迟到还有多久」。

## 功能
- 手动添加 / 编辑课程（点击课程行进入编辑），支持 JSON 批量导入
- **AlarmKit 提醒（按规则）**：
  - 每天最早的一节课（首节课）→ 按设置里的「首节课提前分钟」（默认 30）响铃；
  - 在课程里单独开启「上课前提醒」的课 → 按该课设定的分钟（如 20）响铃；
  - 其余课程 → 不响铃、不全屏。
  - 即使 App 被杀/锁屏/被 Focus 静音，系统闹钟仍可靠触发。
- 迟到判定：以上课时间为迟到线，倒计时归零即迟到
- 灵动岛 / 锁屏实时活动：显示距迟到倒计时，由系统 `Text(timerInterval:countsDown:)` **每秒自动刷新**（App 挂起也持续）；到达该课设置的「提前提醒分钟」时自动上岛（首节课按首节课规则）

## 环境要求
- macOS + Xcode 26（含 iOS 26 SDK）
- 运行设备 iOS 26+；灵动岛需 iPhone 14 Pro 及以上机型
- **AlarmKit 能力**：App Target 的 Signing & Capabilities 添加 AlarmKit（授权 `com.apple.developer.alarmkit`，真机/分发可能需 Apple 批准）

## 一键生成 Xcode 工程（推荐）
仓库根目录已有 `project.yml`（XcodeGen 描述文件），不用再手工新建 Target：

```bash
brew install xcodegen
xcodegen generate        # 生成 ScheduleReminder.xcodeproj 和 Config/*.plist、entitlements
open ScheduleReminder.xcodeproj
```

生成的 `*.xcodeproj`、`Config/` 已加入 `.gitignore`，改工程配置请改 `project.yml`（Target、文件归属、Info.plist、entitlements 都在里面）。

## 在 Xcode 中手工搭建（不用 XcodeGen 时）
1. 新建 iOS App：`Interface = SwiftUI`，`Storage = SwiftData`，`Product Name = ScheduleReminder`，`Deployment Target = 26.0`。
2. 新建 Target：`File > New > Target > Widget Extension`，名称 `ScheduleReminderWidget`，**不要**勾选 “Include Live Activity”，`Minimum = 26.0`。
3. 在 App Target 的 **Signing & Capabilities** 添加 **AlarmKit** 能力。
4. 文件归属：
   - App Target 加入：`App/`、`Models/`、`Services/`、`Views/`、`Shared/ScheduleLiveActivityAttributes.swift`
   - Widget Target 加入：`Widget/ScheduleWidgetBundle.swift`、`Widget/ScheduleLiveActivityView.swift`、`Shared/ScheduleLiveActivityAttributes.swift`
5. **关键**：`Shared/ScheduleLiveActivityAttributes.swift` 需在文件 Inspector 中同时勾选 **App Target 和 Widget Target**（两个 target 都要编译它）。
6. 在 App Target 与 Widget Target 的 `Info.plist` 增加布尔键 `NSSupportsLiveActivities = YES`。
7. 选择真机，运行主 Target 即可（AlarmKit 需真机，模拟器能力有限）。

## JSON 格式
见 `sample_schedule.json`。顶层为数组，每条字段：
- `subject`（必填）科目，如 "语文"
- `weekday`（必填）1 = 周一 … 7 = 周日
- `hour`、`minute`（必填）上课时间，24 小时制
- `location`（可选）地点
- `alertMinutes`（可选）或 `remindBeforeMinutes`（可选，旧字段名，两者同时存在时以 `alertMinutes` 为准）上课前提醒分钟，例如 20 表示提前 20 分钟响铃；**缺省或留空 = 不提醒**（即不全屏、不响铃）。注意：若该课是当天首节课且开启了「首节课提醒」，仍会按首节课规则响铃。

导入时会按「科目 + 星期 + 时间」自动去重：已存在的课程不会被重复添加，结果提示会显示跳过多少条。

## 提醒与灵动岛的分工（重要）
- **提醒（可靠触发）** 用 AlarmKit：系统闹钟，杀掉 App 也能响。见 `Services/AlarmKitService.swift`。
- **灵动岛倒计时（看一眼）** 用 ActivityKit Live Activity：见 `Services/LiveActivityManager.swift` 与 `Widget/`。
  AlarmKit 不提供灵动岛实时药丸，所以这一段保留。倒计时数字用系统 `Text(timerInterval:countsDown:)` 自动刷新，无需 App 轮询。
- 两者的触发时机统一由 `Services/AlertPolicy.swift` 计算：**到达该课设置的提前提醒分钟**时，既响闹钟、也自动上岛；没设提醒的课两者都不触发。
- 增删/编辑课程后会自动调用 `AlarmKitService.scheduleAll` 重新排程闹钟。

## AlarmKit 一次性闹钟与滚动重排（重要）
AlarmKit 的闹钟是**一次性**的，没有本地通知那样的「每周重复」。因此：
- `scheduleAll` 会为每节课一次排好**未来 2 周**的所有上课时间点（`Schedule.upcomingOccurrences(weeks:)`）；
- App 每次**启动 / 回到前台**都会重新 `scheduleAll`，把窗口向后滚动；
- 已过去的触发点由 `guard fire > Date()` 跳过，不会排过期闹钟；
- 重排前先 `cancelAll()` 清空旧闹钟，避免重复累积。

系统会负责「到点触发」这一次；触发后的闹钟自然结束，无需手动删除。
但系统**不会**自动排下一次——这就是需要滚动重排的原因。

## 用 GitHub Actions 生成 IPA

仓库里有两个 workflow，都在 `.github/workflows/`：

| 文件 | 产物 | 是否需要签名凭证 |
| --- | --- | --- |
| `build-ipa.yml` | `ScheduleReminder-unsigned.ipa`（未签名） | 不需要，push 即跑 |
| `build-ipa-signed.yml` | `ScheduleReminder-signed.ipa`（自动签名） | 需要付费账号 + ASC API Key |

### 未签名 IPA（默认，最省事）
push 到 `main` / 打 tag / 手动 `Run workflow` 后：
1. `macos-26` runner（自带 Xcode 26 + iOS 26 SDK）；
2. `brew install xcodegen` → `xcodegen generate` 生成工程；
3. `xcodebuild archive` 加 `CODE_SIGNING_ALLOWED=NO`，把 `.xcarchive` 里的 `ScheduleReminder.app` 装进 `Payload/` 再 zip 成 ipa；
4. 在 Actions 运行页面的 **Artifacts** 下载 `ScheduleReminder-unsigned-ipa`。

未签名 ipa **不能直接安装**，需用 Sideloadly / AltStore / Feather 等工具，以你自己的 Apple ID 重签后装到设备。重签使用的是你的描述文件，因此：
- 免费账号没有 `com.apple.developer.alarmkit` 授权，AlarmKit 闹钟会排程失败（Live Activity 灵动岛仍可用）；
- App 有效期 7 天（免费账号）或 1 年（付费账号），到期需重装。

### 已签名 IPA（需要证书）
前提：付费开发者账号，且 Apple 已批准 AlarmKit 授权（否则 codesign 会因 entitlements 不在描述文件里而失败）。

1. 在 App Store Connect → Users and Access → Integrations 创建 API Key，下载 `AuthKey_XXX.p8`；
2. 仓库 Settings → Secrets and variables → Actions 添加：
   - `APPLE_TEAM_ID`：10 位 Team ID
   - `ASC_KEY_ID`：Key ID
   - `ASC_ISSUER_ID`：Issuer ID
   - `ASC_PRIVATE_KEY`：`.p8` 文件的完整内容
3. 手动运行 `Build Signed IPA`，可选 `development` / `ad-hoc` / `app-store-connect`。

`development` 只能装到设备列表里已注册的 iPhone；分发给他人用 `ad-hoc`（需先收集设备 UDID）。

### 常见失败点
- **找不到 iOS 26 SDK**：`macos-26` 已经是 GitHub 正式 runner；若先跑在旧镜像上，改用 `macos-26` 并 `xcode-version: latest-stable`。
- **Swift 6 并发报错**：`project.yml` 里已固定 `SWIFT_VERSION: 5.0`，不要随手改成 6.0。
- **AlarmKit API 编译失败**：`Services/AlarmKitService.swift` 中的 `Alarm.Management` 相关调用是按 iOS 26 公开接口写的，首次 CI 若报签名/参数不匹配，以本机 Xcode 补全为准微调。
- **Bundle ID 重复**：`project.yml` 里默认 `com.example.ScheduleReminder`，签名前改成你自己的唯一 ID，并同步改两个 Target。
- **产物缺失**：`build-ipa.yml` 里的 `unzip -l` 步骤会列出 ipa 内容，失败时先看 archive 日志里的第一条 error。

## 已知限制
- 滚动重排窗口为 2 周；若用户超过 2 周不打开 App，窗口外的课程会没有闹钟（打开 App 即恢复）。可把 `AlarmKitService.rollingWeeks` 调大，但会增加系统闹钟数量。
- AlarmKit API 基于 iOS 26 公开接口编写；若 SDK 版本间有命名差异（如 `alarms` 取值、`Metadata` 构造参数），以 Xcode 补全为准微调。
- 倒计时数字由系统 `Text(timerInterval:)` 每秒自动刷新，App 挂起/被杀后仍会继续倒数；
  但「自动上岛」只能在 App 前台时触发（系统不允许后台主动启动 Live Activity），手动「上灵动岛」始终可用。
- 跨过迟到线后切换「已迟到」文案依赖 App 刷新（前台时每分钟一次）；App 长期不活跃时会停在 0。
