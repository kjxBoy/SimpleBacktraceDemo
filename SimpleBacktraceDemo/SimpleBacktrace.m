//
//  SimpleBacktrace.m
//  简化版堆栈回溯工具实现
//

// 启用 Darwin 平台的非标准扩展函数
// 必须在所有头文件之前定义
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif

#ifndef __DARWIN_C_LEVEL
#define __DARWIN_C_LEVEL 900000L
#endif

#import "SimpleBacktrace.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <pthread.h>
#import <execinfo.h>

// ============================================================================
// 配置选项：内存读取方式
// ============================================================================

/**
 * 内存读取方式选择开关
 * 
 * 使用方式：
 * 1. 在项目的 Build Settings → Preprocessor Macros 中定义
 * 2. 或在此文件开头（导入之前）定义
 * 
 * 选项说明：
 * 
 * USE_VM_READ_OVERWRITE = 1（默认，推荐）
 * - 使用 vm_read_overwrite（内核级安全读取）
 * - 优点：安全可靠，无效地址不会崩溃
 * - 缺点：性能稍慢（约 2-3 倍）
 * - 适用场景：生产环境、跨线程读取、不确定栈是否有效
 * 
 * USE_VM_READ_OVERWRITE = 0
 * - 使用 memcpy + @try/@catch（直接读取）
 * - 优点：性能快
 * - 缺点：无效地址可能崩溃（部分信号无法捕获）
 * - 适用场景：开发调试、性能敏感场景、确定栈有效
 * 
 * 示例：
 * // 在 Build Settings → Preprocessor Macros 中添加：
 * USE_VM_READ_OVERWRITE=1  （生产环境）
 * USE_VM_READ_OVERWRITE=0  （性能测试）
 */
#ifndef USE_VM_READ_OVERWRITE
    #if DEBUG
        // Debug 模式：优先性能，便于调试
        #define USE_VM_READ_OVERWRITE 0
    #else
        // Release 模式：优先安全，防止崩溃
        #define USE_VM_READ_OVERWRITE 1
    #endif
#endif

// ============================================================================
// Darwin 平台非标准扩展函数声明（兜底方案）
// ============================================================================
#if !defined(pthread_main_thread_np)
extern pthread_t pthread_main_thread_np(void);
#endif

#if !defined(pthread_mach_thread_np)
extern mach_port_t pthread_mach_thread_np(pthread_t);
#endif

// ============================================================================
// 私有结构体：ARM64 栈帧
// ============================================================================

/**
 * ARM64 栈帧结构
 * 
 * ARM64 调用约定：
 * - 函数入口时执行：stp x29, x30, [sp, #-16]!
 * - 将 FP (x29) 和 LR (x30) 压入栈
 * 
 * 栈帧布局（16 字节）：
 * ┌────────────────┐
 * │ LR (x30)       │  ← FP + 8 (返回地址)
 * ├────────────────┤
 * │ previous FP    │  ← FP + 0 (上一个帧指针)
 * └────────────────┘  ← 当前 FP (x29)
 */
typedef struct {
    struct FrameEntry *previous;    // 上一个栈帧的 FP
    uintptr_t returnAddress;        // 返回地址（LR）
} FrameEntry;

// ============================================================================
// BacktraceFrame 实现
// ============================================================================

@implementation BacktraceFrame

- (NSString *)description {
    NSMutableString *result = [NSMutableString string];
    
    // 格式：0x地址  镜像名  符号名 + 偏移
    [result appendFormat:@"0x%016lx", (unsigned long)self.address];
    
    if (self.imageName) {
        [result appendFormat:@"  %@", self.imageName];
    } else {
        [result appendString:@"  ???"];
    }
    
    if (self.symbolName) {
        [result appendFormat:@"  %@ + %ld", self.symbolName, (long)self.offset];
    } else {
        [result appendString:@"  ???"];
    }
    
    return result;
}

@end

// ============================================================================
// SimpleBacktrace 实现
// ============================================================================

