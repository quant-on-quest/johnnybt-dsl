# johnnybt_dsl

一台装好的 **mruby 虚拟机**。跑几段 Ruby，取回它产出的那个字符串 —— 就这些。

```python
from johnnybt_dsl import compile, run

words = compile(open("dsl.rb").read(), "dsl.rb")     # 一个进程编一次
ir = run([(words, "dsl.rb"), (source, "策略.rb")], answer="MyDSL.result")
```

**词是你自己的。** 这个包不知道什么是策略、什么是因子，也不规定 IR 长什么样：
那都是拿它写 DSL 的项目说了算。写死一套词就成了只服务一个项目的库。

**装上就能用**：wheel 里 mruby 已经编好了，用的人**不需要 GCC，也不需要 Ruby**。
那两样只有我们构建 wheel 时才要。

## 安装

```sh
pip install johnnybt-dsl
```

预编译轮子，一个平台一个，`abi3` 绑 Python 3.11、覆盖 3.11–3.14：

| | x86_64 | arm64 |
|---|---|---|
| Linux | manylinux_2_28（glibc 2.28 及以上） | manylinux_2_28（glibc 2.28 及以上） |
| macOS | 10.12 及以上 | 11.0 及以上 |
| Windows | 有 | 有 |

linux 的门槛比同系的两个 polars 插件（2.17）高一档，是因为这个包要编 C：
mruby 的构建会跑它刚编出来的 `mrbc`，所以每一格都得在自己的架构上原生构建，
而 pypa 提供原生镜像的最老的一档是 glibc 2.28。

## API

| | |
|---|---|
| `compile(source, name) -> bytes` | 编成字节码。字节码和解释器无关，编一次到处 load |
| `run(chunks, answer, context) -> str` | 按顺序跑几段（源码或字节码），再跑 `answer`，返回它的字符串。`context` 进全局变量 `$johnny_context`（惯例是 JSON，基类懒解析成 `JohnnyBtDSL.context`） |
| `run_file(path, before, answer)` | 同上，最后一段读自文件 |

一次 `run` 一个解释器：一份文件定义的东西不会漏进下一份。几段之间共用一个
编译上下文，所以局部变量跨得过去 —— 它们像一段程序，不像几份互不相干的文件。

通用能力也由本包提供，不需要宿主框架注入：

- `float64("…")`：裸 VM 内置的精确标量声明 helper。
- `loads(text)` / `decode_float64(value)`：JSON IR 的保留叶子解码与有限值检查。
- `export_schema(sources)`：有超时的隔离词库元信息导出，不运行使用方配置。
- `builtin_sources()`：已安装内置词源码，供文档与源码跳转使用。

`words/float64.rb` 同一份文件编译进 VM 并随 wheel 发布；无两份 Ruby 定义。
这些通用能力不依赖 `johnnybt`。宿主只负责自己的词库发现、声明绑定和图接口。

## 里面有什么

| 件 | 做什么 |
|---|---|
| `build.rs` | 取 mruby（钉住某个 commit）、按 `build_config.rb` 编、链接 `libmruby.a` |
| `src/sys.rs` | mruby 的 C API，**手写**的 extern 声明。十来个函数，不用生成器 |
| `src/shim.c` | mruby 里是宏的那几个（`mrb_test` / `mrb->exc`）和编译入口的跳板 |
| `src/engine.rs` | 解释器的生命周期，以及「跑几段、取一个字符串」 |
| `mrbgems/mruby-json/` | 我们自己的 gem：`JSON.generate` / `#to_json` / `JSON.parse`，双向都在 C 里（解析错误带字节位） |
| `mrbgems/mruby-dsl/` | 我们自己的 gem：`JohnnyBtDSL::Base` —— DSL 的基类（注册、declare、逐语句 trouble、manifest/ir 信封、`JohnnyBtDSL.context`）。**词不在这里**，词归定义语言的项目 |

## 一处 mruby 的实情

mruby 开发线上的 Prism 编译器带**全局状态**（`mrc_init_presym` 写一个文件级的
`offset`），两个解释器同时编译会互相踩。我们钉的是稳定版，它的解析器状态都在
`mrb_parser_state` 里、没有这个全局 —— 但 `run` / `compile` 那把锁留着：一次求值
不到一毫秒，串行的代价是零，而下次挪版本时谁都不用再想起这件事。

