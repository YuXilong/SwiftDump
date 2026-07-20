actor StatusActor {
    let counter: Int

    init(counter: Int) {
        self.counter = counter
    }
}

@main
struct FixtureMain {
    static func main() {
        _ = StatusActor(counter: 1)
    }
}
