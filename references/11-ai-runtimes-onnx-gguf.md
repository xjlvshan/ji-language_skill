# 11 · 极语言调用 AI 运行时（ONNX Runtime / llama.cpp + GGUF）实测笔记

> 本文件全部结论来自本机**实测**（2026-09，Windows x64，Sc.exe 编译），每条都写了现象与证据。
> 复现工作区：`D:\SEC\project\ji-ai\`（示例 `examples/20-ai-onnx-run.txt`、`21-ai-gguf-parse.txt`、`22-ai-gguf-llama.txt`）。

## 0. 结论速览

| 能力 | 结论 | 证据 |
|---|---|---|
| 动态载入 x64 外部 DLL | ✅ 可以 | `LoadLibraryA` 返回 `0x7FFAA7990000`，`GetProcAddress` 拿到真实地址 |
| 间接调用函数指针（含 8 个参数） | ✅ 可以 | `大数 f=取址(...); 大数 r=调用 f(...)`，实测 0/1/2/3/7/8 参全部正确 |
| **ONNX Runtime 完整推理** | ✅ **已跑通** | `examples/20`：DLL→OrtApi vtable→建环境→建会话→建张量→Run→读输出，Y=X+1 得到 `40000000 40400000 40800000 40A00000 40C00000 40E00000` = 2,3,4,5,6,7 |
| GGUF 文件格式解析 | ✅ 纯极语言实现，不依赖任何 DLL | `examples/21`：读出 GGUF v3 / 35 个 KV / 320 张量 / `general.file_type=15`（Q4_K_M）/ 词表 248320 |
| llama.cpp 载入 GGUF 量化模型 | ✅ 可以（已载入并解析模型元数据） | `examples/22`：`llama_model_load_from_file` → llama.cpp 日志 `loaded meta data with 35 key-value pairs and 320 tensors ... Q4_K_M.gguf (GGUF V3)` |
| 32 位产物调 AI 库 | ❌ 不行 | onnxruntime.dll / llama.dll 本机都是 x64（machine=0x8664）→ 必须 `定义 位数=64;` |

**前提条件（缺一不可）**：`定义 位数=64;` + 用 `大数`/`变数` 保存指针 + 用 `调用 变量(...)` 做间接调用。

---

## 1. 64 位模式下的指针规则（能不能调 AI 库的分水岭）

> 主 `SKILL.md` 里原先记着「动态调用 4/4 TIMEOUT 不可用」——**那是用 `整数` 存函数指针导致的**，改用 `大数` 后全部打通。这是本次最重要的修正。

```ji
程序类型=2
模块文件=CMD.inc
定义 位数=64;                 // ← AI 库都是 x64，必须 64 位
```

| 事实 | 实测证据 |
|---|---|
| x64 下调用约定**统一**（cdecl/stdcall 不再区分），所以 llama.cpp（C, cdecl）和 onnxruntime（stdcall）都能直接调 | 两者的函数都被 `导入/调用` 成功调用 |
| **`整数` 是 32 位**，即使 64 位产物也是；API 返回的 64 位地址存进去会被截断 | `整数 i=载库(名)` → `00000000A7990000`（截断）；`大数 h=载库(名)` → `00007FFAA7990000`（完整）。截断后 `GetProcAddress` 必然返回 0 |
| `大数`、`变数` 都是 64 位，能完整保存指针 | 同上，且 `变数 v` 也得到 `00007FFAA7990000` |
| `格式化(缓冲,"%p",值)` 能打印 64 位（用 `大数`） | `api_base=00007FF9FCC7FF60`、`OrtGetApiBase=00007FF9FC04A7B0` 与 python ctypes 拿到的地址逐位一致 |
| 指针偏移读写后缀：`(偏移)$`=8 字节大数、`(偏移)&`=4 字节整数、`(偏移)%`=2 字节、`(偏移)!`=4 字节单精度、`(偏移)#`=8 字节双精 | `大数 x=$123456789; 大数 p=@x; p(0)$`→ 原值；`p[0]$`、`#$0` 同效 |
| **`(偏移)`（无后缀，读 1 字节）在 64 位模式下必崩 `0xC0000005`**，32 位模式正常 | 同一份逐字节读文件代码：`位数=64` → 崩；去掉 `定义 位数=64;` → `byte0=71`(='G') 正常 |
| `申请内存(n)` 在 64 位进程里返回的缓冲区仍落在低 4GB（实测 `0x707CC0`、`0x840080`），纯解析类代码可以存进 `整数` | 多个示例实测 |

