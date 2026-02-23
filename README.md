# SimpleBacktraceDemo - 项目总览

## 🎯 项目目标

从 Matrix 的 `kssc_backtraceCurrentThread` 函数中提取核心逻辑，创建一个**简化版、易于理解**的堆栈回溯工具，帮助开发者学习 iOS 堆栈回溯的底层原理。

## 📁 项目结构

```
SimpleBacktraceDemo/
├── 📄 README.md                    # 详细说明文档
├── 📄 快速开始.md                   # 快速上手指南 ⭐
├── 📄 特性对比.md                   # 与 Matrix 的对比
├── 📄 项目总览.md                   # 本文档
│
├── 📁 SimpleBacktraceDemo.xcodeproj/  # Xcode 项目文件
│   └── project.pbxproj
│
└── 📁 SimpleBacktraceDemo/          # 源代码目录
    ├── 🔧 SimpleBacktrace.h        # 堆栈回溯工具 - 头文件
    ├── 🔧 SimpleBacktrace.m        # 堆栈回溯工具 - 实现 ⭐⭐⭐
    ├── 📱 ViewController.h         # 演示界面 - 头文件
    ├── 📱 ViewController.m         # 演示界面 - 实现 ⭐
    ├── 🎬 AppDelegate.h           # 应用委托 - 头文件
    ├── 🎬 AppDelegate.m           # 应用委托 - 实现
    ├── 🚀 main.m                  # 入口函数
    └── ⚙️ Info.plist              # 配置文件
```

## 🌟 核心文件说明

### 1. SimpleBacktrace.m（⭐⭐⭐ 核心实现）

**300 行代码实现完整的堆栈回溯！**

#### 核心功能

```objc
// 1. 获取当前线程堆栈（使用 backtrace）
+ (NSArray<BacktraceFrame *> *)captureCurrentThreadBacktrace:(NSInteger)maxDepth
                                                   skipFrames:(NSInteger)skipFrames;

// 2. 获取其他线程堆栈（使用 Mach API + FP 遍历）
+ (NSArray<BacktraceFrame *> *)captureBacktraceOfThread:(thread_t)thread
                                                maxDepth:(NSInteger)maxDepth;

// 3. 获取主线程堆栈（卡顿检测专用）
+ (NSArray<BacktraceFrame *> *)captureMainThreadBacktrace:(NSInteger)maxDepth;

// 4. 格式化输出
+ (NSString *)formatBacktrace:(NSArray<BacktraceFrame *> *)frames;
```

#### 核心算法（ARM64 FP 遍历）

```objc
+ (int)getThreadBacktrace:(thread_t)thread
                   buffer:(uintptr_t *)buffer
                  maxSize:(int)maxSize {
    
    // ✅ 步骤1：获取寄存器状态
    _STRUCT_ARM_THREAD_STATE64 threadState;
    thread_get_state(thread, ARM_THREAD_STATE64, &threadState, ...);
    
    // ✅ 步骤2：第一帧返回 PC
    buffer[0] = threadState.__pc;
    
    // ✅ 步骤3：通过 FP 链表遍历后续帧
    uintptr_t currentFP = threadState.__fp;
    
    while (currentFP != 0 && index < maxSize) {
        // 读取栈帧（16 字节）
        FrameEntry frame;
        memcpy(&frame, (void *)currentFP, sizeof(frame));
        
        // 保存返回地址
        buffer[index++] = frame.returnAddress;
        
        // 移动到上一个栈帧
        currentFP = (uintptr_t)frame.previous;
    }
    
    return index;
}
```

### 2. ViewController.m（⭐ 演示界面）

**200 行代码实现 3 个测试场景！**

#### 测试场景

| 按钮 | 测试内容 | 技术点 |
|------|---------|--------|
| 🔵 按钮1 | 当前线程堆栈 | `backtrace()` API |
| 🟠 按钮2 | 主线程卡顿检测 | Mach API + FP 遍历 ⭐⭐⭐ |
| 🟢 按钮3 | 多层函数调用 | 完整调用链验证 |
| 🔴 按钮4 | 清空输出 | UI 操作 |

