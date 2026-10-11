import Foundation
import CoreServices
import UniformTypeIdentifiers

struct MarkdownAssociation: Codable {
    let contentType: String
    let applicationPath: String
}

func defaultHandler(for contentType: String) -> String? {
    LSCopyDefaultRoleHandlerForContentType(contentType as CFString, .all)?
        .takeRetainedValue() as String?
}

func isApplication(_ path: String, bundleID: String) -> Bool {
    Bundle(path: path)?.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
}

func check(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
        throw NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "\(operation) failed (OSStatus \(status))"]
        )
    }
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count >= 4 else {
        throw NSError(domain: "Packaging", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Usage: preserve-markdown-default snapshot|restore <snapshot.json> <bundle-id> [fallback-app]"
        ])
    }
    let snapshot = URL(fileURLWithPath: arguments[2])
    let bundleID = arguments[3]
    switch arguments[1] {
    case "snapshot":
        let types = Set(["net.daringfireball.markdown", UTType(filenameExtension: "md")?.identifier].compactMap { $0 })
        var associations: [MarkdownAssociation] = []
        for type in types.sorted() {
            guard let handler = defaultHandler(for: type) else {
                throw NSError(domain: "Packaging", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot read the default application for \(type)"
                ])
            }
            guard handler.caseInsensitiveCompare(bundleID) == .orderedSame else { continue }
            guard let app = LSCopyDefaultApplicationURLForContentType(type as CFString, .all, nil)?
                .takeRetainedValue() as URL? else {
                throw NSError(domain: "Packaging", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot locate the default application for \(type)"
                ])
            }
            associations.append(MarkdownAssociation(contentType: type, applicationPath: app.path))
        }
        try JSONEncoder().encode(associations).write(to: snapshot, options: .atomic)
    case "restore":
        let associations = try JSONDecoder().decode([MarkdownAssociation].self, from: Data(contentsOf: snapshot))
        for association in associations {
            // Avoid changing settings when packaging has left the default intact.
            if defaultHandler(for: association.contentType)?.caseInsensitiveCompare(bundleID) == .orderedSame {
                continue
            }
            let candidates = [
                association.applicationPath,
                "/Applications/AropytEditor.app",
                arguments.count > 4 ? arguments[4] : "",
            ]
            guard let path = candidates.first(where: { isApplication($0, bundleID: bundleID) }) else {
                throw NSError(domain: "Packaging", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot restore Markdown defaults: Aropyt is no longer available"
                ])
            }
            try check(LSRegisterURL(URL(fileURLWithPath: path) as CFURL, true), operation: "Register Aropyt")
            try check(LSSetDefaultRoleHandlerForContentType(
                association.contentType as CFString, .all, bundleID as CFString
            ), operation: "Restore Markdown default")
            guard defaultHandler(for: association.contentType)?.caseInsensitiveCompare(bundleID) == .orderedSame else {
                throw NSError(domain: "Packaging", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "macOS did not restore the Markdown default"
                ])
            }
            print("Restored Aropyt as the existing default for \(association.contentType)")
        }
    default:
        throw NSError(domain: "Packaging", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unknown operation"])
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