**推论：逐字节解析二进制格式（如 GGUF）请用 32 位产物；凡是调用 x64 AI 库的代码用 64 位产物 + `大数`。**

---

## 2. 外部 DLL 调用链（实测通过）

```ji
程序类型=2
模块文件=CMD.inc
定义 位数=64;
引入 "lib\kernel32.lib";
导入 载库 别名 LoadLibraryA 支持库 "KERNEL32.DLL",1;
导入 取址 别名 GetProcAddress 支持库 "KERNEL32.DLL",2;
导入 设目录 别名 SetDllDirectoryA 支持库 "KERNEL32.DLL",1;
导入 取错 别名 GetLastError 支持库 "KERNEL32.DLL",0;
导入 冲刷 别名 fflush 支持库 "MSVCRT.DLL",1;

程序 初始启动
文本 库名[64];
复制文字(库名,"llama.dll");
大数 库=载库(库名);                 // 全路径也可以
整数 错=取错;                        // 紧跟其后取 LastError
大数 f=取址(库,"llama_backend_init");
调用 f();                            // ← 间接调用
结束
```

- `导入 ... 支持库 "XX.DLL",参数个数` **不需要 .lib**，DLL 名直接写；参数个数必须准确。
- **直接调用**导入的中文名时**不要加 `调用`**：`设目录(目录);` ✅；`调用 设目录(目录);` ❌ 编译报「符号 设目录 不存在」（`调用` 是"间接调用"关键字）。
- 实测参数个数：0、1、2、3、7（`llama_tokenize`）、8（`OrtApi::Run`）全部正确传参。
- 有依赖的 DLL：**先 `SetDllDirectoryA(依赖目录)` 再 `LoadLibraryA`**。实测「只把 llama.dll 的全路径传给 LoadLibraryA、不设目录」→ 返回 0（依赖 ggml*.dll 找不到）；先设目录 → `00007FFA23F70000` 成功。放到 .com 同目录也可以。
- 调试必备：`fflush(0)`（`冲刷(0)`）——程序崩溃时标准输出缓冲会丢失全部内容，关键步骤后冲刷一次才能定位崩溃点。

---

## 3. ONNX Runtime（onnxruntime.dll）——完整推理已跑通

### 3.1 为什么必须走 vtable

官方/pip 的 `onnxruntime.dll` **只导出 2 个名字**（实测：`OrtGetApiBase`、`OrtSessionOptionsAppendExecutionProvider_CPU`），其余几百个 API 全部在 `OrtApi` 这个"函数指针结构体"里。所以链路是：

```
OrtGetApiBase()                -> OrtApiBase*        （结构体第 0 个字段就是 GetApi）
大数 取接口 = 基(0)$            -> GetApi            （(0)$ = 读 8 字节指针）
大数 接口   = 调用 取接口(23)   -> OrtApi*           （23 = ORT_API_VERSION）
大数 建环境 = 接口(24)$         -> 函数指针
大数 状态   = 调用 建环境(...)  -> 真正调用
```

### 3.2 版本必须匹配（实测踩过）

请求的版本号大于运行时支持的版本时，`GetApi` 直接返回 `NULL`，并打印：
`The requested API version [31] is not available, only API versions [1, 23] are supported in this build.`

- 版本号取 `include/onnxruntime/core/session/onnxruntime_c_api.h` 里的 `#define ORT_API_VERSION n`
  （`main` 分支是 31，本机 onnxruntime **1.23.2** 对应的 `v1.23.2` 标签是 **23**）。
- 结构体是**只追加**的，所以低版本号 = 前缀，老偏移不会变。

### 3.3 OrtApi x64 偏移表（来自 1.23.2 头文件解析，共 382 项）

> `scripts/ort-vtable-offsets.py` 可对任意版本的头文件重新生成全表。

