# SimpleBacktraceDemo

简化版堆栈回溯工具演示项目

## 📚 项目简介

这是一个从 Matrix 的 `kssc_backtraceCurrentThread` 函数中提取和简化的堆栈回溯工具演示项目。

### 核心功能

1. **获取当前线程堆栈**：使用 POSIX `backtrace()` API
2. **获取其他线程堆栈**：使用 Mach API (`thread_get_state` + FP 遍历)
3. **符号化地址**：使用 `dladdr()` 将地址转换为函数名
4. **格式化输出**：友好的堆栈信息展示

## 🔑 核心原理

### ARM64 堆栈遍历

```
ARM64 栈帧结构（16 字节）：
┌────────────────┐
│ LR (x30)       │  ← FP + 8 (返回地址)
├────────────────┤
│ previous FP    │  ← FP + 0 (上一个帧指针)
└────────────────┘  ← 当前 FP (x29)
```

### 实现步骤

1. **挂起目标线程** (`thread_suspend`)
2. **获取寄存器状态** (`thread_get_state`)
3. **第一帧返回 PC**（当前执行位置）
4. **后续帧通过 FP 链表遍历**
5. **恢复线程** (`thread_resume`)
6. **符号化地址** (`dladdr`)

## 📂 项目结构

```
SimpleBacktraceDemo/
├── SimpleBacktrace.h          # 堆栈回溯工具头文件
├── SimpleBacktrace.m          # 核心实现
├── ViewController.m           # 演示界面
├── AppDelegate.m             # 应用入口
├── main.m                    # Main 函数
└── Info.plist               # 配置文件
```

## 🎯 演示功能

### 测试 1：获取当前线程堆栈

```objc
NSArray<BacktraceFrame *> *frames = 
    [SimpleBacktrace captureCurrentThreadBacktrace:50 skipFrames:2];
```

输出示例：
```
0  SimpleBacktraceDemo  -[ViewController captureCurrentThreadStack] + 52
1  UIKitCore            -[UIApplication sendAction:to:from:forEvent:] + 96
2  UIKitCore            -[UIControl sendAction:to:forEvent:] + 64
...
```

### 测试 2：模拟卡顿，获取主线程堆栈

模拟主线程卡顿 2 秒，从子线程捕获主线程的堆栈。

```objc
// 子线程监控主线程
dispatch_async(dispatch_get_global_queue(...), ^{
    NSArray *frames = [SimpleBacktrace captureMainThreadBacktrace:50];
});

// 主线程卡顿
[NSThread sleepForTimeInterval:2.0];
```

### 测试 3：多层函数调用

测试嵌套函数调用的堆栈追踪：
```
level4 → level3 → level2 → level1 → testNestedCalls → ...
```

## 🛠️ 使用方法

### 1. 打开项目

```bash
cd /Users/momo/Desktop/SimpleBacktraceDemo
open SimpleBacktraceDemo.xcodeproj
```

### 2. 运行项目

- 选择模拟器或真机
- 点击 Run (⌘R)

### 3. 测试功能

在应用界面点击对应按钮测试不同的功能。

## 📖 API 说明

### SimpleBacktrace 类

#### 获取当前线程堆栈
```objc
+ (NSArray<BacktraceFrame *> *)captureCurrentThreadBacktrace:(NSInteger)maxDepth
                                                   skipFrames:(NSInteger)skipFrames;
```

#### 获取指定线程堆栈
```objc
+ (NSArray<BacktraceFrame *> *)captureBacktraceOfThread:(thread_t)thread
                                                maxDepth:(NSInteger)maxDepth;
```

#### 获取主线程堆栈
```objc
+ (NSArray<BacktraceFrame *> *)captureMainThreadBacktrace:(NSInteger)maxDepth;
```

#### 格式化输出
```objc
+ (NSString *)formatBacktrace:(NSArray<BacktraceFrame *> *)frames;
```

### BacktraceFrame 类

堆栈帧信息：

```objc
@property (nonatomic, assign) uintptr_t address;        // 地址
@property (nonatomic, copy) NSString *imageName;        // 镜像名
@property (nonatomic, copy) NSString *symbolName;       // 符号名
@property (nonatomic, assign) NSInteger offset;         // 偏移量
```

## 🔍 与 Matrix 的区别

### 简化内容

1. **移除了复杂的错误处理**
2. **移除了游标迭代器模式**（直接使用数组）
3. **移除了多架构兼容代码**（只保留 ARM64）
4. **移除了内存安全保护**（简化为 try-catch）
5. **移除了崩溃上下文处理**

### 保留核心

1. ✅ ARM64 FP 链表遍历
2. ✅ Mach API 寄存器获取
3. ✅ dladdr 符号化
4. ✅ 线程挂起/恢复机制

## ⚠️ 注意事项

### 真机运行

- 需要配置开发者证书
- 建议使用 Debug 构建（符号化效果更好）

### Release 构建

- 符号可能被 strip，导致无法符号化
- 可以保留调试符号：Build Settings → Strip Debug Symbols During Copy → NO

### 性能考虑

- 堆栈采集会挂起线程，有一定开销
- 建议只在必要时使用（如检测到卡顿）
- 生产环境需要更完善的错误处理

## 📝 学习资源

### 相关文档

- `ARM64堆栈遍历寄存器结构详解.md` - ARM64 寄存器和栈帧详解
- `Matrix异步堆栈追溯技术实现.md` - 异步堆栈追踪
- `虚拟内存地址与符号化原理.md` - 符号化原理

### 关键 API

- `backtrace()` - POSIX 堆栈回溯
- `thread_suspend()` / `thread_resume()` - 线程控制
- `thread_get_state()` - 获取寄存器
- `dladdr()` - 地址符号化

## 🎓 进阶方向

### 可以添加的功能

1. **异步堆栈追溯**（参考 Matrix 的 fishhook 实现）
2. **离线符号化支持**（atos + dSYM）
3. **堆栈去重**（相同堆栈合并）
4. **热点分析**（统计高频函数）
5. **性能优化**（缓存符号查询结果）

### 完整实现参考

如需更完整的实现，请参考 Matrix 源码：
- `KSStackCursor_SelfThread.c`
- `KSStackCursor_MachineContext.c`
- `KSSymbolicator.c`

## 📄 License

MIT License

---

**🎯 这是一个教学演示项目，展示了堆栈回溯的核心原理！**
