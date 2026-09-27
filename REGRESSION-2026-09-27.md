# 极语言 32/64 位全量回归报告（2026-09-27，编译器基线 Sc.exe 2026-09-26 版）

## 一、口径与方法

- **回归集**：技能包 `examples/` 全集 **47 个源文件 = 46 个示例 + 1 个预期失败反例**（43 个与工作区 `D:\SEC\deepseek-sec\examples\` 内容逐字节一致，4 个为技能包独有：`07-gui-minimal`、`08-struct-table-class-dll`、`11-net-tcp-connect`、`12-gui-5-edit-settext`）。覆盖：控制台、GUI、指针内存、结构体/数据表/子类、DLL 导入、系统 API（进程/模块/文件/目录/控制台/MD5）、TCP 网络。
- **双位数**：同一源码两套暂存目录 —— `m32`＝原样（默认 32 位）；`m64`＝在配置区注入一行 `定义 位数=64;`。每个源码都经 `sec.ps1` 编译（GUI 与弹窗例编译后另行启动验证）。
- **位数校验**：逐个读取产物 PE 头 machine 字段 —— 32 位轴全部 `0x014C`、64 位轴全部 `0x8664`，**位数注入100% 生效**。例外：`10-adv-10/11` 源码自带 64 位声明，32 位轴产物也是 `0x8664`（两轴实际同为 64 位）。
- **输出对比**：提取每个日志 `--- program output ---` 之后的程序 stdout → ①精确对比 → ②数字掩码（`0x..`与≥3位数字全替换为`#`，屏蔽地址/PID/句柄/时间戳）→ ③剩余差异 = 真实内容差异。
- **分类口径**：`IDENTICAL`＝stdout 完全一致；`NUMERIC-ONLY`＝仅数字（地址类）不同；`CONTENT-DIFF`＝语义内容不同；`NO-OUTPUT-xx`＝某轴崩溃/超时无输出；`BUILD-FAIL-IN-64`＝仅 64 位编译失败。
- 长耗时例单独处理：`11-app-netport` 超时 30s（默认 6s 不够）、`10-adv-9` 弹窗例单独启动探测、GUI 例启动后枚举顶层窗口判定。

## 二、总体结论

| 维度 | 32 位 | 64 位 |
|---|---|---|
| 编译 | **47/47 符合预期**（46 OK + 1 例预期失败复现 `未定义的名称:千`） | **46/47**：仅 `09-bas-1` 失败（内部错误 Overflow） |
| 运行时崩溃 | **1 例**：`14-sys-3` 0xC0000005 | **2 例**：`14-sys-1`、`06-app-fileinfo` 0xC0000005 |
| 输出与对轴一致 | — | 26 例完全一致 + 10 例仅数字差异 + **4 例真实内容差异** |
| GUI 窗口 | **6/6 无窗口（回归）** | **6/6 无窗口（回归）** |

**输出分类统计（47 例）**：IDENTICAL 26｜NUMERIC-ONLY 10｜CONTENT-DIFF 4｜崩溃无输出 3｜64 位编译失败 1｜弹窗阻塞（已知限制）1｜预期失败 1。

## 三、逐例结果（32 位 / 64 位：构建/产物machine/退出码 → 输出差异级别）

