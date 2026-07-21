import Foundation

enum PayloadlessColor {
    case red
    case green
}

enum PayloadMessage {
    case text(String)
    case count(Int)
}

struct GenericBox<T> {
    let item: T
}

typealias PairAlias = (Int, String)
typealias AsyncSendableClosure = @Sendable () async -> String

protocol RootProtocol {
    func rootRequirement(seed: Int) -> String
}
protocol ChildProtocol: RootProtocol {}

enum FixtureError: Error {
    case sample
}

final class ObjectiveCarrier: NSObject, ChildProtocol {
    let pair: PairAlias
    let handler: AsyncSendableClosure
    let failure: any Error
    let sendableType: Sendable.Type
    let genericBox: GenericBox<String>
    var mutableText: String

    var computedSummary: String {
        get { "\(pair.0)-\(mutableText)" }
        set { mutableText = newValue }
    }

    init(
        pair: PairAlias,
        handler: @escaping AsyncSendableClosure,
        failure: any Error,
        sendableType: Sendable.Type,
        genericBox: GenericBox<String>
    ) {
        self.pair = pair
        self.handler = handler
        self.failure = failure
        self.sendableType = sendableType
        self.genericBox = genericBox
        self.mutableText = genericBox.item
    }

    func rootRequirement(seed: Int) -> String {
        "\(seed)-\(mutableText)"
    }

    func instanceMethod(box: GenericBox<String>, flag: Bool) async throws -> GenericBox<String> {
        if flag {
            return box
        }
        throw FixtureError.sample
    }

    static func staticMethod(value: String) -> GenericBox<String> {
        GenericBox(item: value)
    }

    func genericMethod<T: Sendable>(value: T) -> T {
        value
    }

    class func classMethod(code: Int) -> String {
        "code-\(code)"
    }
}

@main
struct FixtureMain {
    static func main() {
        let closure: AsyncSendableClosure = { "done" }
        let carrier = ObjectiveCarrier(
            pair: (7, "swift"),
            handler: closure,
            failure: FixtureError.sample,
            sendableType: String.self,
            genericBox: GenericBox(item: "payload")
        )
        carrier.computedSummary = "updated"
        _ = carrier.computedSummary
        _ = carrier.rootRequirement(seed: 3)
        _ = ObjectiveCarrier.staticMethod(value: "factory")
        _ = carrier.genericMethod(value: "generic")
        _ = ObjectiveCarrier.classMethod(code: 9)
        let task = Task {
            _ = try? await carrier.instanceMethod(box: GenericBox(item: "async"), flag: true)
        }
        _ = task
        _ = PayloadlessColor.red
        _ = PayloadMessage.text("hello")
    }
}
