import Foundation

/// Which entry of an app's account menu to press to reach an organization. The menu does not say
/// which entry is which organization or which is active, so the app learns it: every switch it
/// makes that ends in a known organization records the label it pressed (`AppConfig.organizationLabels`).
public enum OrganizationPicker {
    /// Labels to try, best first. A learned label for `target` wins; otherwise the labels no other
    /// organization is known to use, then the rest. The label of `current` is left out when known,
    /// since pressing the active organization changes nothing.
    public static func candidates(menu labels: [String], target: String, current: String?,
                                  learned: [String: String]) -> [String] {
        if let label = learned[target], labels.contains(label) { return [label] }
        let usedByOthers = Set(learned.filter { $0.key != target }.map(\.value))
        let activeLabel = current.flatMap { learned[$0] }
        let free = labels.filter { !usedByOthers.contains($0) && $0 != activeLabel }
        let rest = labels.filter { !free.contains($0) && $0 != activeLabel }
        return free + rest
    }
}
