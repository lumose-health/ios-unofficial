import Foundation

/// A Driver that maps its device's own dose-category labels onto the platform
/// vocabulary.
///
/// Mirrors Android's `BolusCategoryProvider`
/// (`plugins/pump-driver-api/.../capabilities/BolusCategoryProvider.kt`) — for
/// example, Tandem's `CONTROL_IQ` label maps to ``DoseCategory/autoCorrection``.
/// The rename is explained on ``Capability/doseCategoryProvider``: the word the
/// Android capability is named for is a denied symbol in
/// `scripts/guards/driver_guards.sh`, and a read-side name that forces the
/// delivery-verb guard to carry an exemption is the wrong name.
///
/// This capability exists so insulin summaries can be device-agnostic without
/// throwing away device-specific detail: the platform stores the mapped category
/// and the device's verbatim label side by side (``DoseRecord``).
public protocol DoseCategoryProvider: Sendable {

    /// The device-specific category labels this Driver declares, verbatim.
    var declaredCategories: Set<String> { get }

    /// The platform category for one of ``declaredCategories``, or `nil` when the
    /// Driver does not recognise the label.
    ///
    /// Pure: same label in, same category out, no device contact. Returning `nil`
    /// is the correct answer for an unrecognised label — the caller records
    /// ``DoseCategory/other`` and keeps the verbatim label, rather than the
    /// Driver guessing the nearest-looking category and producing a summary that
    /// is confidently wrong.
    func platformCategory(for declaredCategory: String) -> DoseCategory?
}
