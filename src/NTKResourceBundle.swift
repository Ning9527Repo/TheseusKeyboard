import Foundation

// Replaces only SwiftPM's generated resource accessor; upstream remains byte-identical.
// Resolved beside the actual loaded dylib, so no hard-coded /var/jb or jbroot UUID.
extension Bundle {
    static let module: Bundle = {
        let base = URL(fileURLWithPath: String(cString: NTKResourceDirectory()), isDirectory: true)
        guard let bundle = Bundle(url: base.appendingPathComponent("TheseusKeyboard.bundle", isDirectory: true)) else {
            // An empty bundle must not silently select another application's shader.
            fatalError("TheseusKeyboard: resource bundle is missing")
        }
        return bundle
    }()
}
