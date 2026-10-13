import Foundation

// The session sidecar's identity (4D side): stays in mac4DSTEM, because the
// schema marker names what mac4DSTEM writes. HDF5Types.swift (the HDF5 C ABI
// aliases and HDF5Serial lock) moves to SpectroKit at the S1 extraction.

/// The session sidecar's identity, shared by the writer that stamps it and
/// the reader that recognises it. This file is the one `Core/Data` source
/// every standalone harness that compiles either side already includes, so
/// hosting the constants here costs no build-list edit anywhere — the
/// alternative (duplicated literals with "change one, change both" comments)
/// is exactly how a format constant drifts and recognition silently stops
/// firing. // v2 S4
// `nonisolated`: pure constants read from the reader actor and nonisolated
// writer statics; MainActor default isolation would wall them off (the S3
// rider's pattern for pure data types).
package nonisolated enum SessionSidecarFormat {
    /// Root-group attribute stamped on every file the sidecar writer
    /// produces. Its *presence* is the identity marker; its value is the
    /// schema version.
    package static let schemaAttribute = "mac4dstem_session_schema"
    /// The writer's root group name.
    package static let rootGroupName = "braggvectors_root"
    /// A sidecar is named `<stem>.mac4dstem.h5` beside its source, where the
    /// stem is the source name with *any* extension stripped — the source is
    /// not necessarily an `.h5` file.
    package static let nameSuffix = ".mac4dstem.h5"

    /// The name to seed an `NSSavePanel` with when proposing `url`.
    ///
    /// The panel appends the extension its `allowedContentTypes` requires, so
    /// the seed must NOT already carry it. Seeding the full
    /// `<stem>.mac4dstem.h5` is what produced `<stem>.mac4dstem.h5.h5` on
    /// every first save — reported 2026-09-07 on the COPL cube and seen again
    /// 2026-09-09 on `downsample_Si_SiGe_exp` (`docs/open-items.md`). Only the
    /// LAST extension comes off, so a sidecar already carrying the doubled
    /// name keeps it rather than being silently renamed under the owner.
    package static func savePanelSeedName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Schema versioning (v2 S5)

    /// The schema this build writes AND the newest it understands. History,
    /// so the numbers keep meaning: "5" was v1's format — and it stayed "5"
    /// across the 2026-08-18 load-specification addition, which is exactly
    /// the defect that made this constant necessary (a stamp that never moves
    /// identifies nothing). "6" is v2's: load specification honoured on
    /// restore, plus the replay record. "7" adds the lineage graph
    /// (`lineageAttribute`, ADR 047): additive and safe to ignore, so the
    /// minimum-reader marker did NOT move with it — v4.0.0 (schema 6) opens a
    /// v7 file and restores everything it did before.
    package static let currentSchema = 7

    /// Root attribute naming the OLDEST schema a reader may implement and
    /// still interpret this file **without misreading it** — not the newest
    /// feature present. Additive, safe-to-ignore content (the replay record)
    /// does not raise it; content that is dangerous to ignore (a reduced load
    /// specification: ignoring it restores scan-indexed results at wrong
    /// positions, the §5 evidence) does. Readers refuse, with both numbers
    /// named, when this exceeds `currentSchema` — never partially restore.
    /// The unfixable half, stated: v1.0.0 checks nothing, so this marker
    /// protects the NEXT format change, not the last one.
    package static let minimumReaderAttribute = "mac4dstem_min_reader_schema"

    /// Root attribute carrying the serialized `SessionReplayRecord` (JSON).
    package static let replayRecordAttribute = "mac4dstem_replay_record"

    /// Root attribute carrying the serialized `SessionLineage` (JSON), schema 7.
    /// The linear record above is its projection and is still written with it.
    package static let lineageAttribute = "mac4dstem_lineage"
    // (The min-reader VALUE for a given specification is computed by
    //  `BraggVectorEMDWriter.minimumReaderSchema(for:)` — this file stays
    //  constants-only so harnesses can compile it without `LoadSpecification`.)
}
