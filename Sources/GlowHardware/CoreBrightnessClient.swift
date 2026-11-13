import Foundation
import ObjectiveC

// The selector bindings and keyboard correction follow LogoLight's MIT-licensed
// research. See ThirdParty/LogoLight-LICENSE.txt. No private interface is assumed
// present: selectors, keyboard IDs and readback are checked before control starts.
@MainActor
final class CoreBrightnessClient {
    private static let frameworkLoaded = dlopen(
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY
    ) != nil
    private typealias CopyFunction = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias SetFunction = @convention(c) (AnyObject, Selector, AnyObject, NSString) -> Bool
    private typealias KeyboardSetFunction = @convention(c) (AnyObject, Selector, AnyObject, NSString, UInt64) -> Bool
    private typealias KeyboardIDsFunction = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private let client: NSObject
    private let copySelector = NSSelectorFromString("copyPropertyForKey:")
    private let setSelector = NSSelectorFromString("setProperty:forKey:")
    private let keyboardSelector = NSSelectorFromString("setProperty:withKey:keyboardID:")
    private let copyFunction: CopyFunction
    private let setFunction: SetFunction
    private let keyboardFunction: KeyboardSetFunction
    private let keyboardIDs: [UInt64]

    init?() {
        guard Self.frameworkLoaded,
              let type = NSClassFromString("BrightnessSystemClient") as? NSObject.Type,
              Self.hasABI(type, selector: copySelector, result: "@", arguments: ["@", ":", "@"]),
              Self.hasABI(type, selector: setSelector, result: "B", arguments: ["@", ":", "@", "@"]),
              Self.hasABI(type, selector: keyboardSelector, result: "B", arguments: ["@", ":", "@", "@", "Q"])
        else { return nil }
        client = type.init()
        copyFunction = unsafeBitCast(client.method(for: copySelector), to: CopyFunction.self)
        setFunction = unsafeBitCast(client.method(for: setSelector), to: SetFunction.self)
        keyboardFunction = unsafeBitCast(client.method(for: keyboardSelector), to: KeyboardSetFunction.self)

        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard let keyboardType = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              Self.hasABI(keyboardType, selector: idsSelector, result: "@", arguments: ["@", ":"])
        else { return nil }
        let keyboardClient = keyboardType.init()
        let copyIDs = unsafeBitCast(keyboardClient.method(for: idsSelector), to: KeyboardIDsFunction.self)
        guard let ids = copyIDs(keyboardClient, idsSelector)?.takeRetainedValue() as? [NSNumber],
              !ids.isEmpty else { return nil }
        keyboardIDs = ids.map(\.uint64Value)
        guard let mode = mode, [0, 2].contains(mode), factor != nil else { return nil }
    }

    /// Responding to a selector alone does not establish its C calling convention.
    /// A future OS signature change must disable this backend before an IMP is cast.
    /// B is the one-byte C/Objective-C bool used on the supported Apple silicon Macs;
    /// Q is the unsigned 64-bit keyboard identifier. Unknown encodings fail closed.
    static func hasABI(_ type: AnyClass, selector: Selector,
                       result: String, arguments: [String]) -> Bool {
        guard let method = class_getInstanceMethod(type, selector),
              method_getNumberOfArguments(method) == arguments.count else { return false }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == result else { return false }
        for (index, expected) in arguments.enumerated() {
            guard let argumentType = method_copyArgumentType(method, UInt32(index)) else { return false }
            let actual = String(cString: argumentType)
            free(argumentType)
            guard actual == expected else { return false }
        }
        return true
    }

    var mode: Int? { (read("LEBacklightMode") as? NSNumber)?.intValue }
    var factor: Double? {
        guard let value = ((read("LEPWMState") as? [String: Any])?["Factor"] as? NSNumber)?.doubleValue,
              value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    func read(_ key: String) -> Any? {
        copyFunction(client, copySelector, key as NSString)?.takeRetainedValue()
    }

    func set(_ value: NSNumber, key: String) throws {
        guard setFunction(client, setSelector, value, key as NSString) else {
            throw HardwareControlError.commandRejected(key)
        }
    }

    func fade(lit: Bool, duration: Double, keepKeyboardLit: Bool) throws {
        try set(NSNumber(value: duration), key: "LEPWMFactorFadeDuration")
        try set(NSNumber(value: lit ? 2 : 1), key: "DisplayLogicalState")
        if !lit && keepKeyboardLit {
            for id in keyboardIDs {
                guard keyboardFunction(client, keyboardSelector, NSNumber(value: 2),
                                       "DisplayLogicalState", id) else {
                    throw HardwareControlError.commandRejected("keyboard correction")
                }
            }
        }
    }
}
