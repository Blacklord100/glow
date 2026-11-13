import SwiftUI
import GlowCore

struct TodayView: View {
    @Bindable var model: AppModel
    @ViewState private var addingTime = false
    @ViewState private var manualMinutes = 30
    @ViewState private var editingGoal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.dailyProgress >= 1 ? "A day well spent." : "Make room for focus.")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Small sessions. A little more glow.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { addingTime = true } label: { Label("Add time", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .popover(isPresented: $addingTime) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Count offline work").font(.headline)
                            Text("Add a meeting or a focus block you did away from Glow.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Stepper("\(manualMinutes) minutes", value: $manualMinutes, in: 5...480, step: 5)
                            Button("Add to today") { model.addTime(minutes: Double(manualMinutes)); addingTime = false }
                                .buttonStyle(.borderedProminent).tint(.orange)
                        }.padding(20).frame(width: 270)
                    }
            }

            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").foregroundStyle(.orange)
                    Text(notice).font(.system(size: 11))
                    Spacer()
                    Button { model.dismissNotice() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss").accessibilityLabel("Dismiss notice")
                }.padding(.horizontal, 12).padding(.vertical, 9).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }

            HStack(alignment: .top, spacing: 18) {
                GlowCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("DAILY CHARGE").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                            Spacer()
                            Button { editingGoal.toggle() } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain)
                                .help("Daily goal")
                                .accessibilityLabel("Edit daily goal")
                                .popover(isPresented: $editingGoal) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text("Your daily focus goal").font(.headline)
                                        Stepper(GlowFormat.duration(Double(model.goalMinutes * 60)), value: Binding(get: { model.goalMinutes }, set: { model.setGoal(minutes: $0) }), in: 30...720, step: 30)
                                        Text("Progress stops at 100%. Extra time is still saved.").font(.caption).foregroundStyle(.secondary)
                                    }.padding(20).frame(width: 280)
                                }
                        }
                        HStack(spacing: 24) {
                            ApplePreview(progress: model.dailyProgress, size: 94)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(model.percentLabel).font(.system(size: 50, weight: .light, design: .rounded)).monospacedDigit()
                                Text("\(GlowFormat.duration(model.todaySeconds)) focused").font(.system(size: 13, weight: .medium))
                                Text("of \(GlowFormat.duration(Double(model.goalMinutes * 60))) today").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        ProgressView(value: model.dailyProgress).tint(.orange)
                        HStack {
                            ForEach([0, 25, 50, 75, 100], id: \.self) { milestone in
                                if milestone != 0 { Spacer() }
                                Text("\(milestone)%").font(.system(size: 10, weight: .medium)).foregroundStyle(Double(milestone) <= model.dailyProgress * 100 ? Color.orange : Color.secondary)
                            }
                        }
                        Label("On-screen fill · physical milestones pulse", systemImage: "sparkle")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity)

                FocusCard(model: model).frame(width: 278)
            }

            WeekStrip(model: model)

            Spacer(minLength: 0)
        }.padding(30)
    }
}

struct FocusCard: View {
    @Bindable var model: AppModel
    var body: some View {
        GlowCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("FOCUS SESSION").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    if model.isRunning { Circle().fill(.green).frame(width: 6, height: 6) }
                }
                Text(GlowFormat.countdown(model.sessionActive || model.session.state == .completed ? model.session.remainingSeconds : Double(model.sessionMinutes * 60)))
                    .font(.system(size: 45, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Picker("Session length", selection: $model.sessionMinutes) {
                    Text("25 min").tag(25)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }.pickerStyle(.segmented).labelsHidden().disabled(model.sessionActive)
                Button { model.toggleSession() } label: {
                    Label(model.isRunning ? "Pause focus" : model.isPaused ? "Resume focus" : "Start focusing", systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                if model.sessionActive {
                    HStack {
                        Text(model.isPaused ? "Paused · progress saved" : "One thing at a time.").font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Finish") { model.endSession() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    }
                } else {
                    Text("Pause whenever you take a break.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WeekStrip: View {
    var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your last seven days").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("Focused time").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index - 6, to: model.now) ?? model.now
                    let seconds = model.ledger.focusSeconds(on: date)
                    VStack(spacing: 5) {
                        Text(seconds > 0 ? GlowFormat.duration(seconds) : "—").font(.system(size: 9)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(index == 6 ? Color.orange.gradient : Color.primary.opacity(0.13).gradient)
                            .frame(height: max(3, 23 * min(1, seconds / Double(model.goalMinutes * 60))))
                            .frame(height: 25, alignment: .bottom)
                        Text(index == 6 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: index == 6 ? .semibold : .regular))
                    }.frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