@implementation SimpleBacktrace

#pragma mark - Initialization

/**
 * 类加载时输出配置信息
 */
+ (void)load {
#if USE_VM_READ_OVERWRITE
    NSLog(@"🛡️ SimpleBacktrace: 使用 vm_read_overwrite（安全模式）");
#else
    NSLog(@"⚡️ SimpleBacktrace: 使用 memcpy（性能模式）");
#endif
}

#pragma mark - Public Methods

/**
 * 获取当前线程的堆栈（使用 backtrace）
 */
+ (NSArray<BacktraceFrame *> *)captureCurrentThreadBacktrace:(NSInteger)maxDepth
                                                   skipFrames:(NSInteger)skipFrames {
    if (maxDepth <= 0) {
        return @[];
    }
    
    // 使用 POSIX backtrace() 获取当前线程堆栈
    void *addresses[maxDepth];
    int count = backtrace(addresses, (int)maxDepth);
    
    NSMutableArray<BacktraceFrame *> *frames = [NSMutableArray array];
    
    // 跳过指定的帧数（通常跳过 backtrace 和本函数）
    for (int i = (int)skipFrames; i < count; i++) {
        BacktraceFrame *frame = [self symbolizeAddress:(uintptr_t)addresses[i]];
        [frames addObject:frame];
    }
    
    return frames;
}

/**
 * 获取指定线程的堆栈（核心实现）
 */
+ (NSArray<BacktraceFrame *> *)captureBacktraceOfThread:(thread_t)thread
                                                maxDepth:(NSInteger)maxDepth {
    if (maxDepth <= 0) {
        return @[];
    }
    
    // ========================================================================
    // 步骤1：挂起目标线程
    // ========================================================================
    kern_return_t kr = thread_suspend(thread);
    if (kr != KERN_SUCCESS) {
        NSLog(@"❌ 线程挂起失败: %s", mach_error_string(kr));
        return @[];
    }
    
    // ========================================================================
    // 步骤2：获取线程的寄存器状态
    // ========================================================================
    uintptr_t addresses[maxDepth];
    int count = [self getThreadBacktrace:thread buffer:addresses maxSize:(int)maxDepth];
    
    // ========================================================================
    // 步骤3：恢复线程
    // ========================================================================
    thread_resume(thread);
    
    // ========================================================================
    // 步骤4：符号化地址
    // ========================================================================
    NSMutableArray<BacktraceFrame *> *frames = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        BacktraceFrame *frame = [self symbolizeAddress:addresses[i]];
        [frames addObject:frame];
    }
    
    return frames;
}

/**
 * 获取主线程的堆栈
 */
+ (NSArray<BacktraceFrame *> *)captureMainThreadBacktrace:(NSInteger)maxDepth {
    // 获取主线程的 Mach 线程 ID
    thread_t mainThread = pthread_mach_thread_np(pthread_main_thread_np());
    return [self captureBacktraceOfThread:mainThread maxDepth:maxDepth];
}

/**
 * 格式化输出堆栈
 */
+ (NSString *)formatBacktrace:(NSArray<BacktraceFrame *> *)frames {
    NSMutableString *result = [NSMutableString string];
    
    [result appendString:@"📚 堆栈信息：\n"];
    [result appendString:@"═══════════════════════════════════════\n"];
    
    for (NSInteger i = 0; i < frames.count; i++) {
        [result appendFormat:@"%2ld  %@\n", (long)i, frames[i].description];
    }
    
    return result;
}

#pragma mark - Private Methods

/**
 * 获取线程堆栈的核心实现（ARM64）
 * 
 * 原理：
 * 1. 通过 thread_get_state 获取寄存器（PC、FP、SP、LR）
 * 2. 第一帧返回 PC（当前指令）
 * 3. 后续帧通过 FP 链表遍历
 */