#### 核心演示代码

```objc
// 测试2：模拟卡顿检测（最重要！）
- (void)simulateLagAndCapture {
    // 在子线程监控主线程
    dispatch_async(dispatch_get_global_queue(...), ^{
        // 获取主线程堆栈
        NSArray *frames = [SimpleBacktrace captureMainThreadBacktrace:50];
        
        // 显示结果
        NSString *result = [SimpleBacktrace formatBacktrace:frames];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendOutput:result];
        });
    });
    
    // 主线程卡顿 2 秒
    [NSThread sleepForTimeInterval:2.0];
}
```

## 🔑 关键技术点

### 1. ARM64 栈帧结构

```
完整的栈帧布局（从高地址到低地址）：

High Address (栈底)
    ↑
   ├─ main() 的栈帧
   │  ┌────────────────┐
   │  │ 0x100004000    │  ← [FP₀+8] main 的返回地址 (高地址)
   │  ├────────────────┤
   │  │ NULL           │  ← FP₀ (没有上一个栈帧，低地址)
   │  └────────────────┘
    │
   ├─ funcA() 的栈帧
   │  ┌────────────────┐
   │  │ 0x100001234    │  ← [FP₁+8] 在 main 中的返回地址 (高地址)
   │  ├────────────────┤
   │  │ FP₀            │  ← FP₁ (链表指针，低地址)
   │  └────────────────┘
   │
   ├─ funcB() 的栈帧
   │  ┌────────────────┐
   │  │ 0x100002456    │  ← [FP₂+8] 在 funcA 中的返回地址 (高地址)
   │  ├────────────────┤
   │  │ FP₁            │  ← FP₂ (链表指针，低地址)
   │  └────────────────┘
    ↓
Low Address (栈顶)
```

**关键寄存器：**
- **x29 (FP)**: 指向当前栈帧，形成链表
- **x30 (LR)**: 保存返回地址
- **PC**: 当前执行的指令地址
- **SP**: 栈顶指针

---

### 栈回溯核心原理

#### 🎯 两条关键信息链

1. **FP 链**：用于遍历栈帧（找到"上一个函数"）
2. **LR 链**：用于定位代码位置（找到"调用位置"）

#### 回溯过程详解

假设调用链：`main() → funcA() → funcB() → funcC()`

**步骤 0：获取当前位置**

```
从寄存器读取：
- PC (当前执行位置) = 0x100003000  ← 第 0 帧（funcC 内部）

栈帧 #0: 0x100003000 (funcC 内部)
```

**步骤 1：回溯到 funcB**

```
从寄存器读取：
- x29 (FP) = 0x16fdff0a0  ← funcC 的栈帧

从内存读取 funcC 的栈帧：
┌─────────────────┐
│ 0x100002456     │ ← [FP+8] 返回地址 = funcB 调用 funcC 的位置
├─────────────────┤
│ 0x16fdff0b0     │ ← [FP+0] Previous FP = funcB 的栈帧
└─────────────────┘  ← FP (0x16fdff0a0)

栈帧 #1: 0x100002456 (funcB 中调用 funcC 后的位置)
下一个 FP = 0x16fdff0b0
```

**步骤 2：回溯到 funcA**

```
从内存读取 funcB 的栈帧（FP = 0x16fdff0b0）：
┌─────────────────┐
│ 0x100001234     │ ← [FP+8] 返回地址 = funcA 调用 funcB 的位置
├─────────────────┤
│ 0x16fdff0c0     │ ← [FP+0] Previous FP = funcA 的栈帧
└─────────────────┘  ← FP (0x16fdff0b0)

栈帧 #2: 0x100001234 (funcA 中调用 funcB 后的位置)
下一个 FP = 0x16fdff0c0
```

**步骤 3：回溯到 main**

```
从内存读取 funcA 的栈帧（FP = 0x16fdff0c0）：
┌─────────────────┐
│ 0x100000f00     │ ← [FP+8] 返回地址 = main 调用 funcA 的位置
├─────────────────┤
│ 0x16fdff0d0     │ ← [FP+0] Previous FP = main 的栈帧
└─────────────────┘  ← FP (0x16fdff0c0)

栈帧 #3: 0x100000f00 (main 中调用 funcA 后的位置)
下一个 FP = 0x16fdff0d0
```