| 函数 | 序号 | 偏移 |
|---|---|---|
| CreateStatus | 0 | 0 |
| GetErrorCode | 1 | 8 |
| GetErrorMessage | 2 | 16 |
| **CreateEnv** | 3 | **24** |
| CreateSession | 7 | 56 |
| **CreateSessionFromArray** | 8 | **64** |
| **Run** | 9 | **72** |
| **CreateSessionOptions** | 10 | **80** |
| DisableMemPattern | 17 | 136 |
| SetSessionLogSeverityLevel | 22 | 176 |
| SetSessionGraphOptimizationLevel | 23 | 184 |
| SetIntraOpNumThreads | 24 | 192 |
| SetInterOpNumThreads | 25 | 200 |
| SessionGetInputCount | 30 | 240 |
| SessionGetOutputCount | 31 | 248 |
| SessionGetInputName | 36 | 288 |
| SessionGetOutputName | 37 | 296 |
| CreateRunOptions | 39 | 312 |
| **CreateTensorAsOrtValue** | 48 | **384** |
| CreateTensorWithDataAsOrtValue | 49 | 392 |
| **GetTensorMutableData** | 51 | **408** |
| GetTensorElementType | 60 | 480 |
| GetDimensionsCount | 61 | 488 |
| GetDimensions | 62 | 496 |
| GetTensorShapeElementCount | 64 | 512 |
| GetTensorTypeAndShape | 65 | 520 |
| GetValueType | 67 | 536 |
| **GetAllocatorWithDefaultOptions** | 78 | **624** |
| ReleaseEnv | 92 | 736 |
| ReleaseStatus | 93 | 744 |
| ReleaseTensorTypeAndShapeInfo | 99 | 792 |
| ReleaseSession | 95 | 760 |
| ReleaseValue | 96 | 768 |
| ReleaseSessionOptions | 100 | 800 |
| SessionGetModelMetadata | 111 | 888 |

枚举常量：`ORT_LOGGING_LEVEL_WARNING=2`、`ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT=1`。

### 3.4 最小可用推理（`examples/20-ai-onnx-run.txt`，实测通过）

```ji
大数 库=载库("...\onnxruntime.dll");
大数 取基=取址(库,"OrtGetApiBase");
大数 基=调用 取基();
大数 取接口=基(0)$;
大数 接口=调用 取接口(23);
大数 建环境=接口(24)$;  大数 环境=0;      大数 状态=调用 建环境(2,"probe",@环境);
大数 建选项=接口(80)$;  大数 选项=0;              调用 建选项(@选项);
// 用 开文件/文件大小/申请内存/读文件/关文件 把 .onnx 读进内存
大数 建会话=接口(64)$;  大数 会话=0;      状态=调用 建会话(环境,模型,长度,选项,@会话);
大数 取分配=接口(624)$; 大数 分配=0;              调用 取分配(@分配);
大数 形状=申请内存(16); 形状(0)$=2; 形状(8)$=3;    // int64 维度
大数 建张量=接口(384)$; 大数 输入=0;      状态=调用 建张量(分配,形状,2,1,@输入);
大数 取数据=接口(408)$; 大数 数据=0;      状态=调用 取数据(输入,@数据);
数据(0)!=1.0; 数据(4)!=2.0; 数据(8)!=3.0; 数据(12)!=4.0; 数据(16)!=5.0; 数据(20)!=6.0;
大数 入名=申请内存(8); 大数 入值=申请内存(8);
大数 出名=申请内存(8); 大数 出值=申请内存(8);
入名(0)$="X"; 出名(0)$="Y"; 入值(0)$=输入; 出值(0)$=0;   // 字符串字面量当地址写进 8 字节槽
大数 运行=接口(72)$;
状态=调用 运行(会话,0,入名,入值,1,出名,1,出值);
// 读回：出数据(0)& 等四个字节就是 float 原始位
```

### 3.5 ONNX 侧踩坑

1. **模型 IR 版本**：python `onnx` 1.21 默认写 `ir_version=13`，ORT 1.23.2 只支持到 11 → 报
   `Unsupported model IR version: 13, max supported IR version: 11`。生成模型时 `model.ir_version = 10`。
2. **名字指针数组要自己拼内存**：`入名=申请内存(8); 入名(0)$="X";`（`$` 写 8 字节；32 位数组装不下指针）。
3. **输出 float 不要用 `写格式("%.1f",...)` / `格式化(缓冲,"%.1f",...)`**：实测 6 个 `%.1f` 同一行里前几个打成乱码（`0.0 1.$ 0.0 5.0 6.0 7.0`），而同一份数据用 `(偏移)&` 打 `%08X` 完全正确。**结论：用十六进制看原始字节**（`0x40000000`=2.0、`0x40400000`=3.0、`0x40800000`=4.0、`0x40A00000`=5.0、`0x40C00000`=6.0、`0x40E00000`=7.0）。

---

## 4. GGUF 量化模型