## 构建（只有我们要）

* Rust、C 编译器
* Ruby —— mruby 自己的 rake 要它（`brew install ruby`）。解析器由 `parse.y` 生成，但生成好的 `y.tab.c` 随发布版一起来，**不要 bison**

构建走真 `rake -m`（并行）：mruby 自带的 `minirake` 完全串行，316 个目标文件
一个一个编，32 核机器上要几分钟；`rake -m` 同一棵树 **4 秒**。没有 rake 时退回
minirake。`vendor/mruby` 不进 git，第一次 `cargo build` 自己取。

测试：`vendor/mruby/build/host/bin/mruby mrbgems/run_tests.rb`（gem 那侧）与
`cargo test`（引擎那侧）。

## 许可

本包 MIT（见 `LICENSE`）。wheel 里静态链接了 **mruby**（MIT，见 `LICENSE-mruby`，
版权归 mruby developers）；两个 mrbgem（`mruby-json`、`mruby-dsl`）是本仓库自己写的，
同样 MIT。

## 配置元编程基类

`JohnnyBtDSL::Config` 是市场中立的配置对象基类，不会被注册为一门语言。
字段／嵌套／自定义词的声明同时生成行为、校验与可反射 schema。
`JohnnyBtDSL::Base.entry` 负责绑定入口、采集显式 IR 和定位失败语句。

```ruby
class FactorConfig < JohnnyBtDSL::Config
  field :reference, type: String, positional: true, required: true,
    doc: "Factor reference"
  field :weight, type: Numeric, default: 1,
    doc: "Scoring weight", impact: :strategy
end

class ResearchConfig < JohnnyBtDSL::Config
  field :name, type: String, positional: true, required: true,
    doc: "Declaration title"
  many :factors, of: FactorConfig, item: :use, doc: "Ordered factors"
end

class ResearchDSL < JohnnyBtDSL::Base
  sample "research.rb"
  entry :research, of: ResearchConfig, doc: "Declare a research configuration"
end

research "example" do
  factors do
    use("volume.bias").weight(0.7)
  end
end
```

`field` 支持原始类型、required、nullable、默认值、min/max/enum、doc、impact、
invariants；`one` / `many` 声明嵌套；`word` 同时定义参数和实现；
`validates` 的任意 Ruby 谓词在 schema 中明确标为 runtime-only。
默认字段只影响访问器，`to_h` 默认不写入省略值；整数不转换成浮点。
继承不共享实例默认容器，显式字段重定义要求 `override: true`。
`word` 实现块的参数默认值由 schema 注入；兼容绑定已有方法时保留其原默认行为，
不要复制一套原实现／Python 模板拥有的默认值。

`Config.schema` 导出配置类型；`JohnnyBtDSL.manifest` 导出语言入口与可达配置树，
含字段／参数说明、约束、来源、返回类型和 block 类型。JSON 是自动导出格式，
不是需要作者手动维护的另一份定义。现有收集器可使用 `entry(existing: true)`
和同文件 `word` 绑定保持原 IR，逐步迁入元编程 API。

## 浮点契约（0.2.0 起）

源码字面量、`String#to_f`／`Float(...)` 和 JSON 读取均使用 C locale 的
正确舍入 binary64 转换。构建时使用本仓库的 `src/readfloat.c` 替换上游的
近似 reader 对象，不修改 vendor 源码；禁止编译为 float32。
JSON 输出使用 17 位有效数字保证往返，保留浮点类型与负零，拒绝 NaN／Infinity。
不依赖 mruby `to_s` 或 `sprintf` 的展示文本来传输数值。

这修复配置解析和传输，不承诺 Ruby 与 Python 的不同计算表达式逐位等价，
也不会修复已经用旧引擎编译的字节码。升级引擎后重新编译 DSL，清理自己的
字节码缓存；不要未经验收改写历史配置或放宽对齐标准。

Rust 测试同时检查源码、预编译字节码和 JSON 往返，包括有符号零、subnormal、
相邻浮点数和最大有限值。发布流程也应从 wheel 安装后运行 Python 位模式测试。
