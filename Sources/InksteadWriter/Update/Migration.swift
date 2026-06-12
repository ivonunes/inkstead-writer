import Foundation

public enum MigrationAction: Equatable {
    case rename(from: String, to: String)
    case delete(path: String)
    case write(path: String, content: String, reason: String)
    case manual(path: String?, message: String)

    public var description: String {
        switch self {
        case .rename(let from, let to):
            "Rename \(from) -> \(to)"
        case .delete(let path):
            "Remove \(path)"
        case .write(let path, _, let reason):
            "Update \(path): \(reason)"
        case .manual(let path, let message):
            [path, message].compactMap { $0 }.joined(separator: ": ")
        }
    }
}

extension MigrationAction {
    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }
}

public struct MigrationPlan: Equatable {
    public var currentVersion: String
    public var targetVersion: String
    public var actions: [MigrationAction]

    public var isCurrent: Bool { actions.isEmpty }
    public var hasManualActions: Bool { actions.contains(where: \.isManual) }
}

public struct MigrationRunResult: Equatable {
    public var plan: MigrationPlan
    public var changedFiles: [String]
    public var dryRun: Bool
    public var checkOnly: Bool
}

public enum MigrationRunner {
    public static func run(
        root: URL,
        targetVersion: String = InksteadWriterMetadata.currentVersion,
        checkOnly: Bool = false,
        dryRun: Bool = false
    ) throws -> MigrationRunResult {
        let config = try ConfigLoader.load(root: root)
        let plan = try MigrationPlanner.plan(root: root, config: config, targetVersion: targetVersion)
        guard !plan.actions.isEmpty, !checkOnly, !dryRun else {
            return MigrationRunResult(plan: plan, changedFiles: [], dryRun: dryRun, checkOnly: checkOnly)
        }
        let changed = try MigrationPlanner.apply(plan, root: root)
        return MigrationRunResult(plan: plan, changedFiles: changed, dryRun: false, checkOnly: false)
    }
}
