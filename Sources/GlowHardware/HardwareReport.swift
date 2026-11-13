import Foundation
import IOKit

public enum HardwareEffect: String, CaseIterable, Sendable {
    case breathe
    case pulse
}

public struct HardwareReport: Sendable {
    public let modelIdentifier: String
    public let osVersion: String
    public let logoDetected: Bool
    public let directControlAvailable: Bool
    public let candidateNodes: [String]
    public let summary: String
    public let details: String
}

public enum HardwareControlError: LocalizedError {
    case unavailable(String)
    case competingApplication(String)
    case commandRejected(String)
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .competingApplication(let name):
            return "Quit \(name) before controlling the logo so the two apps do not compete."
        case .commandRejected(let key):
            return "macOS did not confirm the logo command (\(key)). Control has stopped."
        case .invalidDuration: return "Choose a finite cycle duration between 2 and 20 seconds."
        }
    }
}

struct HardwareInventory {
    struct Node {
        let name: String
        let path: String
        let plane: String
        let properties: [String]
    }

    let nodes: [Node]
    let logoDetected: Bool

    static func read() -> HardwareInventory {
        var nodes: [Node] = []
        var iterator: io_iterator_t = 0
        if let matching = IOServiceMatching("AppleARMPWMDevice"),
           IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            while true {
                let entry = IOIteratorNext(iterator)
                guard entry != 0 else { break }
                nodes.append(readNode(entry, plane: kIOServicePlane))
                IOObjectRelease(entry)
            }
        }

        // Read the device tree independently: a driver service may be absent even when
        // firmware describes a device. Neither presence nor absence proves per-LED wiring.
        var treeIterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        if root != 0 {
            defer { IOObjectRelease(root) }
            if IORegistryEntryCreateIterator(root, kIODeviceTreePlane,
                                             IOOptionBits(kIORegistryIterateRecursively),
                                             &treeIterator) == KERN_SUCCESS {
                defer { IOObjectRelease(treeIterator) }
                while true {
                    let entry = IOIteratorNext(treeIterator)
                    guard entry != 0 else { break }
                    let name = registryName(entry).lowercased()
                    if name.contains("bklb") || name.contains("light-emitter") || name.contains("logo") {
                        nodes.append(readNode(entry, plane: kIODeviceTreePlane))
                    }
                    IOObjectRelease(entry)
                }
            }
        }
        nodes.sort { ($0.plane, $0.path) < ($1.plane, $1.path) }
        let hasLogo = nodes.contains {
            $0.plane == kIOServicePlane &&
                ($0.name == "bklb-backlight" || $0.name.hasPrefix("bklb-backlight@"))
        }
        return HardwareInventory(nodes: nodes, logoDetected: hasLogo)
    }

    static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "Unknown Mac" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Unknown Mac" }
        return String(cString: bytes)
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { return "unnamed" }
        return String(cString: name)
    }

    private static func readNode(_ entry: io_registry_entry_t, plane: String) -> Node {
        let name = registryName(entry)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let path: String
        if IORegistryEntryGetPath(entry, plane, &pathBuffer) == KERN_SUCCESS {
            path = String(cString: pathBuffer)
        } else {
            path = name
        }

        // Deliberately avoid dumping the registry. In particular, hardware serials,
        // UUIDs, firmware blobs and unrelated properties never enter the report.
        let allowed: Set<String> = [
            "enabled", "high-period", "low-period", "reg", "compatible",
            "pwm-channel", "pwm-id", "channel", "channel-count", "channels",
            "#pwm-cells", "clock-frequency", "IOClass", "IOProviderClass"
        ]
        var properties: Unmanaged<CFMutableDictionary>?
        var lines: [String] = []
        if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let values = properties?.takeRetainedValue() as? [String: Any] {
            for key in values.keys.sorted() where allowed.contains(key) {
                guard let value = values[key] else { continue }
                if let data = value as? Data {
                    if key == "compatible", let string = String(data: data, encoding: .utf8) {
                        lines.append("\(key): \(string.replacingOccurrences(of: "\0", with: ", ").prefix(256))")
                    } else {
                        lines.append("\(key): 0x" + data.prefix(32).map { String(format: "%02x", $0) }.joined())
                    }
                } else if let number = value as? NSNumber {
                    lines.append("\(key): \(number)")
                } else if let string = value as? String {
                    lines.append("\(key): \(string.prefix(256))")
                } else if let numbers = value as? [NSNumber] {
                    lines.append("\(key): \(numbers.prefix(16).map(\.stringValue).joined(separator: ", "))")
                }
            }
        }
        return Node(name: name, path: path, plane: plane, properties: lines)
    }
}
