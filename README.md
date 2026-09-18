# ji-language · 极语言（SEC / Sc.exe）开发技能

一个给 AI Agent（以及人类）用的 **极语言开发技能包**：把 `D:\SEC` 那套中文关键字编译型语言（IDE = `Sec.exe`，编译器 = `Sc.exe`）的**实测知识**整理成 SKILL.md + 参考手册 + 编译运行工具 + 可直接跑的示例。

> 所有结论都是**在真实编译器上跑出来的**，不是文档抄录。这个编译器坑不少（文档与实现有多处不一致），按官方文档照抄大概率编译失败或程序死循环，所以本技能把"能用的写法 + 实测禁区"都标了出来。

## 内容

```
ji-language/
├── SKILL.md          # 技能入口：30 秒上手 / 源码结构 / 40+ 条陷阱表 / 语法速查 / 调试流程
├── references/       # 10 份参考手册（合计约 200KB）
│   ├── 01-toolchain.md            编译器与 IDE 行为、产物规则、.sec 二进制格式逆向、排错速查
│   ├── 02-language-core.md        词法/类型/运算符/控制流/函数/数组文本指针
│   ├── 03-basics.md               类型表、运算符表、关键字总表（标注本版支持情况）
│   ├── 04-advanced.md             指针内存、结构体、数据表、子类、常量、DLL、机器指令
│   ├── 05-console-system.md       控制台 API、命令行参数、文件读写、目录遍历、网络 TCP
│   ├── 06-gui.md                  GUI.inc 骨架、创建窗口参数、控件/消息/事件、截图验证
│   ├── 07-basics-detailed.md      基础语法逐条实测（28 条陷阱总表）
│   ├── 08-advanced-detailed.md    进阶逐条实测（机器指令 / DLL 模板 / 子类 / 列举）
│   ├── 09-gui-detailed.md         GUI 逐条实测（12 参 / 事件编码 / 风格表 / GDI）
│   └── 10-console-system-detailed.md  控制台·系统·文件·网络·加密逐条实测
├── scripts/          # 工具脚本（PowerShell，纯 ASCII，PS 5.1 兼容）
│   ├── sec.ps1            编译 + 运行（自动纠正 GBK/CRLF、判定编译失败、偶发假死自动重试）
│   ├── shot.ps1           按窗口标题/进程截图（PNG）
│   ├── sysshot.ps1        按 PID 截控制台窗口
│   ├── winprobe.ps1       枚举子窗口 / BM_CLICK / WM_SETTEXT / 读窗口标题（GUI 调试）
│   ├── build-check.ps1    编译产物加载校验（识别"BUILD_OK 但 CreateProcess 报 193"的坏镜像）
│   └── utf8-to-gbk.ps1    UTF-8 源码 → GBK + CRLF
├── examples/         # 示例源码（全部 BUILD_OK）+ 截图 + 索引
└── apps/             # 实战应用（完整工程）
    └── ji-offline-translator/   极语言复现的「离线翻译助手」：GUI + Winsock + 定时器防抖
                                  + 全屏框选截图识别 + 整套主题换色（源码 / 工具 / 截图）
```

## 快速使用

**作为 DSH 技能**：把整个目录放到 `~/.dsh/skills/ji-language/`（`.dsh/skills` 是 DSH 的技能扫描根之一），技能即出现在会话目录中。

**直接编译运行示例**（需要本机装有 `D:\SEC\Sc.exe`）：

```powershell
powershell -File scripts/sec.ps1 -Src examples/01-core-cheatsheet.txt -Run
# 输出：BUILD_OK → 编译器消息 → ARTIFACT → --- program output --- → 程序 stdout
```

**写自己的程序**：源码必须是 **GBK 编码 + CRLF 换行** 的纯文本（`.txt`），开头两行固定：

```
程序类型=2          ← 第 1 行：0=GUI(默认) 1=扩展DLL 2=控制台 3=函数类库
模块文件=CMD.inc    ← 第 2 行：控制台 CMD.inc；需要 Win32/Winsock 时写 CMD.inc,dll.inc
```

`sec.ps1` 会自动把你写的 UTF-8/LF 源码转成 GBK+CRLF，所以用任意编辑器写都可以。

## 示例（全部实测通过）

| 示例 | 主题 | 验证结果 |
|---|---|---|
| `01-core-cheatsheet` / `02-flows-cheatsheet` | 变量/算术/取模/浮点转文本/文本缓冲区/数组、四种循环/判断 | BUILD_OK，输出逐项核对 |
| `03-app-mandelbrot` | ASCII 曼德博集合（浮点运算 + 字节级拼字符串） | 渲染 22×78 图形 |
| `04-app-baseconv` | 命令行进制转换器（`启动参数` 解析命令行） | `255` → `FF` / `11111111` |
| `05-app-algorithms` | 冒泡排序 + 素数筛 + 斐波那契 | 排序正确、素数 25 个、斐波那契前 20 项 |
| `06-app-fileinfo` | 自包含文件读写（建文件/写文件/开文件/读文件/内存） | 写入 31 字节读回，行数/字符统计正确 |
| `07-gui-minimal` | 最小 GUI 骨架（窗口 + 标签 + 按钮 + 编辑框） | 截图确认控件全部显示 |
| `08-struct-table-class-dll` | 结构体 + 数据表 + 子类成员 + DLL 导入 | `GetSystemMetrics` → 屏幕宽 1920 |
| `09-bas-1..8` | 基础语法：入口/类型/转义/运算符/分支/循环/文本数组/浮点专题 | 8/8 BUILD_OK |
| `10-adv-1..13` | 指针内存/结构体/数据表/常量/跳转/机器指令/DLL/MessageBoxA/子类/列举 | 12 通过 + 1 预期失败反例 |
| `11-*` | TCP 连接探测、本机端口扫描、目录清单 | 开放端口 3080/135/445 正确识别 |
| `12-gui-1..5` | GUI 骨架/常用控件/菜单+定时器/GDI 绘图/Edit 文本复验 | 4 张截图 + 1 张复验截图 |
| `13-aux-1..2` | 控件消息常量表、控件编号/通知码编码规律 | 按手册值打印 |
| `14-sys-1..8` | 控制台能力/信息框/文件目录/进程模块/时间内存环境磁盘/网络/MD5·SHA1 | 8/8 BUILD_OK + exit=0 |