**步骤 4：到达栈底**

```
从内存读取 main 的栈帧（FP = 0x16fdff0d0）：
┌─────────────────┐
│ 0x100004000     │ ← [FP+8] 返回地址 = 入口点
├─────────────────┤
│ 0x0 (NULL)      │ ← [FP+0] Previous FP = NULL (链表结束)
└─────────────────┘  ← FP (0x16fdff0d0)

栈帧 #4: 0x100004000 (系统入口点)
Previous FP = NULL → 回溯结束！
```

#### 代码实现

```objc
// 第一帧：从寄存器读取当前 PC
buffer[0] = threadState.__pc;  // ← 当前执行位置

// 后续帧：遍历 FP 链表
uintptr_t currentFP = threadState.__fp;  // ← 从寄存器读取 FP

while (index < maxSize && currentFP != 0) {
    // 读取栈帧（16 字节）
    FrameEntry frame;
    memcpy(&frame, (void *)currentFP, sizeof(frame));
    
    // 栈帧结构：
    // ┌────────────────┐
    // │ returnAddress  │ ← [FP+8] 返回地址（调用位置）
    // ├────────────────┤
    // │ previous       │ ← [FP+0] 上一个 FP（用于继续遍历）
    // └────────────────┘
    
    if (frame.previous == NULL || frame.returnAddress == 0) {
        break;  // 到达栈底
    }
    
    buffer[index++] = frame.returnAddress;  // ← 保存返回地址
    currentFP = (uintptr_t)frame.previous;  // ← 移动到上一个栈帧
}
```

#### 地址符号化

回溯得到的是**代码地址**，需要通过 `dladdr()` 转换为**函数名**：

```objc
// 获取到的地址数组：
addresses = [0x100003000, 0x100002456, 0x100001234, 0x100000f00]

// 符号化过程：
for (uintptr_t addr : addresses) {
    Dl_info info;
    dladdr((void *)addr, &info);
    
    // info.dli_fname = "/path/to/MyApp"          (镜像路径)
    // info.dli_sname = "funcC" / "funcB" / ...   (符号名)
    // info.dli_saddr = 函数起始地址
    
    printf("%s + %ld\n", 
           info.dli_sname, 
           addr - info.dli_saddr);  // 计算偏移量
}
```

#### 最终输出效果

```
📚 堆栈信息：
═══════════════════════════════════════
 0  0x100003000  MyApp  funcC + 0
 1  0x100002456  MyApp  funcB + 86
 2  0x100001234  MyApp  funcA + 52
 3  0x100000f00  MyApp  main + 240
 4  0x100004000  dyld   start + 0
```

#### 关键点总结

| 组件 | 作用 | 信息来源 |
|------|------|----------|
| **PC (第 0 帧)** | 当前执行位置 | 寄存器 `threadState.__pc` |
| **FP 链** | 遍历栈帧（向上追溯） | `[FP+0]` → Previous FP |
| **LR 链** | 定位调用位置（代码地址） | `[FP+8]` → Return Address |
| **dladdr()** | 地址 → 函数名 | 查询动态链接器符号表 |

#### 为什么是"调用位置"而不是"函数入口"？

**返回地址 = 调用指令的下一条指令**

```armasm
funcA:
0x100001000:  ...
0x100001230:  bl    funcB        ; ← 调用 funcB
0x100001234:  mov   x0, #1       ; ← 返回地址（LR = 0x100001234）
              ↑
              │
              回溯时看到的地址，表示"在 funcA 中调用了 funcB"
```

所以输出会显示 `funcA + 52`（相对 funcA 入口的偏移），表示"在 funcA 的第 52 字节处调用了下一个函数"。

---

### 2. 核心 Mach API

