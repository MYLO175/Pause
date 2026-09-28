import SwiftUI

struct JournalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var openSettings: () -> Void = {}
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var selectedDay: SelectedDay?
    @State private var add = false
    private let calendar = Calendar.current
    private let durationShades: [Double] = [0.055, 0.23, 0.36, 0.50, 0.62, 0.85]
    private var monthDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: month)!
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: geometry.size.height < 600 ? 14 : 24) {
                HStack {
                    TopBarButton(symbol: "arrow.left", label: "Back to meditation") { dismiss() }
                    Spacer()
                    TopBarButton(symbol: "plus", label: "Add meditation") { add = true }.accessibilityIdentifier("addMeditation")
                    TopBarButton(symbol: "slider.horizontal.3", label: "Settings", action: openSettings).disabled(model.active != nil)
                }.padding(.top, 10)
                statistics.frame(height: geometry.size.height < 600 ? 85 : 100)
                calendarCard
                    .frame(maxHeight: 570).layoutPriority(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(Palette.cream.ignoresSafeArea())
        .foregroundStyle(Palette.ink)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedDay) { day in DayDetailView(day: day.date) }
        .sheet(isPresented: $add) { SessionEditor(date: Date()) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-six-week-month") {
                // March 2026 occupies six rows with a Monday-first calendar.
                month = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
            }
            #endif
        }
    }
    private var statistics: some View {
        let total = PracticeTotal(seconds: model.progress.totalSeconds)
        return HStack(spacing: 0) {
            stat("\(model.progress.currentStreak(now: model.now))", caption: "day streak")
            Rectangle().fill(Palette.line).frame(width: 0.5, height: 34)
            stat("\(model.progress.longestStreak)", caption: "best streak")
            Rectangle().fill(Palette.line).frame(width: 0.5, height: 34)
            stat(total.value, caption: total.unit)
        }
        .frame(maxHeight: .infinity)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.line.opacity(0.38), lineWidth: 0.8))
        .shadow(color: Palette.ink.opacity(0.035), radius: 12, x: 0, y: 4)
    }
    private func stat(_ value: String, caption: String) -> some View {
        VStack(spacing: 7) {
            Text(value).font(.system(.largeTitle, design: .serif)).minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).font(.system(.caption2, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity).padding(.horizontal, 5).accessibilityElement(children: .combine)
    }
    private var calendarCard: some View {
        GeometryReader { geometry in
            let rows = Int(ceil(Double(monthDays.count) / 7))
            let inset: CGFloat = 18
            let sectionSpacing: CGFloat = 14
            let gridSpacing: CGFloat = 6
            let headerHeight: CGFloat = 44
            let weekdayHeight: CGFloat = 18
            let legendHeight: CGFloat = 16
            let reservedHeight = 2 * inset + headerHeight + weekdayHeight + legendHeight
                + 3 * sectionSpacing + CGFloat(rows) * gridSpacing
            let height = max(18, min(62, (geometry.size.height - reservedHeight) / CGFloat(rows)))
            VStack(spacing: sectionSpacing) {
                HStack(spacing: 0) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(.title3, design: .serif)).lineLimit(1).minimumScaleFactor(0.65)
                        .accessibilityIdentifier("calendarMonth")
                    Spacer(minLength: 0)
                    monthButton(-1, symbol: "chevron.left", label: "Previous month")
                    monthButton(1, symbol: "chevron.right", label: "Next month")
                        .disabled(calendar.isDate(month, equalTo: Date(), toGranularity: .month))
                }.frame(height: headerHeight)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: gridSpacing) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.secondary).frame(height: weekdayHeight).accessibilityHidden(true)
                    }
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                        if let day { dayTile(day, height: height) }
                        else { Color.clear.frame(height: height).accessibilityHidden(true) }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                    Text("Daily goal met").font(.system(size: 10)).accessibilityIdentifier("calendarLegend")
                    Spacer(minLength: 3)
                    Text("0").font(.system(size: 9))
                    ForEach(durationShades, id: \.self) { value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.dialSage.opacity(value))
                            .frame(width: 8, height: 8)
                    }
                    Text("30+ min").font(.system(size: 9))
                }.foregroundStyle(Palette.secondary).frame(height: legendHeight)
            }.padding(inset)
        }.background(Palette.paper, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Palette.line.opacity(0.38), lineWidth: 0.8))
            .shadow(color: Palette.ink.opacity(0.035), radius: 12, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 26))
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { gesture in
                        let horizontal = gesture.translation.width
                        let vertical = gesture.translation.height
                        guard abs(horizontal) >= 40, abs(horizontal) > abs(vertical) * 1.2 else { return }
                        changeMonth(by: horizontal < 0 ? 1 : -1)
                    }
            )
    }
    private func changeMonth(by offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month),
              let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start,
              next <= currentMonth else { return }
        month = next
    }
    private func monthButton(_ offset: Int, symbol: String, label: String) -> some View {
        Button { changeMonth(by: offset) } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .regular)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func dayTile(_ date: Date, height: CGFloat) -> some View {
        let key = Day.key(date)
        let seconds = model.progress.secondsByDay[key] ?? 0
        let reached = model.progress.reached(key)
        let intensity = durationShade(for: seconds)
        let future = key > model.today
        return Button { selectedDay = SelectedDay(date: date) } label: {
            VStack(spacing: height < 35 ? 2 : 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.caption, design: .rounded).weight(calendar.isDateInToday(date) ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Image(systemName: reached ? "checkmark" : "circle.fill")
                    .font(.system(size: reached ? 7 : 3, weight: .bold)).opacity(seconds > 0 ? 1 : 0)
            }.frame(maxWidth: .infinity).frame(height: height)
                .foregroundStyle(intensity > 0.65 ? Palette.paper : Palette.ink)
                .background(Palette.dialSage.opacity(intensity), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(calendar.isDateInToday(date) ? Palette.dialSage : .clear, lineWidth: 1))
                .opacity(future ? 0.35 : 1)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(future)
            .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(minutesText(seconds))\(reached ? ", daily goal met" : "")")
    }
    private func durationShade(for seconds: Double) -> Double {
        guard seconds > 0 else { return durationShades[0] }
        let minutes = seconds / 60
        if minutes < 5 { return durationShades[1] }
        if minutes < 10 { return durationShades[2] }
        if minutes < 20 { return durationShades[3] }
        if minutes < 30 { return durationShades[4] }
        return durationShades[5]
    }
}
private struct SelectedDay: Identifiable { let date: Date; var id: Date { date } }

