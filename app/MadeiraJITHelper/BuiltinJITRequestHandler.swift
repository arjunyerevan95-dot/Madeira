import Foundation
import StikJIT

/// Separate process used by Madeira's built-in JIT path. A process cannot
/// attach a debugger to itself without deadlocking, so all blocking StikJIT
/// work lives here on one serial queue.
final class BuiltinJITRequestHandler: NSObject, NSExtensionRequestHandling {
    private let queue = DispatchQueue(label: "com.madeira.stikjit.helper", qos: .userInitiated)

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let info = item.userInfo,
            let pidNumber = info["pid"] as? NSNumber,
            let pairingData = info["pairingData"] as? Data,
            let scriptData = info["scriptData"] as? Data
        else {
            finish(context, success: false, message: "Built-in JIT request was malformed.")
            return
        }

        let targetPID = pidNumber.int32Value
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let fm = FileManager.default
                let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let cacheDirectory = library.appendingPathComponent("StikJIT", isDirectory: true)
                try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

                let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: temporary) }

                let pairingURL = temporary.appendingPathComponent("pairingFile.plist")
                let scriptURL = temporary.appendingPathComponent("madeira-jit.js")
                try pairingData.write(to: pairingURL, options: .atomic)
                try scriptData.write(to: scriptURL, options: .atomic)

                let paths = DDIPaths.default(in: cacheDirectory)
                try StikJIT.enableJIT(
                    targetPID: targetPID,
                    pairingFile: pairingURL,
                    ddiPaths: paths,
                    script: .custom(scriptURL),
                    forceScript: false,
                    preparationProgress: { _ in },
                    progress: { _ in }
                )
                self.finish(context, success: true, message: "Built-in StikJIT attached to Madeira.")
            } catch {
                self.finish(context, success: false, message: error.localizedDescription)
            }
        }
    }

    private func finish(_ context: NSExtensionContext, success: Bool, message: String) {
        let result = NSExtensionItem()
        result.userInfo = ["success": success, "message": message]
        context.completeRequest(returningItems: [result])
    }
}
