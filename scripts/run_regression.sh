#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTDUMP_BIN="${SWIFTDUMP_BIN:-}"
BUILD_DIR="$ROOT_DIR/Tests/.build"
DEMO_BIN="$ROOT_DIR/Demo/test"
DEMO_OUTPUT="$BUILD_DIR/demo.output.txt"
SURFACE_FIXTURE_SRC="$ROOT_DIR/Tests/Fixtures/Swift6SurfaceRegression.swift"
SURFACE_FIXTURE_BIN="$BUILD_DIR/Swift6SurfaceRegression"
SURFACE_STRIPPED_BIN="$BUILD_DIR/Swift6SurfaceRegression.stripped"
SURFACE_TRUNCATED_BIN="$BUILD_DIR/Swift6SurfaceRegression.truncated"
SURFACE_OUTPUT="$BUILD_DIR/swift6-surface.output.txt"
SURFACE_STRIPPED_OUTPUT="$BUILD_DIR/swift6-surface-stripped.output.txt"
SURFACE_TRUNCATED_OUTPUT="$BUILD_DIR/swift6-surface-truncated.output.txt"
ACTOR_FIXTURE_SRC="$ROOT_DIR/Tests/Fixtures/Swift6ActorRegression.swift"
ACTOR_FIXTURE_BIN="$BUILD_DIR/Swift6ActorRegression"
ACTOR_OUTPUT="$BUILD_DIR/swift6-actor.output.txt"
ACTOR_STDERR="$BUILD_DIR/swift6-actor.stderr.txt"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
TMP_DIR="$BUILD_DIR/tmp"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local needle="$2"
    if ! grep -F "$needle" "$file" >/dev/null; then
        fail "expected '$needle' in $file"
    fi
}

assert_not_contains() {
    local file="$1"
    local needle="$2"
    if grep -F "$needle" "$file" >/dev/null; then
        fail "did not expect '$needle' in $file"
    fi
}

assert_adjacent_lines() {
    local file="$1"
    local first="$2"
    local second="$3"
    if ! awk -v first="$first" -v second="$second" '
        previous && index($0, second) { found = 1 }
        { previous = index($0, first) > 0 }
        END { exit(found ? 0 : 1) }
    ' "$file"; then
        fail "expected adjacent lines containing '$first' then '$second' in $file"
    fi
}

compile_fixture() {
    local source_file="$1"
    local output_file="$2"

    TMPDIR="$TMP_DIR" xcrun swiftc \
        -swift-version 6 \
        -target arm64-apple-macosx13.0 \
        -module-cache-path "$MODULE_CACHE_DIR" \
        -parse-as-library \
        -o "$output_file" \
        "$source_file"
}

mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_CACHE_DIR"
mkdir -p "$TMP_DIR"

if [[ -z "$SWIFTDUMP_BIN" ]]; then
    fail "set SWIFTDUMP_BIN to a freshly built SwiftDump executable"
fi

if [[ ! -x "$SWIFTDUMP_BIN" ]]; then
    fail "SWIFTDUMP_BIN is not executable: $SWIFTDUMP_BIN"
fi

echo "[1/6] compiling Swift 6 fixtures with xcrun swiftc"
compile_fixture "$SURFACE_FIXTURE_SRC" "$SURFACE_FIXTURE_BIN"
compile_fixture "$ACTOR_FIXTURE_SRC" "$ACTOR_FIXTURE_BIN"
cp "$SURFACE_FIXTURE_BIN" "$SURFACE_STRIPPED_BIN"
strip -x "$SURFACE_STRIPPED_BIN"
surface_size="$(stat -f %z "$SURFACE_FIXTURE_BIN")"
if (( surface_size <= 4096 )); then
    fail "surface fixture is unexpectedly small: $surface_size"
fi
dd if="$SURFACE_FIXTURE_BIN" of="$SURFACE_TRUNCATED_BIN" bs=1 count="$((surface_size - 4096))" status=none

echo "[2/6] verifying existing Demo/test regression"
"$SWIFTDUMP_BIN" -a x86_64 "$DEMO_BIN" > "$DEMO_OUTPUT"
assert_not_contains "$DEMO_OUTPUT" "Fatal error"
assert_contains "$DEMO_OUTPUT" "enum MyEnum"
assert_contains "$DEMO_OUTPUT" "struct BaseStruct"
assert_contains "$DEMO_OUTPUT" "var bbname: String //"
assert_not_contains "$DEMO_OUTPUT" "var bbname: String;"
assert_contains "$DEMO_OUTPUT" "class MyClass : BaseClass"
assert_contains "$DEMO_OUTPUT" "var st: MyStruct? //"
assert_not_contains "$DEMO_OUTPUT" "var st: MyStruct?;"