struct DayDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var editing: SessionRecord?
    @State private var adding = false
    @State private var deleting: SessionRecord?
    private var records: [SessionRecord] { model.sessions.filter { $0.dayKey == Day.key(day) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(day.formatted(.dateTime.month(.wide).day())).font(.system(.largeTitle, design: .serif))
                    Text("\(minutesText(records.reduce(0) { $0 + $1.seconds })) of stillness · \(model.progress.goal(on: Day.key(day))) min goal")
                        .font(.subheadline).foregroundStyle(Palette.secondary)
                    if records.isEmpty { Text("An open page. Add a meditation you took away from the app.").foregroundStyle(Palette.secondary).padding(.vertical, 20) }
                    ForEach(records) { session in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(minutesText(session.seconds)).font(.system(.title2, design: .serif))
                                    Text("\(session.completedAt.formatted(date: .omitted, time: .shortened)) · \(session.source == "manual" ? "Added by you" : "Meditation")").font(.caption).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Edit session", systemImage: "pencil") { editing = session }
                                    Button("Delete session", systemImage: "trash", role: .destructive) { deleting = session }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Session options")
                            }
                            if !session.reflection.isEmpty { Text(session.reflection).font(.system(.body, design: .serif)).foregroundStyle(Palette.secondary) }
                        }.paperCard()
                    }
                    Button("Add a meditation") { adding = true }.buttonStyle(PrimaryButton())
                }.padding(24)
            }.background(Palette.cream).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .toolbarBackground(Palette.cream, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .sheet(item: $editing) { session in SessionEditor(date: session.completedAt, existing: session) }
                .sheet(isPresented: $adding) { SessionEditor(date: min(Date(), day)) }
                .alert("Delete this meditation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete", role: .destructive) { if let deleting { model.deleteSession(deleting.id) }; deleting = nil }
                    Button("Keep", role: .cancel) { deleting = nil }
                } message: { Text("Your calendar and streaks will be recalculated.") }
        }.tint(Palette.dialSage).presentationBackground(Palette.cream)
    }
}
