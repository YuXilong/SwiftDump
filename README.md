
#### SwiftDump

##### [中文文档](./README_zh.md)

SwiftDump is a command-line tool for retrieving Swift object information from Mach-O files. Similar to [class-dump](https://github.com/nygard/class-dump/), SwiftDump focuses on Swift 5 and Swift 6 metadata. For Mach-O files mixed with Objective-C and Swift, you can combine class-dump with SwiftDump.

There is alos a [Frida](https://www.frida.re/) version named [FridaSwiftDump](https://github.com/neil-wu/FridaSwiftDump/).

You can either use`SwiftDump` for a Mach-O file or `FridaSwiftDump` for a foreground running app.

If you are curious about the Mach-O format, check the image at the bottom of this article.

![demo](./Doc/img_demo_result.jpg)

#### Usage

``` Text
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

* SwiftDump ./TestMachO > result.txt
* SwiftDump -a x86_64 ./TestMachO > result.txt

#### Features

* Written entirely in swift, the project is tiny
* Dump Swift 5/6 struct, class, actor, enum, and protocol declarations
* Parse payload and payloadless enum cases plus field mutability/indirect-case flags
* Support class inheritance, protocol inheritance, and conformances
* Safely read signed relative pointers and modern `LC_DYLD_CHAINED_FIXUPS` imports
* Decode symbolic mangled-name references without instantiating target types through a private Swift runtime entry point

Thanks to the runtime function, SwiftDump can demangle complex type, such as RxSwift variable. For example, 
`RxSwift.Queue<(eventTime: Foundation.Date, event: RxSwift.Event<A.RxSwift.ObserverType.Element>)>`

#### TODO

* Parse swift function address
* More

#### Compile

1. Clone the repo
2. Open SwiftDump.xcodeproj with Xcode
3. Modify 'Signing & Capabilities' to use your own id
4. Build & Run

The default Mach-O file path is `Demo/test`, you can change it in `Xcode - Product - Scheme - Edit Scheme - Arguments`

The project builds in Swift 6 language mode and tracks the Swift 6.3.3 metadata ABI. Run the regression suite with:

```sh
SWIFTDUMP_BIN=/path/to/SwiftDump ./scripts/run_regression.sh
```

The suite covers the legacy demo plus Swift 6 actors, generics, protocol inheritance, existentials, async `@Sendable` function types, and modern chained fixups.

Note: marker protocols can be erased from field reflection metadata. For example, `Sendable.Type` may be emitted as `Any.Type`; SwiftDump reports the recoverable ABI representation rather than guessing source syntax.

#### Credit

* [Machismo](https://github.com/g-Off/Machismo) : Parsing of Mach-O binaries using swift.
* [swift-argument-parser](https://github.com/apple/swift-argument-parser) : Straightforward, type-safe argument parsing for Swift.
* [Swift metadata](https://knight.sc/reverse%20engineering/2019/07/17/swift-metadata.html) : High level description of all the Swift 5 sections that can show up in a Swift binary.


#### License

MIT


#### Mach-O File Format

The following image shows how SwiftDump parse swift types from file `Demo/test`. You can open this file with [MachOView](https://github.com/gdbinit/MachOView).

![demo](./Doc/macho.jpg)

