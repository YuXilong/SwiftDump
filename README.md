# SwiftDump

中文（默认） | [English](./README_EN.md)

[![Release](https://img.shields.io/github/v/release/YuXilong/SwiftDump?display_name=tag)](https://github.com/YuXilong/SwiftDump/releases/latest)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

SwiftDump 是一个从 Mach-O 文件中恢复 Swift 类型定义的命令行工具，定位类似 Objective-C 的 [class-dump](https://github.com/nygard/class-dump/)。它可以离线解析 Swift 5 / Swift 6 metadata；对于 Objective-C 与 Swift 混编程序，可以配合 class-dump 使用。

| 工具 | 输入 | 适用场景 |
| --- | --- | --- |
| **SwiftDump** | 本地 Mach-O 文件 | 离线分析、自动化处理、无需启动目标 App |
| [FridaSwiftDump](https://github.com/neil-wu/FridaSwiftDump/) | 正在前台运行的 App | 运行时分析，需要 Frida 环境 |

![SwiftDump 输出示例](./Doc/img_demo_result.jpg)

## 下载与快速开始

推荐从 [GitHub Releases](https://github.com/YuXilong/SwiftDump/releases) 下载最新版本。

当前正式版本：[SwiftDump v1.1.0](https://github.com/YuXilong/SwiftDump/releases/tag/v1.1.0)

发布包包含 arm64 与 x86_64 Universal CLI、中英文文档、许可证和构建信息。Release 页面同时提供完整构建日志、回归日志及 `SHA256SUMS`。

```sh
curl -LO https://github.com/YuXilong/SwiftDump/releases/download/v1.1.0/SwiftDump-v1.1.0-macos-universal.zip
curl -LO https://github.com/YuXilong/SwiftDump/releases/download/v1.1.0/SHA256SUMS
shasum -a 256 SwiftDump-v1.1.0-macos-universal.zip
unzip SwiftDump-v1.1.0-macos-universal.zip
cd SwiftDump-v1.1.0-macos-universal
chmod +x SwiftDump
./SwiftDump --version
```

将 `shasum` 输出与 `SHA256SUMS` 中对应条目比对后再运行。

> 发布二进制使用 ad hoc signature，尚未经过 Apple notarization。如果文件带有浏览器下载隔离属性，macOS 可能要求你在“系统设置 → 隐私与安全性”中确认运行。

## 功能

- 恢复 Swift 5 / Swift 6 的 `struct`、`class`、`actor`、`enum` 和 `protocol` 定义。
- 解析 payload / payloadless enum case，以及字段 `let` / `var`、`indirect case` 标志；字段声明不带分号，并在 ABI 可确定时附带实例内偏移。
- 恢复类继承、协议继承和协议遵循关系。
- 在 Mach-O 保留 `LC_SYMTAB` Swift 符号时，恢复 `init`、实例/静态方法、泛型约束、`async throws`、属性 accessor 及函数地址；`init` 入口地址紧跟 metadata access function 输出。
- 恢复有存储符号的静态属性声明；对于常量区中的基础数值类型，可安全输出其字面量值。
- 按 Swift 6.3.3 metadata ABI 解析 descriptor、conformance 和 field records。
- 安全处理 signed relative pointer、direct / indirect pointer。
- 支持现代 Mach-O `LC_DYLD_CHAINED_FIXUPS` userland rebase / bind，包括常见 arm64e authenticated pointer。
- 识别新版 symbolic mangled-name reference 与 Embedded Swift `$e` 前缀。
- 对截断、损坏或越界 Mach-O 数据安全失败，不直接崩溃。

SwiftDump 会调用公开的 Swift runtime demangler，因此可以恢复复杂的泛型类型，例如：

```swift
RxSwift.Queue<(eventTime: Foundation.Date, event: RxSwift.Event<A.RxSwift.ObserverType.Element>)>
```

## 兼容性

| 项目 | 当前状态 |
| --- | --- |
| Swift metadata | Swift 5、Swift 6；以 Swift 6.3.3 ABI 定义为当前适配基线 |
| CPU 架构 | arm64、x86_64、Universal Mach-O |
| 构建环境 | 已验证 Xcode 26.0.1 / Apple Swift 6.2 / Swift 6 language mode |
| macOS 部署目标 | macOS 10.13+ |
| chained fixups | 常见 userland pointer formats；不包含 kernel/shared-cache formats 或 PAC 验签 |
| Swift 函数签名 | 未剥离的 `LC_SYMTAB` 可恢复；完全 strip 后安全退化为类型/字段输出 |
| 字段偏移 | 固定布局 struct metadata vector 与 class `Wvd` 可恢复；泛型、韧性或运行时初始化布局会明确标记 |
| 静态属性值 | 仅恢复未剥离存储符号中可验证的基础数值常量；不执行初始化代码 |
| 发布签名 | ad hoc signature，尚未 Apple notarization |

## 使用方法

```text
USAGE: SwiftDump [--debug] [--arch <arch>] <file> [--version]

ARGUMENTS:
  <file>                  Mach-O File

OPTIONS:
  -d, --debug             Show debug log.
  -a, --arch <arch>       Choose architecture from a fat binary (only support x86_64/arm64).
                          (default: arm64)
  -v, --version           Version
  -h, --help              Show help information.
```

示例：

```sh
SwiftDump ./TestMachO > result.txt
SwiftDump -a x86_64 ./TestMachO > result.txt
SwiftDump --debug -a arm64 ./TestMachO
```

示例输出：

```swift
protocol ChildProtocol : RootProtocol {
}

enum PayloadMessage {
    case text(String)
    case count(Int)
}

struct LicenseDevice {
    // <0x10051, struct, isUnique, kindSpecificFlags 0x1>
    // Access Function at 0x25c43c
    // Init Function at 0x25d080
    let id: String // runtime-dependent
    let name: String // runtime-dependent
    let activatedAt: Foundation.Date? // runtime-dependent
    static let maximumActivations: Int = 5
    static var serviceName: String // initialized at runtime

    init(id: String, name: String, activatedAt: Foundation.Date?)
}

struct FixedLayoutRecord {
    let count: Int64 // 0x0
    let enabled: Bool // 0x8
    let code: UInt32 // 0xc
}
```

函数声明来源会影响输出完整度：SwiftDump 优先读取 Mach-O 符号表并调用公开的 Swift runtime demangler。编译器生成的方法可能一同出现；如果发布构建已经移除本地 Swift 符号，SwiftDump 不会根据地址猜测不存在于 ABI 中的参数名或类型。

`kindSpecificFlags 0x1` 表示该类型需要 singleton metadata initialization。此时最终字段偏移由 Swift runtime 填充；SwiftDump 不调用目标代码，因此输出 `runtime-dependent`，而不会把磁盘 metadata 模板中的占位值误报为真实偏移。

## 从源码构建

工程使用 Swift 6 language mode，依赖通过 Swift Package Manager 管理。

1. 克隆仓库。
2. 使用 Xcode 打开 `SwiftDump/SwiftDump.xcodeproj`。
3. 选择 `SwiftDump` scheme 和 `My Mac`。
4. Build 或 Run。

也可以通过命令行构建无需签名的 Release：

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

构建产物位于：

```text
/tmp/SwiftDumpDerivedData/Build/Products/Release/SwiftDump
```

项目已在 Xcode 26.0.1 / Apple Swift 6.2 下通过构建，并以 Swift 6.3.3 官方 ABI 定义作为解析适配基线。使用更新的 Swift 6.3.3 工具链时，也应重新执行下方回归。

## 回归测试

测试脚本强制使用调用者指定的新构建产物，不会回退到仓库中的旧 Demo 二进制：

```sh
SWIFTDUMP_BIN=/tmp/SwiftDumpDerivedData/Build/Products/Release/SwiftDump \
  ./scripts/run_regression.sh
```

回归范围包括：

- 旧版 `Demo/test`。
- Swift 6 actor、泛型与协议继承。
- payload / payloadless enum。
- existential 与 `Error`。
- async `@Sendable` 函数类型。
- `init`、实例/静态方法、泛型约束、`async throws` 与 computed-property accessor。
- 固定布局 struct、class 字段偏移，动态布局和 stripped binary 的安全降级。
- 静态基础数值常量与运行时初始化静态属性的区分。
- `strip -x` 后不崩溃且继续恢复类型/字段。
- 现代 chained fixups 与损坏输入安全性。

## ABI 边界

- SwiftDump 输出 metadata 中能够恢复的信息，不猜测已经被编译器擦除的源码语法。例如 marker protocol 可能在 field reflection metadata 中被擦除，`Sendable.Type` 可能只能恢复为 `Any.Type`。
- 完整函数签名主要来自 `LC_SYMTAB` 中的 Swift mangled symbols。class vtable 和 protocol requirement ABI 只提供方法类别、槽位或实现地址，并不包含完整 name/type；完全 strip 的二进制需要 dSYM/DWARF 才可能进一步恢复。
- 固定布局 struct 的字段偏移来自 type metadata field-offset vector，class 字段优先使用 `Wvd` direct-field-offset global。泛型布局、`metadataInitializationKind != 0`、缺失符号或 stripped binary 会输出 `runtime-dependent` / `offset unavailable`，不会执行 metadata accessor。
- 静态属性不是 field reflection metadata 的组成部分，只能在 `LC_SYMTAB` 保留相应 storage/accessor 符号时恢复。当前只读取只读常量区中的 `Bool`、整数和浮点数；`String`、引用、lazy/运行时初始化值不会离线解码或执行初始化函数。
- demangle 输出是规范化声明，不保证保留源码中的 typealias、默认参数值、访问控制，也无法可靠区分所有 `class func` 与 `static func` 源码写法。
- chained fixups 当前聚焦常见 userland pointer formats，不实现 kernel/shared-cache formats 或 PAC 验签。
- 不通过保留的私有 Swift 类型实例化入口加载目标类型，避免离线 dump 触发目标程序运行时行为。

## 项目结构

```text
SwiftDump/                  Xcode 工程与 Swift 源码
Tests/Fixtures/            Swift 6 回归输入
scripts/run_regression.sh  回归入口
Demo/                      旧版示例 Mach-O 与输出
Doc/                       示例图片
```

## TODO

- 支持可选 dSYM/DWARF 输入，增强 stripped binary 的函数恢复。
- 解析 class vtable / protocol requirement trailing records，提供无符号时的方法类别与地址 fallback。
- 扩展更多 chained pointer formats 与 metadata trailing objects。

## 参考与致谢

- [Machismo](https://github.com/g-Off/Machismo)：使用 Swift 读取 Mach-O。
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)：类型安全的命令行参数解析。
- [Swift metadata](https://knight.sc/reverse%20engineering/2019/07/17/swift-metadata.html)：Swift metadata 高层介绍。
- [Swift ABI 源码](https://github.com/swiftlang/swift/tree/swift-6.3.3-RELEASE/include/swift/ABI)：本项目当前 ABI 适配依据。

## Mach-O 文件格式

下图展示 SwiftDump 如何从 `Demo/test` 恢复 Swift 类型。可以使用 [MachOView](https://github.com/gdbinit/MachOView) 打开示例文件并对照查看。

![Mach-O 文件结构](./Doc/macho.jpg)

## License

[MIT](./LICENSE)