+ (int)getThreadBacktrace:(thread_t)thread
                   buffer:(uintptr_t *)buffer
                  maxSize:(int)maxSize {
    if (maxSize == 0) {
        return 0;
    }
    
#if defined(__arm64__)
    // ========================================================================
    // ARM64 实现
    // ========================================================================
    
    // 获取线程状态
    _STRUCT_ARM_THREAD_STATE64 threadState;
    mach_msg_type_number_t stateCount = ARM_THREAD_STATE64_COUNT;
    
    kern_return_t kr = thread_get_state(thread,
                                       ARM_THREAD_STATE64,
                                       (thread_state_t)&threadState,
                                       &stateCount);
    
    if (kr != KERN_SUCCESS) {
        NSLog(@"❌ 获取线程状态失败: %s", mach_error_string(kr));
        return 0;
    }
    
    // ========================================================================
    // 第一帧：PC（当前执行位置）
    // ========================================================================
    int index = 0;
    buffer[index++] = (uintptr_t)threadState.__pc;
    
    
    //+ (BacktraceFrame *)symbolizeAddress:(uintptr_t)address
    
    
    
    BacktraceFrame *frame = [SimpleBacktrace symbolizeAddress:(uintptr_t)threadState.__pc];
    
    
    NSString *result = [SimpleBacktrace formatBacktrace:@[frame]];

    
    NSLog(@"pc - result %@", result);
    
    // ========================================================================
    // 后续帧：通过 FP 链表遍历
    // ========================================================================
    uintptr_t currentFP = (uintptr_t)threadState.__fp;
    
    while (index < maxSize && currentFP != 0) {
        // 读取栈帧（16 字节）
        FrameEntry frame;
        
        // 安全读取内存
        if (![self safelyCopyMemory:(void *)currentFP
                                  to:&frame
                                size:sizeof(frame)]) {
            // 内存读取失败，停止遍历
            break;
        }
        
        // 验证数据有效性
        if ((uintptr_t)frame.previous == 0 || frame.returnAddress == 0) {
            // 到达栈底
            break;
        }
        
        
        BacktraceFrame *returnAddressFrame = [SimpleBacktrace symbolizeAddress:frame.returnAddress];
        
        
        NSString *result = [SimpleBacktrace formatBacktrace:@[returnAddressFrame]];

        
        NSLog(@"pc - returnAddressFrame %@", result);
        
        // 保存返回地址
        buffer[index++] = frame.returnAddress;
        
        // 移动到上一个栈帧
        currentFP = (uintptr_t)frame.previous;
    }
    
    return index;
    
#else
    // ========================================================================
    // 其他架构：使用 backtrace（简化实现）
    // ========================================================================
    void *addresses[maxSize];
    int count = backtrace(addresses, maxSize);
    for (int i = 0; i < count; i++) {
        buffer[i] = (uintptr_t)addresses[i];
    }
    return count;
#endif
}

/**
 * 安全地从内存复制数据（使用 vm_read_overwrite）
 * 
 * 为什么需要安全复制？
 * - FP 可能指向无效内存（栈已被破坏、野指针等）
 * - 直接访问可能导致 SIGSEGV 崩溃
 * - 跨线程读取内存需要特殊处理
 * 
 * 两种实现方式对比：
 * 
 * 方式 1：vm_read_overwrite（推荐）
 * - 通过 Mach 内核 API 读取
 * - 内核会验证地址有效性
 * - 读取失败返回错误码，不会崩溃
 * - 适用于跨线程读取
 * - 性能开销稍大（需要陷入内核）
 * 
 * 方式 2：memcpy + @try/@catch（简化版）
 * - 直接内存访问
 * - 依赖异常处理机制
 * - 性能开销小
 * - 无法捕获所有类型的内存错误（如 SIGBUS）
 */
