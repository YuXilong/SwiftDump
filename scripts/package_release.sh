#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <vX.Y.Z> <SwiftDump binary> <build log> <regression log> <output directory>" >&2
}

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

if [[ $# -ne 5 ]]; then
    usage
    exit 64
fi

TAG="$1"
BINARY="$2"
BUILD_LOG="$3"
REGRESSION_LOG="$4"
OUTPUT_DIR="$5"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "release tag must match vX.Y.Z: $TAG"
fi

VERSION="${TAG#v}"
PACKAGE_NAME="SwiftDump-${TAG}-macos-universal"
ZIP_NAME="${PACKAGE_NAME}.zip"
BUILD_LOG_NAME="SwiftDump-${TAG}-build.log"
REGRESSION_LOG_NAME="SwiftDump-${TAG}-regression.log"

[[ -x "$BINARY" ]] || fail "binary is not executable: $BINARY"
[[ -f "$BUILD_LOG" ]] || fail "build log does not exist: $BUILD_LOG"
[[ -f "$REGRESSION_LOG" ]] || fail "regression log does not exist: $REGRESSION_LOG"

version_output="$("$BINARY" --version)"
[[ "$version_output" == "SwiftDump v${VERSION} "* ]] || \
    fail "binary version does not match $TAG: $version_output"

architectures="$(lipo -archs "$BINARY")"
for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || \
        fail "binary is missing $architecture: $architectures"
done

mkdir -p "$OUTPUT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SwiftDump-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

PACKAGE_DIR="$WORK_DIR/$PACKAGE_NAME"
mkdir -p "$PACKAGE_DIR"
cp "$BINARY" "$PACKAGE_DIR/SwiftDump"
cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/README.md" "$ROOT_DIR/README_EN.md" "$PACKAGE_DIR/"

codesign --force --sign - --timestamp=none "$PACKAGE_DIR/SwiftDump"
codesign --verify --strict --all-architectures --verbose=2 "$PACKAGE_DIR/SwiftDump"

SOURCE_COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD)"
XCODE_VERSION="$(xcodebuild -version | paste -sd ' ' -)"
SWIFT_VERSION="$(xcrun swiftc --version 2>&1 | awk '/Apple Swift version/ { print; exit }')"

cat > "$PACKAGE_DIR/BUILD_INFO.md" <<EOF
# SwiftDump $TAG 构建信息

- 版本：\`$TAG\`
- 发布日期：\`$(date +%F)\`
- 源码提交：\`$SOURCE_COMMIT\`
- Xcode：\`$XCODE_VERSION\`
- Swift：\`$SWIFT_VERSION\`
- 架构：\`arm64\`、\`x86_64\` Universal Mach-O
- 签名：ad hoc signature，全部架构已验证
- Apple notarization：未提交，不声称已公证

验证结果：Release 构建、静态分析和 Swift 5/6 回归已由发布流水线执行。完整日志作为 GitHub Release 独立附件发布。
EOF

cp "$BUILD_LOG" "$OUTPUT_DIR/$BUILD_LOG_NAME"
cp "$REGRESSION_LOG" "$OUTPUT_DIR/$REGRESSION_LOG_NAME"

rm -f "$OUTPUT_DIR/$ZIP_NAME" "$OUTPUT_DIR/SHA256SUMS"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$OUTPUT_DIR/$ZIP_NAME"

(
    cd "$OUTPUT_DIR"
    shasum -a 256 "$ZIP_NAME" "$BUILD_LOG_NAME" "$REGRESSION_LOG_NAME" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

echo "Packaged SwiftDump $TAG in $OUTPUT_DIR"
