# SwiftDump 项目协作规范

本文件是仓库级编码代理说明。`AGENTS.md` 必须保持为指向本文件的相对软链接，避免 Claude Code、Codex 等工具读取到不同规则。

## 沟通与文档

- 默认使用中文沟通、编写变更说明和发布说明；技术标识、API、ABI 名称保持官方英文拼写。
- `README.md` 是中文主文档，`README_EN.md` 是可选英文文档；修改用户可见行为时同步更新两者。
- `README_zh.md` 仅作为旧链接兼容入口，不在其中维护重复正文。

## 项目目标

SwiftDump 从本地 Mach-O 文件离线恢复 Swift 类型定义。修改时必须同时满足：

1. 保持 Swift 5 输入兼容性。
2. 支持 Swift 6 language mode 和当前声明的 Swift ABI 基线。
3. 对损坏、截断、未知格式输入安全失败，不发生越界读取或强制解包崩溃。
4. 不为获得表面输出而实例化目标程序中的类型或执行目标代码。

## 代码结构

- `SwiftDump/SwiftDump/`：CLI 与解析器源码。
- `SwiftDump/SwiftDump/MachO/`：Mach-O、segment、section、chained fixups 与安全读取。
- `SwiftDump/SwiftDump/Util/ContextDescriptor.swift`：Swift ABI flags 和 descriptor 枚举。
- `SwiftDump/SwiftDump/Util/RuntimeBridge.swift`：公开 Swift runtime demangler 边界。
- `Tests/Fixtures/`：用于生成 Swift 5/6 metadata 的回归输入。
- `scripts/run_regression.sh`：旧 Demo 与 Swift 6 回归入口。

## ABI 实现原则

- 以对应版本的 [swiftlang/swift](https://github.com/swiftlang/swift) 官方源码为事实来源，重点核对：
  - `include/swift/ABI/Metadata.h`
  - `include/swift/ABI/MetadataValues.h`
  - `include/swift/RemoteInspection/Records.h`
  - `docs/ABI/Mangling.rst`
- chained fixups 以 Apple dyld 的 `mach-o/fixup-chains.h` 为事实来源。
- relative pointer 必须按有符号偏移处理；direct、indirect、indirectable 与低位 tag 不得混用。
- 所有 Mach-O offset、range、record size、字符串终止位置在读取前都要验证。
- 未支持的 symbolic reference 或 pointer format 应保留原始信息或安全返回失败，不猜测地址。
- 不重新引入 `_getTypeByMangledNameInContext` 等保留的私有类型实例化入口。
- marker protocol 等源码语义可能在 reflection metadata 中被擦除；只输出 ABI 中可恢复的信息。

## 修改约束

- 优先复用现有安全读取和 pointer resolver，不在 parser 中复制裸地址运算。
- 不引入新依赖，除非需求明确且现有实现无法满足。
- 保持 CLI 参数和输出兼容；有意改变输出时必须增加或更新 fixture 断言。
- 不通过关闭 Swift 6 检查、移除安全校验或降低解析保护来修复构建。
- 避免顺手格式化整个旧文件；让功能 diff 保持可审查。
- 保留用户未提交的实验、`.omx/` 状态和无关工作区改动。

## 构建

本机安装 `xcb` 时，所有 Xcode 构建优先使用包装器：

```sh
WK_XCB_NOSTATS=1 xcb build \
  -project SwiftDump/SwiftDump.xcodeproj \
  -scheme SwiftDump \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath /tmp/SwiftDumpDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

未安装 `xcb` 的通用环境可以使用同参数的 `xcodebuild build`。

## 回归与完成标准

使用刚构建的可执行文件运行回归：

```sh
SWIFTDUMP_BIN=/tmp/SwiftDumpDerivedData/Build/Products/Release/SwiftDump \
  ./scripts/run_regression.sh
```

声称完成前至少确认：

- Release 构建成功，检查 error 和 warning 摘要。
- `scripts/run_regression.sh` 全部通过。
- 对 Mach-O 安全层的修改至少验证一个截断输入不会崩溃。
- `git diff --check` 通过。
- 没有把 `Tests/.build/`、DerivedData、`.omx/` 或临时发布目录加入版本控制。

## Git 与发布

- 在混合工作区中显式暂存本任务文件，不使用无差别 `git add -A`。
- 提交按可独立审查、可独立回退的阶段拆分；提交信息说明意图、约束和验证结果。
- 发布前同步 `SwiftDump/SwiftDump/main.swift` 的版本号与发布日期。
- 发布包应包含 Universal arm64/x86_64 CLI、`LICENSE`、中英文 README 和构建信息。
- Release 同时上传完整构建日志、完整回归日志和 `SHA256SUMS`。
- 上传后从公开 Release URL 下载产物并再次核对 SHA-256。
- 默认不声称 Apple notarization；只有实际提交、公证、staple 和 validate 都通过后才能标记为已公证。
