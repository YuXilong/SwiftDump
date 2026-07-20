# SwiftDump

[中文（默认）](./README.md) | English

[![Release](https://img.shields.io/github/v/release/YuXilong/SwiftDump?display_name=tag)](https://github.com/YuXilong/SwiftDump/releases/latest)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

SwiftDump is a command-line tool that recovers Swift type declarations from Mach-O files. It fills a role similar to Objective-C [class-dump](https://github.com/nygard/class-dump/) and supports offline parsing of Swift 5 and Swift 6 metadata. For mixed Objective-C/Swift binaries, use it together with class-dump.

| Tool | Input | Best for |
| --- | --- | --- |
| **SwiftDump** | Local Mach-O file | Offline analysis and automation without launching the target app |
| [FridaSwiftDump](https://github.com/neil-wu/FridaSwiftDump/) | Foreground app | Runtime analysis with a Frida environment |

![SwiftDump output](./Doc/img_demo_result.jpg)

## Download

Download the latest build from [GitHub Releases](https://github.com/YuXilong/SwiftDump/releases). The current stable release is [SwiftDump v1.0.0](https://github.com/YuXilong/SwiftDump/releases/tag/v1.0.0).

The release provides an arm64/x86_64 Universal CLI, documentation, license, build information, complete build and regression logs, and SHA-256 checksums.

```sh
curl -LO https://github.com/YuXilong/SwiftDump/releases/download/v1.0.0/SwiftDump-v1.0.0-macos-universal.zip
curl -LO https://github.com/YuXilong/SwiftDump/releases/download/v1.0.0/SHA256SUMS
shasum -a 256 SwiftDump-v1.0.0-macos-universal.zip
unzip SwiftDump-v1.0.0-macos-universal.zip
cd SwiftDump-v1.0.0-macos-universal
chmod +x SwiftDump
./SwiftDump --version
```

Compare the `shasum` output with the corresponding entry in `SHA256SUMS` before running the binary.

> The release binary has a linker ad hoc signature and is not Apple-notarized. macOS may require confirmation under System Settings → Privacy & Security when the archive carries a browser quarantine attribute.

## Features

- Recover Swift 5/6 `struct`, `class`, `actor`, `enum`, and `protocol` declarations.
- Parse payload and payloadless enum cases, field mutability, and indirect-case flags.
- Recover class inheritance, protocol inheritance, and conformances.
- Follow Swift 6.3.3 descriptor, conformance, and field-record ABI definitions.
- Safely resolve signed relative and direct/indirect pointers.
- Resolve common userland `LC_DYLD_CHAINED_FIXUPS` rebases and binds, including arm64e authenticated pointers.
- Recognize modern symbolic mangled-name references and the Embedded Swift `$e` prefix.
- Fail safely on truncated, malformed, and out-of-bounds Mach-O input.

SwiftDump uses the public Swift runtime demangler and can recover complex generic types such as:

```swift
RxSwift.Queue<(eventTime: Foundation.Date, event: RxSwift.Event<A.RxSwift.ObserverType.Element>)>
```

## Compatibility

| Item | Current status |
| --- | --- |
| Swift metadata | Swift 5 and Swift 6; Swift 6.3.3 ABI definitions are the current parser baseline |
| Architectures | arm64, x86_64, and Universal Mach-O |
| Build environment | Verified with Xcode 26.0.1 / Apple Swift 6.2 / Swift 6 language mode |
| Deployment target | macOS 10.13+ |
| Chained fixups | Common userland pointer formats; no kernel/shared-cache formats or PAC validation |
| Release signature | Linker ad hoc signature; not Apple-notarized |

## Usage

```text
USAGE: SwiftDump [--debug] [--arch <arch>] <file> [--version]

ARGUMENTS:
  <file>                  MachO File

OPTIONS:
  -d, --debug             Show debug log.
  -a, --arch <arch>       Choose architecture from a fat binary (only support x86_64/arm64).
                          (default: arm64)
  -v, --version           Version
  -h, --help              Show help information.
```

```sh
SwiftDump ./TestMachO > result.txt
SwiftDump -a x86_64 ./TestMachO > result.txt
SwiftDump --debug -a arm64 ./TestMachO
```

Example output:

```swift
protocol ChildProtocol : RootProtocol {
}

enum PayloadMessage {
    case text(String)
    case count(Int)
}

actor StatusActor {
    let counter: Int
}
```

## Build from source

The project uses Swift 6 language mode and Swift Package Manager.

1. Clone the repository.
2. Open `SwiftDump/SwiftDump.xcodeproj` in Xcode.
3. Select the `SwiftDump` scheme and My Mac.
4. Build or run.

To create an unsigned command-line Release build:

```sh
xcodebuild \
  -project SwiftDump/SwiftDump.xcodeproj \
  -scheme SwiftDump \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/SwiftDumpDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The executable is written to:

```text
/tmp/SwiftDumpDerivedData/Build/Products/Release/SwiftDump
```

The project has been built with Xcode 26.0.1 / Apple Swift 6.2 and uses the official Swift 6.3.3 ABI definitions as its parser baseline. Re-run the regression suite when validating a newer Swift 6.3.3 toolchain.

## Regression suite

The runner requires an explicitly selected fresh executable and never falls back to the stale checked-in Demo binary:

```sh
SWIFTDUMP_BIN=/tmp/SwiftDumpDerivedData/Build/Products/Release/SwiftDump \
  ./scripts/run_regression.sh
```

Coverage includes the legacy Demo plus Swift 6 actors, generics, protocol inheritance, enum payloads, existentials, async `@Sendable` function types, and modern chained fixups.

## ABI boundaries

- SwiftDump prints information recoverable from reflection metadata instead of guessing erased source syntax. Marker protocols may be erased; for example, `Sendable.Type` may be represented as `Any.Type`.
- Chained-fixup support focuses on common userland pointer formats. Kernel/shared-cache formats and PAC validation are outside the current scope.
- SwiftDump does not instantiate target types through reserved private Swift runtime entry points.

## Repository layout

```text
SwiftDump/                  Xcode project and Swift sources
Tests/Fixtures/            Swift 6 regression inputs
scripts/run_regression.sh  Regression entry point
Demo/                      Legacy sample Mach-O and output
Doc/                       Documentation images
```

## Credits

- [Machismo](https://github.com/g-Off/Machismo): Mach-O parsing in Swift.
- [swift-argument-parser](https://github.com/apple/swift-argument-parser): type-safe command-line parsing.
- [Swift metadata](https://knight.sc/reverse%20engineering/2019/07/17/swift-metadata.html): a high-level Swift metadata introduction.
- [Swift ABI sources](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE/include/swift/ABI): the current ABI adaptation baseline.

## Mach-O file format

The following image shows how SwiftDump recovers types from `Demo/test`. Open the sample with [MachOView](https://github.com/gdbinit/MachOView) to compare its layout.

![Mach-O layout](./Doc/macho.jpg)

## License

[MIT](./LICENSE)
