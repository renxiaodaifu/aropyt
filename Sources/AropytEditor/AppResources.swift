import Foundation

enum AppResources {
    // Keep the SwiftPM lookup lazy: its generated accessor traps if the build
    // directory has moved, even when the packaged resources are present.
    static let bundle = resolve(mainBundle: .main, swiftPMBundle: .module)

    static func resolve(mainBundle: Bundle, swiftPMBundle: @autoclosure () -> Bundle) -> Bundle {
        let name = "AropytEditor_AropytEditor.bundle"
        let candidates = [
            mainBundle.resourceURL?.appendingPathComponent(name),
            mainBundle.bundleURL.appendingPathComponent(name),
        ].compactMap { $0 }

        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return swiftPMBundle()
    }

    static var resourceDirectory: URL {
        let candidates = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
        for candidate in candidates {
            for directory in [candidate, candidate.appendingPathComponent("Contents/Resources")] {
                if FileManager.default.fileExists(
                    atPath: directory.appendingPathComponent("marked.umd.js").path
                ) {
                    return directory
                }
            }
        }
        return bundle.resourceURL ?? bundle.bundleURL
    }
}
