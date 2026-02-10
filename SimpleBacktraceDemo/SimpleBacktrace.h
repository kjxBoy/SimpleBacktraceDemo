//
//  SimpleBacktrace.h
//  简化版堆栈回溯工具
//
//  功能：获取线程的调用栈
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 堆栈帧信息
 */
@interface BacktraceFrame : NSObject

/// 指令地址（虚拟内存地址）
@property (nonatomic, assign) uintptr_t address;

/// 镜像名称（如 "MyApp", "UIKitCore"）
@property (nonatomic, copy, nullable) NSString *imageName;

/// 符号名称（函数名）
@property (nonatomic, copy, nullable) NSString *symbolName;

/// 偏移量（在函数内的字节偏移）
@property (nonatomic, assign) NSInteger offset;

/// 格式化输出
- (NSString *)description;

@end

/**
 * 简化版堆栈回溯工具
 */
@interface SimpleBacktrace : NSObject

/**
 * 获取当前线程的堆栈（自己调用）
 * 
 * @param maxDepth 最大深度（通常 50-100）
 * @param skipFrames 跳过的帧数（跳过本函数调用）
 * @return 堆栈帧数组
 */
+ (NSArray<BacktraceFrame *> *)captureCurrentThreadBacktrace:(NSInteger)maxDepth
                                                   skipFrames:(NSInteger)skipFrames;

/**
 * 获取指定线程的堆栈（主线程卡顿检测用）
 * 
 * @param thread Mach 线程 ID
 * @param maxDepth 最大深度
 * @return 堆栈帧数组
 */
+ (NSArray<BacktraceFrame *> *)captureBacktraceOfThread:(thread_t)thread
                                                maxDepth:(NSInteger)maxDepth;

/**
 * 获取主线程的堆栈
 * 
 * @param maxDepth 最大深度
 * @return 堆栈帧数组
 */
+ (NSArray<BacktraceFrame *> *)captureMainThreadBacktrace:(NSInteger)maxDepth;

/**
 * 格式化输出堆栈
 * 
 * @param frames 堆栈帧数组
 * @return 格式化的字符串
 */
+ (NSString *)formatBacktrace:(NSArray<BacktraceFrame *> *)frames;

@end

NS_ASSUME_NONNULL_END
