import Foundation

/// Pure layout math for the weekly planning grid.
///
/// This is deliberately free of SwiftUI so it can be unit tested. The view is responsible
/// for drawing rows; this type decides *what the rows are*.
///
/// Why this exists: the grid previously derived one time row per distinct start time,
/// matching on exact hour AND minute. Imported daily schedules rarely line up to the minute
/// across days — a block that starts at 9:45 on Monday and 9:50 on Wednesday produced two
/// separate rows, each mostly empty. Clustering nearby start times into a single row keeps
/// the grid readable without moving any lesson to a time the teacher did not schedule.
struct WeeklyGridLayout {
    /// Start times within this many minutes of a slot's anchor share a row.
    ///
    /// 15 minutes is chosen to absorb the small drift seen in imported schedules while
    /// keeping genuinely distinct blocks apart — a 9:45 math block and a 10:45 science
    /// block will never merge.
    static let defaultToleranceMinutes = 15

    /// One row of the grid: a cluster of assignments whose start times are close together.
    struct Slot: Identifiable, Equatable {
        /// Minutes from midnight of the earliest start in the cluster. Unique per slot,
        /// stable across redraws, and naturally sortable — so it doubles as the identity.
        let id: Int
        /// Earliest start among the assignments in this cluster.
        let displayStart: Date
        /// Latest end among the assignments in this cluster.
        let displayEnd: Date

        /// Two-line label, matching the existing grid presentation.
        var label: String {
            let start = displayStart.formatted(.dateTime.hour().minute())
            let end = displayEnd.formatted(.dateTime.hour().minute())
            return "\(start)\n\(end)"
        }
    }

    /// The grid's time rows, earliest first.
    let slots: [Slot]

    private let slotIDByAssignmentID: [UUID: Int]
    private let calendar: Calendar

    init(
        assignments: [WeeklyLessonAssignment],
        calendar: Calendar = .current,
        toleranceMinutes: Int = WeeklyGridLayout.defaultToleranceMinutes
    ) {
        self.calendar = calendar

        guard !assignments.isEmpty else {
            self.slots = []
            self.slotIDByAssignmentID = [:]
            return
        }

        // Sort by time of day so clustering can sweep forward once.
        let sorted = assignments.sorted {
            Self.minutesFromMidnight($0.start, calendar: calendar)
                < Self.minutesFromMidnight($1.start, calendar: calendar)
        }

        // Greedy clustering anchored on the FIRST start in each cluster, not the previous
        // one. Anchoring on the previous start would let a chain of small gaps drift
        // arbitrarily far — 8:00, 8:14, 8:28, 8:42 would all collapse into one row.
        var clusters: [[WeeklyLessonAssignment]] = []
        var current: [WeeklyLessonAssignment] = []
        var anchorMinutes: Int?

        for assignment in sorted {
            let minutes = Self.minutesFromMidnight(assignment.start, calendar: calendar)
            if let anchor = anchorMinutes, minutes - anchor <= toleranceMinutes {
                current.append(assignment)
            } else {
                if !current.isEmpty { clusters.append(current) }
                current = [assignment]
                anchorMinutes = minutes
            }
        }
        if !current.isEmpty { clusters.append(current) }

        var builtSlots: [Slot] = []
        var index: [UUID: Int] = [:]

        for cluster in clusters {
            // A cluster is non-empty by construction, but avoid force-unwrapping.
            guard
                let earliestStart = cluster.map(\.start).min(),
                let latestEnd = cluster.map(\.end).max()
            else { continue }

            let slotID = Self.minutesFromMidnight(earliestStart, calendar: calendar)
            builtSlots.append(Slot(id: slotID, displayStart: earliestStart, displayEnd: latestEnd))
            for assignment in cluster {
                index[assignment.id] = slotID
            }
        }

        self.slots = builtSlots.sorted { $0.id < $1.id }
        self.slotIDByAssignmentID = index
    }

    /// Assignments belonging to one grid cell, sorted for stable display.
    ///
    /// `titleForSorting` breaks ties between assignments that start at the same moment, so
    /// the order does not flicker between redraws.
    func assignments(
        from all: [WeeklyLessonAssignment],
        forDay day: Date,
        slot: Slot,
        titleForSorting: (WeeklyLessonAssignment) -> String
    ) -> [WeeklyLessonAssignment] {
        all
            .filter { slotIDByAssignmentID[$0.id] == slot.id && calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { lhs, rhs in
                lhs.start == rhs.start
                    ? titleForSorting(lhs) < titleForSorting(rhs)
                    : lhs.start < rhs.start
            }
    }

    /// The slot an assignment was placed in, if any. Exposed for testing and diagnostics.
    func slotID(for assignment: WeeklyLessonAssignment) -> Int? {
        slotIDByAssignmentID[assignment.id]
    }

    private static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
