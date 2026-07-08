import ActivityKit
import WidgetKit
import SwiftUI

// Live Activity for the active-sleep timer: Lock Screen banner + Dynamic
// Island. Renders `startDate` with a system-driven live timer — no polling.
struct SulavSleepLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { context in
            LockScreenSleepView(startDate: context.state.startDate)
                .activityBackgroundTint(SleepColor.sleepBlack)
                .activitySystemActionForegroundColor(SleepColor.ember)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(SleepColor.ember)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer)
                        .font(SleepFont.title(16))
                        .foregroundStyle(SleepColor.ember)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Asleep")
                        .font(SleepFont.body(12))
                        .foregroundStyle(SleepColor.muted)
                }
            } compactLeading: {
                Image(systemName: "moon.fill").foregroundStyle(SleepColor.ember)
            } compactTrailing: {
                Text(context.state.startDate, style: .timer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SleepColor.ember)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "moon.fill").foregroundStyle(SleepColor.ember)
            }
        }
    }
}

private struct LockScreenSleepView: View {
    let startDate: Date

    var body: some View {
        HStack(spacing: SleepSpacing.md) {
            // The ember night sloth — the sleep screen's centerpiece — leads
            // the banner, so the lock screen is recognizably SleepBlock
            // before a single word is read.
            Image("NightSloth")
                .resizable()
                .scaledToFit()
                .frame(height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asleep")
                    .font(SleepFont.body(13))
                    .foregroundStyle(SleepColor.muted)
                Text(startDate, style: .timer)
                    .font(SleepFont.title(24))
                    .foregroundStyle(SleepColor.ember)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(SleepSpacing.lg)
    }
}
