import Combine
import EventKit
import Foundation

struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let allDay: Bool
    let calendar: String
}
struct AgendaReminder: Identifiable {
    let id: String
    let title: String
    let due: Date?
}

@MainActor
final class CalendarAccessStore: ObservableObject {
    @Published private(set) var calendarAllowed = false
    @Published private(set) var remindersAllowed = false
    @Published private(set) var isRequestingCalendar = false
    @Published private(set) var isRequestingReminders = false
    @Published private(set) var message: String?
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var reminders: [AgendaReminder] = []
    @Published private(set) var isLoading = false
    @Published var newReminder = ""
    private let eventStore = EKEventStore()
    private var observer: AnyCancellable?

    init() {
        reload()
        observer = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reload() }
    }
    func requestCalendarAccess() {
        guard !calendarAllowed, !isRequestingCalendar else { return }
        isRequestingCalendar = true
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingCalendar = false
                self.message = granted ? nil : (error?.localizedDescription ?? "Calendar access was not granted. You can allow it in System Settings → Privacy & Security → Calendars.")
                self.reload()
            }
        }
    }
    func requestRemindersAccess() {
        guard !remindersAllowed, !isRequestingReminders else { return }
        isRequestingReminders = true
        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRequestingReminders = false
                self.message = granted ? nil : (error?.localizedDescription ?? "Reminders access was not granted. You can allow it in System Settings → Privacy & Security → Reminders.")
                self.reload()
            }
        }
    }
    func reload() {
        calendarAllowed = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAllowed = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        if calendarAllowed {
            let now = Date()
            let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
            let predicate = eventStore.predicateForEvents(withStart: Calendar.current.startOfDay(for: now), end: end, calendars: nil)
            events = eventStore.events(matching: predicate).filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }.prefix(30).enumerated().map { index, event in
                    AgendaEvent(id: "\(event.eventIdentifier ?? "event")-\(index)", title: event.title ?? "Untitled event", start: event.startDate, allDay: event.isAllDay, calendar: event.calendar.title)
                }
        } else { events = [] }
        if remindersAllowed, !isLoading {
            isLoading = true
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            eventStore.fetchReminders(matching: predicate) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    guard self.remindersAllowed else { self.reminders = []; return }
                    self.reminders = (result ?? []).map {
                        AgendaReminder(id: $0.calendarItemIdentifier, title: $0.title ?? "Untitled reminder", due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) })
                    }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                }
            }
        } else if !remindersAllowed { reminders = [] }
    }
    func complete(_ reminder: AgendaReminder) {
        guard remindersAllowed, let item = eventStore.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        do { try eventStore.save(item, commit: true); message = nil; reload() }
        catch { item.isCompleted = false; message = error.localizedDescription }
    }
    func addReminder() {
        let title = newReminder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, remindersAllowed else { return }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            message = "Create a reminders list in Apple's Reminders app first."
            return
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        do { try eventStore.save(reminder, commit: true); newReminder = ""; message = nil; reload() }
        catch { message = error.localizedDescription }
    }
}
