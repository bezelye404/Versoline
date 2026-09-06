import Foundation

extension Bundle {
    /// Safe resource bundle resolution that works seamlessly across:
    /// - Native Xcode App Target (.xcodeproj) -> Bundle.main
    /// - Packaged macOS .app / .dmg -> Contents/Resources/EasyRSS_EasyRSS.bundle
    /// - Swift Package Manager CLI / Xcode SPM build -> Bundle.module fallback
    static var appResources: Bundle {
        // 1. If running as a native Xcode app target, resources are in Bundle.main
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }

        // 2. If running inside a packaged .app / .dmg, check Contents/Resources/
        if let resourceBundleURL = Bundle.main.url(forResource: "EasyRSS_EasyRSS", withExtension: "bundle"),
           let bundle = Bundle(url: resourceBundleURL) {
            return bundle
        }

        // 3. Fallback for Swift Package Manager development environments
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
