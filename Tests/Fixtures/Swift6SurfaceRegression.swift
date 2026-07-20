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

protocol RootProtocol {}
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
    }
}

@main
struct FixtureMain {
    static func main() {
        let closure: AsyncSendableClosure = { "done" }
        _ = ObjectiveCarrier(
            pair: (7, "swift"),
            handler: closure,
            failure: FixtureError.sample,
            sendableType: String.self,
            genericBox: GenericBox(item: "payload")
        )
        _ = PayloadlessColor.red
        _ = PayloadMessage.text("hello")
    }
}
