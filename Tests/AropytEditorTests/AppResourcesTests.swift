import Foundation
import Testing
@testable import AropytEditor

@Suite("App resources")
struct AppResourcesTests {
    @Test(arguments: ["Contents/Resources", ""])
    func relocatedAppLoadsResourcesWithoutSwiftPMFallback(resourcePath: String) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let app = root.appendingPathComponent("Relocated.app")
        let contents = app.appendingPathComponent("Contents")
        try manager.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.aropyt.resource-test.\(UUID().uuidString)",
                "CFBundlePackageType": "APPL",
            ],
            format: .xml,
            options: 0
        )
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        let destination = app.appendingPathComponent(resourcePath)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let resourceURL = destination.appendingPathComponent("AropytEditor_AropytEditor.bundle")
        try manager.copyItem(at: AppResources.bundle.bundleURL, to: resourceURL)
        let mainBundle = try #require(Bundle(url: app))

        func unexpectedFallback() -> Bundle {
            Issue.record("A relocated app must not access the generated SwiftPM bundle accessor")
            return AppResources.bundle
        }
        let resources = AppResources.resolve(
            mainBundle: mainBundle,
            swiftPMBundle: unexpectedFallback()
        )
        #expect(resources.bundleURL.standardizedFileURL == resourceURL.standardizedFileURL)
        try verifyAssets(in: resources)
    }

    @Test func missingPackagedBundleUsesSwiftPMFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mainBundle = try #require(Bundle(url: directory))
        var didUseFallback = false
        func fallback() -> Bundle {
            didUseFallback = true
            return AppResources.bundle
        }
        let resources = AppResources.resolve(mainBundle: mainBundle, swiftPMBundle: fallback())
        #expect(didUseFallback)
        #expect(resources.bundleURL == AppResources.bundle.bundleURL)
    }

    @Test func developmentResourcesIncludePreviewAssetsAndLocalizations() throws {
        try verifyAssets(in: AppResources.bundle)
        #expect(FileManager.default.fileExists(
            atPath: AppResources.resourceDirectory.appendingPathComponent("marked.umd.js").path
        ))
    }

    private func verifyAssets(in bundle: Bundle) throws {
        #expect(bundle.url(forResource: "marked.umd", withExtension: "js") != nil)
        #expect(bundle.url(forResource: "AropytEditor", withExtension: "icns") != nil)
        for (language, expected) in [("en", "File"), ("zh-hans", "文件")] {
            let path = try #require(bundle.path(forResource: language, ofType: "lproj"))
            let localization = try #require(Bundle(path: path))
            #expect(localization.localizedString(forKey: "menu.file", value: nil, table: "Localizable") == expected)
        }
    }
}
