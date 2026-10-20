import SwiftUI

struct AgendaView: View {
    @ObservedObject var store: CalendarAccessStore
    let remindersMode: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(remindersMode ? "Reminders" : "Upcoming Events").font(.title2.bold())
                Spacer()
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }
            if remindersMode {
                if store.remindersAllowed {
                    HStack {
                        TextField("New reminder", text: $store.newReminder).onSubmit(store.addReminder)
                        Button("Add", action: store.addReminder).disabled(store.newReminder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.reminders) { reminder in
                                HStack(alignment: .top) {
                                    Button { store.complete(reminder) } label: { Image(systemName: "circle") }.buttonStyle(.plain).help("Mark complete")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(reminder.title)
                                        if let due = reminder.due { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }.frame(maxHeight: 300)
                    if store.reminders.isEmpty { Text(store.isLoading ? "Loading reminders…" : "No pending reminders.").foregroundStyle(.secondary) }
                } else {
                    Text("Connect Reminders to see your tasks, add new ones and mark them complete.").foregroundStyle(.secondary)
                    Button("Connect Reminders", action: store.requestRemindersAccess).buttonStyle(.borderedProminent).disabled(store.isRequestingReminders)
                }
            } else {
                if store.calendarAllowed {
                    Text("Next 7 days").font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(store.events) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.headline)
                                    Text(event.start.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened) + (event.allDay ? " · All day" : "")).font(.caption)
                                    Text(event.calendar).font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
                    }.frame(maxHeight: 330)
                    if store.events.isEmpty { Text("No upcoming events in the next 7 days.").foregroundStyle(.secondary) }
                } else {
                    Text("Connect Calendar to show your upcoming events. The date tile works without access.").foregroundStyle(.secondary)
                    Button("Connect Calendar", action: store.requestCalendarAccess).buttonStyle(.borderedProminent).disabled(store.isRequestingCalendar)
                }
            }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }.padding(22).frame(minHeight: 220)
    }
}