### 4.1 纯极语言解析（不依赖任何 DLL，`examples/21-ai-gguf-parse.txt`，**32 位产物**）

格式要点（按顺序）：

```
magic           4 字节 "GGUF" = 46 55 47 47（小端读成 0x46554747）
version         u32        （实测 3）
tensor_count    u64        （实测 320）
metadata_kv_cnt u64        （实测 35）
--- 每个 KV：key(string) + type(u32) + value ---
type: 0=u8 1=i8 2=u16 3=i16 4=u32 5=i32 6=f32 7=bool 8=string 9=array 10=u64 11=i64 12=f64
array: 元素类型(u32) + 个数(u64) + 元素们
string: 长度(u64！8 字节) + 字节
--- 每个张量：name(string) + 维度数(u32) + 各维(u64) + 类型(u32) + 数据偏移(u64) ---
```

实测输出（`Qwen3.5-0.8B.Q4_K_M.gguf`，527,499,200 字节）：

```
magic = 46554747   version = 3   tensors = 320   metadata_kv = 35
general.architecture = qwen35        general.file_type = 15   （Q4_K_M）
qwen35.block_count = 24              general.quantization_version = 2
tokenizer.ggml.tokens  array<类型8> 共248320项
tokenizer.ggml.merges  array<类型8> 共247587项
output_norm.weight   [1024]        ggml_type=0     （F32）
blk.0.ffn_up.weight  [1024][3584]  ggml_type=12    （Q4_K）
```

实操要点（都踩过）：
1. **字符串长度是 u64（8 字节）**，写成 4 字节会整体错位（现象：键名打印成空、类型读成 `1701999988` 这类 ASCII 片段）。带进位：`整数 源=G数据+G位置+8;`
2. 先读 **16MB** 头部：`tokenizer.ggml.tokens/merges` 等大数组就在 KV 表里（几 MB），只读 64KB 会越界崩溃。
3. **字符串要先截断再 `内存复制`**：`如果(长>96){长=96;}` 必须放在拷贝**之前**，否则 512 字节的 `文本` 缓冲会被 chat_template 这类长字符串冲破，进而踩坏相邻全局变量。
4. 张量信息里**别忘了最后的 8 字节数据偏移**（漏掉会从第二个张量开始全是垃圾）。
5. 深嵌套（`如果` → `循环于` → `如果`）会**悄悄错编译**（实测数组跳过 2 个元素变成跳过 0 个）→ 把内层逻辑拆成独立 `程序`（如 `跳串`/`跳元素`/`打维度`）就正常。
6. 逐字节解析用 **32 位产物**（见第 1 节：64 位下 `(偏移)` 单字节读必崩）。

### 4.2 llama.cpp（llama.dll）路线（`examples/22-ai-gguf-llama.txt`）