```objc
// 1. 挂起线程（必须！）
kern_return_t thread_suspend(thread_t thread);

// 2. 获取寄存器状态
kern_return_t thread_get_state(
    thread_t thread,                          // 目标线程
    thread_state_flavor_t flavor,            // ARM_THREAD_STATE64
    thread_state_t state,                    // 输出缓冲区
    mach_msg_type_number_t *stateCount       // 缓冲区大小
);

// 3. 恢复线程
kern_return_t thread_resume(thread_t thread);

// 4. 符号化地址
int dladdr(const void *address, Dl_info *info);
```

### 3. Matrix 卡顿检测原理

```
┌─────────────────────────────────────────────┐
│  监控线程（子线程）                          │
│                                             │
│  while (监控开启) {                         │
│      sleep(检查间隔);                       │
│                                             │
│      if (主线程响应超时) {                   │
│          // 🔴 检测到卡顿！                  │
│                                             │
│          1. 挂起主线程                       │
│             thread_suspend(mainThread);     │
│                                             │
│          2. 获取主线程堆栈                   │
│             captureBacktrace(mainThread);   │
│                                             │
│          3. 恢复主线程                       │
│             thread_resume(mainThread);      │
│                                             │
│          4. 符号化并上报                     │
│             symbolicate() + report();       │
│      }                                      │
│  }                                          │
└─────────────────────────────────────────────┘
```

### Matrix 源码

- `KSStackCursor_SelfThread.c` - 本项目的参考源码
- `KSStackCursor_MachineContext.c` - FP 遍历实现
- `KSSymbolicator.c` - 符号化实现

## 📦 ARM64 函数参数传递机制

### 重要概念纠正

**ARM64 寄存器是 64 位（8 字节），不是 8 位**
- **64 位** = 8 字节 = 可以存储 64 位的数据（地址、整数等）
- ARM64 有 31 个通用寄存器：`x0-x30`（64位）或 `w0-w30`（32位低位部分）

### AAPCS64 调用约定

ARM64 使用 **AAPCS64**（ARM Architecture Procedure Call Standard）调用约定，规定了参数如何传递。

#### 1. 整数/指针参数（前 8 个）

```armasm
// C 代码：
void myFunction(int a, int b, int c, int d, int e, int f, int g, int h);
myFunction(1, 2, 3, 4, 5, 6, 7, 8);

// ARM64 汇编：
mov   x0, #1    // 参数 1 → x0
mov   x1, #2    // 参数 2 → x1
mov   x2, #3    // 参数 3 → x2
mov   x3, #4    // 参数 4 → x3
mov   x4, #5    // 参数 5 → x4
mov   x5, #6    // 参数 6 → x5
mov   x6, #7    // 参数 7 → x6
mov   x7, #8    // 参数 8 → x7
bl    _myFunction
```

**规则：前 8 个整数/指针参数通过寄存器 `x0-x7` 传递**

#### 2. 超过 8 个参数（栈传递）

```armasm
// C 代码：
void funcWithManyArgs(int p1, int p2, ..., int p10, int p11);
funcWithManyArgs(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11);

// ARM64 汇编：
// 前 8 个参数用寄存器
mov   x0, #1
mov   x1, #2
...
mov   x7, #8

// 第 9-11 个参数压入栈
str   x9, [sp, #0]     // 参数 9
str   x10, [sp, #8]    // 参数 10
str   x11, [sp, #16]   // 参数 11

bl    _funcWithManyArgs
```

**栈布局（调用前）：**

```
高地址 ↑
┌──────────────┐
│ 参数 11      │ ← [sp + 16]
├──────────────┤
│ 参数 10      │ ← [sp + 8]
├──────────────┤
│ 参数 9       │ ← [sp + 0]
├══════════════┤ ← SP (调用前)
│ LR (x30)     │
├──────────────┤
│ FP (x29)     │
└──────────────┘
低地址 ↓
```

#### 3. 浮点参数

```armasm
// C 代码：
void computeFloat(double a, float b, double c);

// ARM64 汇编：
fmov  d0, #1.0    // 参数 1 (double) → d0 (v0 的 64 位部分)
fmov  s1, #2.0    // 参数 2 (float)  → s1 (v1 的 32 位部分)
fmov  d2, #3.0    // 参数 3 (double) → d2 (v2 的 64 位部分)
bl    _computeFloat
```