+ (BOOL)safelyCopyMemory:(const void *)source
                      to:(void *)destination
                    size:(size_t)size {
#if USE_VM_READ_OVERWRITE
    // ========================================================================
    // 方式 1：使用 vm_read_overwrite（安全优先）
    // ========================================================================
    
    // 获取当前任务（进程）
    mach_port_t task = mach_task_self();
    
    // 准备输出参数
    vm_size_t outSize = size;
    
    // 调用 vm_read_overwrite
    // - 从当前任务的 source 地址读取 size 字节
    // - 写入到 destination 地址
    // - 如果地址无效，返回 KERN_INVALID_ADDRESS
    kern_return_t kr = vm_read_overwrite(
        task,                           // 目标任务
        (vm_address_t)source,          // 源地址
        (vm_size_t)size,               // 读取大小
        (vm_address_t)destination,     // 目标地址
        &outSize                        // 实际读取的大小
    );
    
    if (kr == KERN_SUCCESS && outSize == size) {
        return YES;
    }
    
    // 降级方案：如果 vm_read_overwrite 失败，尝试直接复制
    @try {
        memcpy(destination, source, size);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"❌ 内存复制失败: source=%p, size=%zu, vm_error=%s", 
              source, size, mach_error_string(kr));
        return NO;
    }
    
#else
    // ========================================================================
    // 方式 2：使用 memcpy + 异常保护（性能优先）
    // ========================================================================
    
    @try {
        memcpy(destination, source, size);
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"❌ 内存复制失败: source=%p, size=%zu, exception=%@", 
              source, size, exception);
        return NO;
    }
#endif
}

/**
 * 安全地从内存复制数据（简化版本）
 * 
 * 注意：
 * - 本方法用于读取当前任务的内存
 * - 如果需要读取其他任务的内存，需要传入 task 参数
 * - vm_read_overwrite 在读取当前进程内存时，几乎总是成功的
 * - 但在某些极端情况下（如地址被 mprotect 保护），仍可能失败
 * 
 * vm_read_overwrite vs vm_read 的区别：
 * - vm_read：分配新内存，返回数据指针（需要手动释放）
 * - vm_read_overwrite：写入到指定缓冲区（无需释放，性能更好）
 * 
 * 使用场景：
 * - 遍历栈帧时读取 FP 和 LR
 * - 读取可能无效的内存地址
 * - 跨线程读取栈数据
 */
+ (BOOL)safelyCopyMemoryFromTask:(mach_port_t)task
                          source:(const void *)source
                              to:(void *)destination
                            size:(size_t)size {
    vm_size_t outSize = size;
    
    kern_return_t kr = vm_read_overwrite(
        task,
        (vm_address_t)source,
        (vm_size_t)size,
        (vm_address_t)destination,
        &outSize
    );
    
    return (kr == KERN_SUCCESS && outSize == size);
}

/**
 * 符号化地址（使用 dladdr）
 * 
 * dladdr 功能：
 * - 查询地址所属的动态库
 * - 查找最接近的符号
 * - 返回镜像名、符号名等信息
 */
+ (BacktraceFrame *)symbolizeAddress:(uintptr_t)address {
    BacktraceFrame *frame = [[BacktraceFrame alloc] init];
    frame.address = address;
    
    // 使用 dladdr 进行符号化
    Dl_info info;
    if (dladdr((const void *)address, &info)) {
        // 镜像名称（去除路径，只保留文件名）
        if (info.dli_fname) {
            NSString *fullPath = [NSString stringWithUTF8String:info.dli_fname];
            frame.imageName = [fullPath lastPathComponent];
        }
        
        // 符号名称
        if (info.dli_sname) {
            frame.symbolName = [NSString stringWithUTF8String:info.dli_sname];
            
            // 计算偏移量
            uintptr_t symbolAddr = (uintptr_t)info.dli_saddr;
            frame.offset = (NSInteger)(address - symbolAddr);
        } else {
            // 无符号，计算相对镜像基址的偏移
            uintptr_t imageBase = (uintptr_t)info.dli_fbase;
            frame.offset = (NSInteger)(address - imageBase);
        }
    }
    
    return frame;
}

@end