- 需要的 DLL：`llama.dll` + `ggml.dll` + `ggml-base.dll` + `ggml-cpu-*.dll`（本机现成三套：
  `D:\CapsWriter-Offline\core\server\engines\llama\bin\`、
  `D:\Lynn\resources\llamacpp\bin\`、
  `...\site-packages\llama_cpp\lib\`）。
- 调用顺序（新版 b7xxx+ 必须这样）：
  1. `设目录(依赖目录);` → `载库("llama.dll")`
  2. `载库("ggml.dll")` → `ggml_backend_load_all_from_path(依赖目录)`
     （少了这步：`llama_model_load_from_file` 失败并提示 `no backends are loaded. hint: use ggml_backend_load() or ggml_backend_load_all()`）
  3. `llama_backend_init()`
  4. `llama_model_load_from_file(路径, llama_model_params)`
  5. 可用：`llama_model_desc`（返回带量化类型的描述，如 `Q4_K - Medium`）、`llama_model_n_params`/`llama_model_size`（u64，用 `大数` 接）、`llama_n_ctx_train`、`llama_model_get_vocab` + `llama_tokenize`
- **按值传递的大结构体**：`llama_model_params`（64 字节）在 x64 ABI 下是靠**隐藏指针**传递的，所以极语言里准备一块内存、把地址当第 2 个参数传即可：
  ```ji
  大数 参数表=申请内存(512);
  调用 取默认参数(参数表);          // llama_model_default_params 的结构体返回值也是 sret：第一个参数就是返回缓冲地址
  大数 模型=调用 载模型(路径,参数表);
  ```
  实测 llama.cpp 自己打到 stderr 的日志（说明模型真的被它读进去了）：
  ```
  llama_model_loader: loaded meta data with 35 key-value pairs and 320 tensors from ...Qwen3.5-0.8B.Q4_K_M.gguf (version GGUF V3 (latest))
  load_backend: loaded CPU backend from ...ggml-cpu-alderlake.dll
  ```
- 现实提醒：不带 mmap 载入 527MB 的 Q4_K_M 是**分钟级**；要真跑生成还得拼 `llama_batch`、`llama_sampler_chain`、上下文参数等一堆结构体，工程量大。

---

## 5. 三条务实路线（建议按场景选）

1. **极语言直接调 onnxruntime.dll**（第 3 节，已验证）——适合中小模型、要打进单个 exe、离线场景。
2. **极语言调 llama.dll 跑 GGUF**——载入和元数据已验证可行；完整生成需自建 batch/sampler 结构体，成本高，建议只做轻量用途。
3. **★推荐：极语言当外壳，推理交给本地服务**——用 Winsock（见 `05/10` 笔记，TCP 已实测）或 `命令行("curl ...")` 调
   `ollama`（127.0.0.1:11434）/ `llama-server` 的 HTTP API。GGUF 量化推理交给成熟服务，极语言只做界面、调度、文件处理，最省事也最稳。

---

## 6. 本次新增的编译器坑（补进主 SKILL.md 表）

| 坑 | 现象 | 正确写法 |
|---|---|---|
| 用 `整数` 存 API 返回的 64 位地址 | 高位被截断，后续 `GetProcAddress` 恒返回 0，`调用` 空指针 → `0xC0000005` | 用 `大数`/`变数` 接指针 |
| 64 位产物里写 `指针(偏移)`（无后缀，1 字节） | 必崩 `0xC0000005` | 加后缀：`(偏移)$/&/%/!/#`；或改用 32 位产物逐字节解析 |
| `调用 导入的中文名(...)` | 编译报「符号 X 不存在」 | `调用` 只用于函数指针变量；直接调用写 `名称(参数);` |
| `如果` → `循环于` → `如果`（三层以上嵌套） | 编译通过但逻辑悄悄错（实测跳过元素数变成 0） | 把内层拆成独立 `程序`，用调用替代嵌套 |
| `循环于` 里再嵌 `循环于` | 同上（计数/状态被搅） | 内层循环移到独立 `程序` |
| `模块文件=CMD.inc;`（配置行多写分号/空格） | `语法有误 + 内部错误` | 配置行不加任何多余符号 |
| `写格式("%d", 大数变量)` | 4/8 字节错位，后面参数全乱 | 64 位量用 `%p` 打印 |
| `写格式("%.1f",…)` 6 个浮点变参 | 前几个打成乱码 | 用 `(偏移)&` 打 `%08X` 看原始位，或手工按位拆 |
| 长字符串 `内存复制` 进定长 `文本` | 越界冲坏相邻全局变量（后续逻辑全乱/崩） | 先按缓冲大小截断长度，再拷贝 |
| 字符串里写 `\"` | 未定义的名称 | 用 `''` 表示引号，或去掉引号 |
| 只在结果处 `fflush` | 崩溃时标准输出全丢，看不到停在哪 | 关键步骤后 `冲刷(0)` |

---

## 7. 复现清单

```powershell
# 0) 环境（本机实测版本）
#    Sc.exe                D:\SEC\Sc.exe
#    onnxruntime 1.23.2    %APPDATA%\Python\Python312\site-packages\onnxruntime\capi\onnxruntime.dll
#    头文件                https://raw.githubusercontent.com/microsoft/onnxruntime/v1.23.2/include/onnxruntime/core/session/onnxruntime_c_api.h
#    llama.cpp             D:\CapsWriter-Offline\core\server\engines\llama\bin\llama.dll

# 1) ONNX 推理
powershell -File scripts\sec.ps1 -Src examples\20-ai-onnx-run.txt -Run

# 2) GGUF 头部解析（32 位产物）
powershell -File scripts\sec.ps1 -Src examples\21-ai-gguf-parse.txt -Run

# 3) llama.cpp 载入 GGUF（需要先把 llama.dll 同目录的 ggml*.dll 放到一起）
powershell -File scripts\sec.ps1 -Src examples\22-ai-gguf-llama.txt

# 4) 重新生成 OrtApi 偏移表
python scripts\ort-vtable-offsets.py --header onnxruntime_c_api.h
```