echo "[3/6] verifying Swift 6 surface regression fixture"
"$SWIFTDUMP_BIN" -a arm64 "$SURFACE_FIXTURE_BIN" > "$SURFACE_OUTPUT"
assert_not_contains "$SURFACE_OUTPUT" "Fatal error"
assert_not_contains "$SURFACE_OUTPUT" "Could not cast value"
assert_contains "$SURFACE_OUTPUT" "protocol RootProtocol"
assert_contains "$SURFACE_OUTPUT" "protocol ChildProtocol : RootProtocol"
assert_contains "$SURFACE_OUTPUT" "enum PayloadlessColor"
assert_contains "$SURFACE_OUTPUT" "enum PayloadMessage"
assert_contains "$SURFACE_OUTPUT" "case text(String)"
assert_contains "$SURFACE_OUTPUT" "case count(Int)"
assert_contains "$SURFACE_OUTPUT" "struct GenericBox"
assert_contains "$SURFACE_OUTPUT" "let item: A // runtime-dependent"
assert_contains "$SURFACE_OUTPUT" "class ObjectiveCarrier : NSObject,ChildProtocol,RootProtocol"
assert_contains "$SURFACE_OUTPUT" "let pair: (Int, String) // 0x8"
assert_contains "$SURFACE_OUTPUT" "let handler: @Sendable () async -> String // 0x20"
assert_contains "$SURFACE_OUTPUT" "let failure: Error // 0x30"
assert_contains "$SURFACE_OUTPUT" "var mutableText: String // 0x50"
# Sendable is a marker protocol, so Swift reflection metadata erases
# Sendable.Type to Any.Type even though function-type @Sendable is preserved.
assert_contains "$SURFACE_OUTPUT" "let sendableType: Any.Type // 0x38"
assert_contains "$SURFACE_OUTPUT" "let genericBox: GenericBox<String> // 0x40"
assert_contains "$SURFACE_OUTPUT" "struct LicenseDevice"
assert_contains "$SURFACE_OUTPUT" "let id: String // runtime-dependent"
assert_contains "$SURFACE_OUTPUT" "let name: String // runtime-dependent"
assert_contains "$SURFACE_OUTPUT" "let activatedAt: Foundation.Date? // runtime-dependent"
assert_contains "$SURFACE_OUTPUT" "static let maximumActivations: Int = 5"
assert_contains "$SURFACE_OUTPUT" "static let featureEnabled: Bool = true"
assert_contains "$SURFACE_OUTPUT" "static let timeoutSeconds: Double = 1.5"
assert_contains "$SURFACE_OUTPUT" "static var serviceName: String // initialized at runtime"
assert_contains "$SURFACE_OUTPUT" "struct FixedLayoutRecord"
assert_contains "$SURFACE_OUTPUT" "let count: Int64 // 0x0"
assert_contains "$SURFACE_OUTPUT" "let enabled: Bool // 0x8"
assert_contains "$SURFACE_OUTPUT" "let code: UInt32 // 0xc"
assert_contains "$SURFACE_OUTPUT" "// Init Function at 0x"
assert_adjacent_lines "$SURFACE_OUTPUT" "// Access Function at 0x" "// Init Function at 0x"
assert_not_contains "$SURFACE_OUTPUT" "let pair: (Int, String);"
assert_contains "$SURFACE_OUTPUT" "init(pair: (Int, String), handler: @Sendable () async -> String, failure: Error, sendableType: Sendable.Type, genericBox: GenericBox<String>)"
assert_contains "$SURFACE_OUTPUT" "var computedSummary: String { get }"
assert_contains "$SURFACE_OUTPUT" "var computedSummary: String { set }"
assert_contains "$SURFACE_OUTPUT" "func rootRequirement(seed: Int) -> String"
assert_contains "$SURFACE_OUTPUT" "func instanceMethod(box: GenericBox<String>, flag: Bool) async throws -> GenericBox<String>"
assert_contains "$SURFACE_OUTPUT" "static func staticMethod(value: String) -> GenericBox<String>"
assert_contains "$SURFACE_OUTPUT" "func genericMethod<A where A: Sendable>(value: A) -> A"
assert_contains "$SURFACE_OUTPUT" "static func classMethod(code: Int) -> String"
assert_contains "$SURFACE_OUTPUT" "static func main()"
assert_not_contains "$SURFACE_OUTPUT" "So120x"

echo "[4/6] verifying stripped Swift 6 surface fixture degradation"
"$SWIFTDUMP_BIN" -a arm64 "$SURFACE_STRIPPED_BIN" > "$SURFACE_STRIPPED_OUTPUT"
assert_not_contains "$SURFACE_STRIPPED_OUTPUT" "Fatal error"
assert_contains "$SURFACE_STRIPPED_OUTPUT" "class ObjectiveCarrier : NSObject,ChildProtocol,RootProtocol"
assert_contains "$SURFACE_STRIPPED_OUTPUT" "let pair: (Int, String) // offset unavailable"
assert_contains "$SURFACE_STRIPPED_OUTPUT" "var mutableText: String // offset unavailable"
assert_not_contains "$SURFACE_STRIPPED_OUTPUT" "// Init Function at 0x"

echo "[5/6] verifying truncated symbol/string table degradation"
"$SWIFTDUMP_BIN" -a arm64 "$SURFACE_TRUNCATED_BIN" > "$SURFACE_TRUNCATED_OUTPUT"
assert_not_contains "$SURFACE_TRUNCATED_OUTPUT" "Fatal error"
assert_contains "$SURFACE_TRUNCATED_OUTPUT" "class ObjectiveCarrier : NSObject,ChildProtocol,RootProtocol"
assert_contains "$SURFACE_TRUNCATED_OUTPUT" "let pair: (Int, String) // offset unavailable"
assert_not_contains "$SURFACE_TRUNCATED_OUTPUT" "    // Function at "

echo "[6/6] verifying Swift 6 actor regression fixture"
if ! "$SWIFTDUMP_BIN" -a arm64 "$ACTOR_FIXTURE_BIN" > "$ACTOR_OUTPUT" 2> "$ACTOR_STDERR"; then
    fail "SwiftDump crashed or exited non-zero on actor fixture: $ACTOR_FIXTURE_BIN"
fi
assert_not_contains "$ACTOR_OUTPUT" "Fatal error"
assert_contains "$ACTOR_OUTPUT" "actor StatusActor"
assert_contains "$ACTOR_OUTPUT" "init(counter: Int)"
assert_contains "$ACTOR_OUTPUT" "static func main()"
assert_not_contains "$ACTOR_OUTPUT" "0xcffaedfe"

echo "PASS: Demo regression, Swift 6 function-signature regression, stripped-binary degradation, and truncated-symbol-table checks all succeeded."