| 示例 | 类型 | 32 位 build/machine/exit | 64 位 build/machine/exit | 输出差异 |
|---|---|---|---|---|
| 01-core-cheatsheet | 控制台 | OK/0x014C/14 | OK/0x8664/14 | IDENTICAL |
| 02-flows-cheatsheet | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 03-app-mandelbrot | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 04-app-baseconv | 控制台 | OK/0x014C/10 | OK/0x8664/10 | IDENTICAL |
| 05-app-algorithms | 控制台 | OK/0x014C/10 | OK/0x8664/10 | NUMERIC-ONLY |
| 06-app-fileinfo | 控制台 | OK/0x014C/1 | OK/0x8664/**0xC0000005** | NO-OUTPUT-64 |
| 07-gui-minimal | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 08-struct-table-class-dll | 控制台 | OK/0x014C/18 | OK/0x8664/18 | IDENTICAL |
| 09-bas-1 | 控制台 | OK/0x014C/0 | **FAIL 内部错误 Overflow** | BUILD-FAIL-IN-64 |
| 09-bas-2 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 09-bas-3 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 09-bas-4 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | **CONTENT-DIFF** |
| 09-bas-5 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 09-bas-6 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 09-bas-7 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | **CONTENT-DIFF** |
| 09-bas-8 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 10-adv-1 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 10-adv-10 ★ | 控制台 | OK/**0x8664**/10 | OK/0x8664/10 | IDENTICAL（自带 64 位声明） |
| 10-adv-11 ★ | 控制台 | OK/**0x8664**/10 | OK/0x8664/10 | IDENTICAL（自带 64 位声明） |
| 10-adv-13 | 控制台 | OK/0x014C/17 | OK/0x8664/17 | IDENTICAL |
| 10-adv-2 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | **CONTENT-DIFF** |
| 10-adv-3 | 控制台 | OK/0x014C/7 | OK/0x8664/7 | IDENTICAL |
| 10-adv-4 | 控制台 | OK/0x014C/24 | OK/0x8664/24 | IDENTICAL |
| 10-adv-5 | 控制台 | OK/0x014C/22 | OK/0x8664/22 | IDENTICAL |
| 10-adv-6 | 控制台 | OK/0x014C/10 | OK/0x8664/10 | IDENTICAL |
| 10-adv-7 | 控制台 | OK/0x014C/31 | OK/0x8664/37 | NUMERIC-ONLY（exit 不同） |
| 10-adv-8 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 10-adv-9 | 弹窗 | OK/0x014C/弹窗可见 | OK/0x8664/弹窗可见 | NO-OUTPUT（已知：控制台弹框不可自动化关闭，stdout 不落盘） |
| 11-app-filelist | 控制台 | OK/0x014C/14 | OK/0x8664/14 | IDENTICAL |
| 11-app-netport | TCP | OK/0x014C/0（30s 内完成） | OK/0x8664/0 | IDENTICAL |
| 11-net-tcp-connect | TCP | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 12-gui-1 | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 12-gui-2 | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 12-gui-3 | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 12-gui-4 | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 12-gui-5-edit-settext | GUI | OK/0x014C/窗口不存在 | OK/0x8664/窗口不存在 | IDENTICAL（同为无窗口） |
| 13-aux-1 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 13-aux-2 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | IDENTICAL |
| 14-sys-1 | 控制台 | OK/0x014C/0 | OK/0x8664/**0xC0000005** | NO-OUTPUT-64 |
| 14-sys-2 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 14-sys-3 | 控制台 | OK/0x014C/**0xC0000005** | OK/0x8664/0 | NO-OUTPUT-32 |
| 14-sys-4 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | **CONTENT-DIFF** |
| 14-sys-5 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 14-sys-6 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 14-sys-7 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 14-sys-8 | 控制台 | OK/0x014C/0 | OK/0x8664/0 | NUMERIC-ONLY |
| 90-adv-12-expected-fail | 反例 | FAIL（预期：`未定义的名称:千`） | FAIL（预期） | EXPECTED-FAIL |

★ `10-adv-10/11` 源码自带 `定义 位数=64;`，"32 位轴"产物亦为 64 位。

## 四、真实输出差异明细（CONTENT-DIFF 4 例，方向均为「64 位错、32 位对」）

1. **09-bas-4（字面量运算回归）**
   - 32 位（正确）：`字面量符号位运算: 1|2=3 1&3=1 1^3=2 ~1=-2`、`8>>1=4 1<<3=8`、`1+2*3=7`、`(1+2)*3=9`、`如果是(数>值,100,200) = 100`
   - 64 位（错误）：`1|2=588690`、`1^3=-4202866`、`8>>1=294345`、`1<<3=33623152`、`1+2*3=12903177`、`(1+2)*3=12608931`、`如果是(数>值,100,200) = 200`
   - 规律：**变量**参与的算术/位运算/比较全部正常，**字面量常量**参与的位运算、移位、优先级表达式、`如果是` 三目求值在 64 位下输出垃圾 → 64 位字面量求值回归。
2. **09-bas-7 与 10-adv-2（`检索` 回归）**
   - `检索(数列,9,8)`：32 位 `=2`（正确）→ 64 位 `=8`；`检索(数列,99,8)`：32 位 `-1` → 64 位 `0`；adv-2 同型：`检索(m,67,32)` 32 位 `=2` → 64 位 `=32`、未命中 32 位 `-1` → 64 位 `0`。
   - 规律：64 位下 `检索` 似返回了参数值/垃圾而非下标，未命中也不返回 -1。
3. **14-sys-4（进程/模块枚举回归）**
   - 32 位：进程快照完整（`PID=0…csrss.exe…` 共 12 个）、模块列表带真实基址与名称。
   - 64 位：`进程快照` 只列出 1 个空名进程、`基址=0x0 名称=`、大小为负数垃圾 → **64 位下 TOOLHELP 结构体（含文本成员）布局/传参错位**（与 9/14、9/26「结构体对齐」改动时间线吻合）。

NUMERIC-ONLY 10 例为地址/PID/句柄/开机毫秒差异（05、bas-8、adv-7、adv-8、aux-1、sys-2/5/6/7/8），属预期；其中 `10-adv-7` 退出码 31↔37 亦仅为输出文本长度差。

## 五、崩溃与编译失败清单（各 3 次复测，全部确定性）

| 示例 | 位数 | 现象 | 对比 9/17 基线 |
|---|---|---|---|
| 14-sys-3（文件与目录） | **32** | 启动即 0xC0000005，stdout 0 字节 | 9/17 基线 exit=0 正常 → **新回归**；同例 64 位正常（双轴倒置） |
| 14-sys-1（控制台能力） | **64** | 0xC0000005，stdout 0 字节 | 32 位正常 |
| 06-app-fileinfo（文件读写） | **64** | 0xC0000005，stdout 0 字节 | 32 位正常（exit=1） |
| 09-bas-1 | **64** | 编译：`内部错误 -> Overflow [第26行]`（报错行号偏 2，实际约第 28 行 `整数 缺省=加法();` 省略实参调用附近） | 32 位正常 |

绕行方案：这 4 例换用另一轴即可正常运行/编译。

## 六、GUI 全量无窗口回归 —— 根因定位（本次附加调查）

**症状**：6 个 GUI 例 ×2 位数全部 —— 编译 BUILD_OK，进程存活（0 CPU、线程全部 Wait/UserRequest，消息循环空转），但**顶层窗口数为 0**（`EnumWindows` 该 PID 无任何窗口，`MainWindowHandle=0`）。9/17 旧编译器下同一批示例均有窗口截图 → **确定为 9/22–9/26 编译器更新引入的回归**。

**定位链**（探针源码见 `tmp\regress2\m32\{gui1,gui2,gui3,gui4}-dbg.txt`、`rawwin*.txt`，全部编译运行实测）：

1. **控制台程序**直接 `导入` RegisterClassExA + CreateWindowExA（手动字节填充 WNDCLASSEX、字面量类名/标题）→ **成功**（`reg=50089, win=855318`）→ 32 位 FFI 与 user32 本身可用。
2. **GUI 程序**里把 `列举 界面{…}` 填充的窗口类结构交给同一个 RegisterClassExA → **`err=87 参数不正确`**；同一结构改用**手动字节填充**→ **成功（atom=49882）** → **根因①：`列举/窗口类` 结构体字段填充在新编译器下错位 → 窗口类注册失败**。
3. `创建窗口` builtin → `返回 0，GetLastError=487 "Attempt to access invalid address"`；补充复现：**根因②：常量字符串（如 `程序.名称`）作 API 第 2 参 → 指针无效**（同常量作第 3 参标题 → 成功；字面量作第 2 参 → 成功）。子窗口 `err=1406` 是父窗口为 0 的连锁。
4. 探针还复证了一条技能规则：**GUI.inc 的 `程序入口` 排在用户代码之前 → 用户源码里重复写的 `程序入口` 被静默忽略**（gui-1 源码中那份从未执行，A 探针行因此从未打印）。

时间线吻合：9/23–9/26 更新日志正含「子类对象虚函数表按位宽对齐」「结构体对齐」「修改极语言程序为专属调用约定规范」「传参关键字/栈式编程」等结构性改动。

**附**：`10-adv-9` 弹窗例在双位数下 MessageBox 均正常弹出（`#32770` 可见）；但自动化 WM_CLOSE / BM_CLICK 均无法使其退出（与技能既有结论一致：控制台弹框救不回），stdout 不可捕获，故输出对比记 N/A。

## 七、复现方式

```powershell
# 矩阵（94 次编译+运行，约 8 分钟）与报告
powershell -NoProfile -File D:\SEC\deepseek-sec\tmp\run-matrix.ps1
powershell -NoProfile -File D:\SEC\deepseek-sec\tmp\run-matrix-report.ps1
# 产物与日志：D:\SEC\deepseek-sec\tmp\regress2\{m32,m64,out32,out64,rep}
# rep\summary.csv（逐例 JSON/CSV）、rep\diff-*.txt（内容差异明细）
# GUI 根因探针：m32\gui1~gui4-dbg.txt、m32\rawwin*.txt（均经 sec.ps1 实测）
# 顶层窗口枚举工具：D:\SEC\deepseek-sec\tools\winenum.ps1（已随技能发布 scripts\winenum.ps1）
```

## 八、与技能基线的差异汇总（skill 已同步更新）

- 9/17 基线「46/46 BUILD_OK + exit=0」→ 现状：**32 位编译 46/46 仍全部通过**，但 `14-sys-3` 运行崩溃；**64 位新增 09-bas-1 编译失败、sys-1/fileinfo 崩溃、bas-4/bas-7/adv-2/sys-4 输出错误**。
- 新增关键字：`传参`（movepar，2026-09-25 加入，手册 sec.htm 已有条目，实测编译通过、运行语义未验证）；`小程序`/`程序段` 实测仍报「未定义的名称」（9/14「统一改为程序」＝移除旧关键字）。
- 新增工具：`winenum.ps1`（顶层窗口枚举 / #32770 弹窗定位点击）。
- 更新检测方法：`D:\SEC\UpLog.txt`（GBK）顶部即最新更新日志；`D:\SEC\*.zip` 实为 CAB（MSCF）更新包。