**规则：前 8 个浮点参数通过 `v0-v7`（或 `d0-d7`、`s0-s7`）传递**

#### 4. 结构体/对象参数

**小结构体（≤ 16 字节）：**

```objc
struct Point {
    double x;  // 8 字节
    double y;  // 8 字节
};

void drawPoint(struct Point p);

// 汇编：
// Point.x → x0 (前 8 字节)
// Point.y → x1 (后 8 字节)
fmov  x0, d0    // x = 1.0
fmov  x1, d1    // y = 2.0
bl    _drawPoint
```

**大结构体（> 16 字节）：**

```objc
struct LargeData {
    char data[100];
};

void processData(struct LargeData data);

// 汇编：
// 1. 在栈上分配空间
// 2. 复制结构体到栈
// 3. 传递栈地址（指针）到 x0
sub   sp, sp, #128
mov   x8, sp           // x8 = 栈上的临时空间
// ... 复制数据到 [x8] ...
mov   x0, x8           // 传递地址
bl    _processData
```

#### 5. Objective-C 方法调用

```objc
// Objective-C 代码：
[myObject setName:@"Hello" age:25];

// 对应的 C 函数签名：
void objc_msgSend(id self, SEL _cmd, NSString *name, int age);

// ARM64 汇编：
mov   x0, x20         // self (对象指针) → x0
adrp  x1, l_OBJC_SELECTOR@PAGE
add   x1, x1, l_OBJC_SELECTOR@PAGEOFF  // _cmd (selector) → x1
adrp  x2, @"Hello"
add   x2, x2, ...     // name (@"Hello") → x2
mov   w3, #25         // age (25) → w3 (x3 的低 32 位)
bl    _objc_msgSend
```

**关键点：**
- `x0` = `self`（隐式参数）
- `x1` = `_cmd`（选择器，隐式参数）
- `x2` = 第一个显式参数 `name`
- `x3` = 第二个显式参数 `age`

### 寄存器使用规则

| 寄存器 | 用途 | 调用时是否保留？ |
|--------|------|------------------|
| **x0-x7** | 参数传递 & 返回值 (x0) | ❌ Caller-saved（调用者保存） |
| **x8** | 间接返回值地址 | ❌ Caller-saved |
| **x9-x15** | 临时寄存器 | ❌ Caller-saved |
| **x16-x17 (IP0/IP1)** | 过程内调用临时寄存器 | ❌ Caller-saved |
| **x18** | 平台寄存器（iOS 保留） | ✅ 不可用 |
| **x19-x28** | 被调用者保存寄存器 | ✅ Callee-saved（被调用者保存） |
| **x29 (FP)** | Frame Pointer | ✅ Callee-saved |
| **x30 (LR)** | Link Register | ✅ Callee-saved |
| **SP** | Stack Pointer | ✅ Callee-saved |

### 参数传递总结

| 参数类型 | 存储位置 | 数量限制 |
|---------|---------|---------|
| **整数/指针** | `x0-x7` | 前 8 个 |
| **浮点数** | `v0-v7` (d0-d7, s0-s7) | 前 8 个 |
| **超出参数** | 栈 | 无限制 |
| **小结构体** (≤16B) | `x0-x1` 或 `x0-x7` | 取决于大小 |
| **大结构体** (>16B) | 栈（传递指针） | - |
| **返回值** | `x0` (整数) 或 `v0` (浮点) | - |

### 为什么栈回溯不需要关心参数？

- 参数在**函数调用时**通过寄存器/栈传递
- 函数执行中，参数可能被**修改或优化掉**
- 栈帧中只保留 **FP 和 LR**（足够重建调用链）
- 参数信息在调试符号（DWARF）中，但运行时不保证可用

**核心要点：**
> 栈回溯只需要 FP 链（找到上一个函数）和 LR 链（找到调用位置），参数信息不是必需的。ARM64 通过寄存器传递参数提高了效率，而栈帧只保留最小的必要信息（FP + LR）。

---




