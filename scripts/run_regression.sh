#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTDUMP_BIN="${SWIFTDUMP_BIN:-}"
BUILD_DIR="$ROOT_DIR/Tests/.build"
DEMO_BIN="$ROOT_DIR/Demo/test"
DEMO_OUTPUT="$BUILD_DIR/demo.output.txt"
SURFACE_FIXTURE_SRC="$ROOT_DIR/Tests/Fixtures/Swift6SurfaceRegression.swift"
SURFACE_FIXTURE_BIN="$BUILD_DIR/Swift6SurfaceRegression"
SURFACE_OUTPUT="$BUILD_DIR/swift6-surface.output.txt"
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

echo "[1/4] compiling Swift 6 fixtures with xcrun swiftc"
compile_fixture "$SURFACE_FIXTURE_SRC" "$SURFACE_FIXTURE_BIN"
compile_fixture "$ACTOR_FIXTURE_SRC" "$ACTOR_FIXTURE_BIN"

echo "[2/4] verifying existing Demo/test regression"
"$SWIFTDUMP_BIN" -a x86_64 "$DEMO_BIN" > "$DEMO_OUTPUT"
assert_not_contains "$DEMO_OUTPUT" "Fatal error"
assert_contains "$DEMO_OUTPUT" "enum MyEnum"
assert_contains "$DEMO_OUTPUT" "struct BaseStruct"
assert_contains "$DEMO_OUTPUT" "var bbname: String;"
assert_contains "$DEMO_OUTPUT" "class MyClass : BaseClass"
assert_contains "$DEMO_OUTPUT" "var st: MyStruct?;"

echo "[3/4] verifying Swift 6 surface regression fixture"
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
assert_contains "$SURFACE_OUTPUT" "let item: A;"
assert_contains "$SURFACE_OUTPUT" "class ObjectiveCarrier : NSObject,ChildProtocol,RootProtocol"
assert_contains "$SURFACE_OUTPUT" "let pair: (Int, String);"
assert_contains "$SURFACE_OUTPUT" "let handler: @Sendable () async -> String;"
assert_contains "$SURFACE_OUTPUT" "let failure: Error;"
# Sendable is a marker protocol, so Swift reflection metadata erases
# Sendable.Type to Any.Type even though function-type @Sendable is preserved.
assert_contains "$SURFACE_OUTPUT" "let sendableType: Any.Type;"
assert_contains "$SURFACE_OUTPUT" "let genericBox: GenericBox<String>;"
assert_not_contains "$SURFACE_OUTPUT" "So120x"

echo "[4/4] verifying Swift 6 actor regression fixture"
if ! "$SWIFTDUMP_BIN" -a arm64 "$ACTOR_FIXTURE_BIN" > "$ACTOR_OUTPUT" 2> "$ACTOR_STDERR"; then
    fail "SwiftDump crashed or exited non-zero on actor fixture: $ACTOR_FIXTURE_BIN"
fi
assert_not_contains "$ACTOR_OUTPUT" "Fatal error"
assert_contains "$ACTOR_OUTPUT" "actor StatusActor"
assert_not_contains "$ACTOR_OUTPUT" "0xcffaedfe"

echo "PASS: Demo regression and Swift 6 regression fixtures all succeeded."
