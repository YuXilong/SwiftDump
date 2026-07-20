
#### SwiftDump

SwiftDump 是从 Mach-O 文件中获取 Swift 对象定义的命令行工具，类似常用的 OC 类 dump 工具 [class-dump](https://github.com/nygard/class-dump/)。当前同时支持 Swift 5 和 Swift 6 metadata。对于 OC/Swift 混编的 Mach-O 文件，可以将 class-dump 和 SwiftDump 结合使用。

同时，我在[Frida](https://www.frida.re/)中实现了一个简单版本 [FridaSwiftDump](https://github.com/neil-wu/FridaSwiftDump/)。

你可以根据需要选择使用，`SwiftDump`可以解析处理Mach-O文件，而`FridaSwiftDump`可以对一个前台运行的app进行解析。

如果你对解析Mach-O的过程感兴趣，请查看该文档最后的配图。

![demo](./Doc/img_demo_result.jpg)

#### 用法

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

#### 特点

* 完全使用swift编写，项目小巧
* 支持 dump Swift 5/6 的 struct、class、actor、enum 和 protocol
* 支持 payload/payloadless enum case，以及字段 `let`/`var` 和 `indirect case` flags
* 支持类继承、协议继承和协议遵循关系
* 安全解析 signed relative pointer 与现代 `LC_DYLD_CHAINED_FIXUPS` imports
* 支持新版 symbolic mangled-name reference，不再通过 Swift 私有类型实例化入口解析目标类型

受益于swift运行时函数, SwiftDump可以还原复杂的数据类型, 比如某个使用RxSwift声明的变量类型能达到如下的解析效果： 
`RxSwift.Queue<(eventTime: Foundation.Date, event: RxSwift.Event<A.RxSwift.ObserverType.Element>)>`

#### TODO

* 考虑添加导出函数地址
* 待定

#### Compile

1. Clone the repo
2. Open SwiftDump.xcodeproj with Xcode
3. Modify 'Signing & Capabilities' to use your own id
4. Build & Run

默认输入参数使用目录`Demo/test`的Mach-O文件, 你可以在Xcode里修改输入参数： `Xcode - Product - Scheme - Edit Scheme - Arguments`

工程已切换到 Swift 6 language mode，并按 Swift 6.3.3 metadata ABI 适配。可以运行以下回归：

```sh
SWIFTDUMP_BIN=/path/to/SwiftDump ./scripts/run_regression.sh
```

回归覆盖旧版 Demo，以及 Swift 6 actor、泛型、协议继承、existential、async `@Sendable` 函数类型和现代 chained fixups。

注意：marker protocol 可能在 field reflection metadata 中被擦除，例如 `Sendable.Type` 可能只保存为 `Any.Type`。SwiftDump 会输出 ABI 中可以恢复的信息，不猜测已丢失的源码语法。

#### 感谢

* [Machismo](https://github.com/g-Off/Machismo) : 使用swift来读取Mach-O文件
* [swift-argument-parser](https://github.com/apple/swift-argument-parser) : 解析命令行参数
* [Swift metadata](https://knight.sc/reverse%20engineering/2019/07/17/swift-metadata.html) : High level description of all the Swift 5 sections that can show up in a Swift binary.


#### License

MIT


#### Mach-O File Format

下图展示了 SwiftDump 是如何从测试文件 `Demo/test` 解析 swift 类型的，你可以使用 [MachOView](https://github.com/gdbinit/MachOView) 打开这个测试文件，对照下图查看。

![demo](./Doc/macho.jpg)