最后全量复验：**46/46 个示例 `BUILD_OK`**（另有 1 个 `90-*-expected-fail.txt` 故意复现编译错误）。

## 几条最要命的实测结论

- **入口 = 源码里第一个 `程序`**。辅助例程写在它前面就会变成入口：参数变栈地址、程序没有输出。
- 源码必须 **GBK + CRLF**：UTF-8 → 关键字乱码 `未定义的名称:绋嬪簭绫诲瀷`；LF → `内部错误 -> Invalid procedure call or argument [:第0行]`。
- **`定义 位数=64;` 是文本类卡死的通用解药**：局部 `文本 x[n]="字面量"`、结构体含 `文本` 成员、子类无参方法，在默认 32 位下会卡死/崩溃，加上这一行即正常（产物变 64 位 PE）。
- `%` 取模必须写中文：`a 余 b`（`a%b` 触发编译器内部错误）；变量不能用符号位运算（要写 `或/与/异/反/非/右移`）；比较不能当表达式。
- `判断(...)` 链不要自己写 `结束`；`如果/判断` 体里写 `结束` 会让整个程序在那里结束。
- `写格式("%f", 小数/浮点变量)` 打印 `0.000000` —— 根因是它们是 4 字节 float 而 printf 的 `%f` 要 8 字节 double；用 `双精`、`3.5#` 字面量或先拼进文本。
- 模块列表**支持逗号分隔**：`模块文件=CMD.inc,dll.inc` 解锁 Win32/Winsock 全套中文函数。
- 本版**不可用**：结构体数组、二维数组、`重置/保留/销毁/循环数组`（普通数组）、`大数` 64 位运算、子类带参/带返回值方法、动态调用 `加载库/函数地址/调用`。

完整 40+ 条见 `SKILL.md` 的陷阱表。

## 实战应用：`apps/ji-offline-translator`

用一个**完整工程**验证本技能的结论：极语言复现 aardio 版「离线翻译助手」
（CTranslate2 + PaddleOCR + Qwen2-0.5B + SQLite 引擎原样复用，前端全部由极语言写）。

| 看点 | 说明 |
|---|---|
| 输入即译 600ms 防抖 | `EN_CHANGE → 设置定时(窗体,101,600,0)` + `为 定时事件` 分支。**这是本技能最重要的修正**：`设置定时` 第 4 参数传 `@过程` 会因 TIMERPROC 蹦床调用约定不匹配，几次回调后必 `0xC0000409`（`src/_lab/tm5.txt` 崩 / `tm4.txt` 稳） |
| 截图识别 | 自建 `WS_EX_LAYERED\|TOPMOST` 全屏框选窗 + 鼠标框选（坐标在 `数据`/lParam）+ GDI `位图传输` 抓屏 + 逐行 `GetDIBits` 手写 24bpp BMP + 引擎 OCR |
| 整套主题换色 | `擦除背景` + `绘制静态/绘制编辑/绘制列表` + `LVM_SETBKCOLOR/SETTEXTCOLOR/SETTEXTBKCOLOR`，棕/深蓝/多彩三套 |
| 自动化回归 | `tools/` 里 5 个脚本：构建、键入/截图、主题校验（读回 LVM 颜色）、截图识别端到端（造目标窗口 + 真实鼠标消息）、桥协议直连测试 |

> 仓库内**不含编译产物**（本仓库 `.gitignore` 全局排除 `*.exe`）与 `engine/`（2.3 GB 模型目录联接）。
> 要跑起来：把 `apps/ji-offline-translator/` 复制到纯 ASCII 路径，按该目录 `README.md` §10 重建
> `engine` 联接，再 `powershell -File tools/build.ps1` 编译。

## 环境要求

- Windows + PowerShell 5.1（脚本用 `Add-Type` 调用少量 Win32 API 驱动编译器对话框与截图）
- 极语言环境安装在 `D:\SEC`（`Sec.exe` / `Sc.exe` / `inc\` / `lib\`）；脚本内路径按该约定写死，换目录需改 `scripts/*.ps1` 顶部的 `SecDir`
- 参考手册里另有指向 `D:\SEC\sec.htm`、`lib.htm`、`obj.htm`、`msapi.htm`（官方文档）与 `D:\SEC\code\*.sec`（官方示例）的索引

## 免责与来源

本技能包由 AI Agent 通过**在真实编译器上反复实测**整理而成（每条结论都带示例文件名与真实输出，未验证项一律标注"未实测"）。极语言本身版权归其作者所有；本仓库只包含学习笔记、工具脚本与自写示例源码。
