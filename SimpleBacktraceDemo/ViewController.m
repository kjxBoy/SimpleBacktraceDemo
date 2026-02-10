//
//  ViewController.m
//  SimpleBacktraceDemo
//
//  演示简化版堆栈获取工具
//

#import "ViewController.h"
#import "SimpleBacktrace.h"

@interface ViewController ()

@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIButton *btn1;
@property (nonatomic, strong) UIButton *btn2;
@property (nonatomic, strong) UIButton *btn3;
@property (nonatomic, strong) UIButton *btn4;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"堆栈回溯演示";
    
    [self setupUI];
}

- (void)setupUI {
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.view.bounds.size.width - 40, 30)];
    titleLabel.text = @"📚 简化版堆栈回溯工具";
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:titleLabel];
    
    // 按钮1：获取当前线程堆栈
    self.btn1 = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btn1.frame = CGRectMake(20, 150, self.view.bounds.size.width - 40, 50);
    [self.btn1 setTitle:@"1️⃣ 获取当前线程堆栈" forState:UIControlStateNormal];
    self.btn1.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
    [self.btn1 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn1.layer.cornerRadius = 8;
    self.btn1.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.btn1 addTarget:self action:@selector(captureCurrentThreadStack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn1];
    
    // 按钮2：获取主线程堆栈（模拟卡顿）
    self.btn2 = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btn2.frame = CGRectMake(20, 210, self.view.bounds.size.width - 40, 50);
    [self.btn2 setTitle:@"2️⃣ 模拟卡顿，获取主线程堆栈" forState:UIControlStateNormal];
    self.btn2.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.2 alpha:1.0];
    [self.btn2 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn2.layer.cornerRadius = 8;
    self.btn2.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.btn2 addTarget:self action:@selector(simulateLagAndCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn2];
    
    // 按钮3：测试多层调用
    self.btn3 = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btn3.frame = CGRectMake(20, 270, self.view.bounds.size.width - 40, 50);
    [self.btn3 setTitle:@"3️⃣ 测试多层函数调用" forState:UIControlStateNormal];
    self.btn3.backgroundColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0];
    [self.btn3 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn3.layer.cornerRadius = 8;
    self.btn3.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.btn3 addTarget:self action:@selector(testNestedCalls) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn3];
    
    // 按钮4：清空
    self.btn4 = [UIButton buttonWithType:UIButtonTypeSystem];
    self.btn4.frame = CGRectMake(20, 330, self.view.bounds.size.width - 40, 50);
    [self.btn4 setTitle:@"🗑️ 清空输出" forState:UIControlStateNormal];
    self.btn4.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
    [self.btn4 setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.btn4.layer.cornerRadius = 8;
    self.btn4.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.btn4 addTarget:self action:@selector(clearOutput) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.btn4];
    
    // 输出文本框
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(20, 400, self.view.bounds.size.width - 40, self.view.bounds.size.height - 430)];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.textView.layer.cornerRadius = 8;
    self.textView.editable = NO;
    self.textView.text = @"👆 点击上方按钮测试堆栈获取\n";
    [self.view addSubview:self.textView];
}

#pragma mark - Test Cases

/**
 * 测试1：获取当前线程的堆栈
 */
- (void)captureCurrentThreadStack {
    [self appendOutput:@"\n=== 测试1：当前线程堆栈 ===\n"];
    
    // 获取当前线程堆栈（跳过 2 帧：backtrace 和本方法）
    NSArray<BacktraceFrame *> *frames = [SimpleBacktrace captureCurrentThreadBacktrace:50 skipFrames:2];
    
    NSString *result = [SimpleBacktrace formatBacktrace:frames];
    [self appendOutput:result];
    [self appendOutput:@"\n✅ 成功获取到当前线程的完整调用栈！\n"];
}

/**
 * 测试2：模拟卡顿，从子线程获取主线程堆栈
 */
- (void)simulateLagAndCapture {
    [self appendOutput:@"\n=== 测试2：主线程卡顿检测 ===\n"];
    [self appendOutput:@"🔄 模拟主线程卡顿 2 秒...\n"];
    
    // 在子线程中监控主线程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 等待一小段时间，让主线程进入卡顿状态
        [NSThread sleepForTimeInterval:0.1];
        
        // 获取主线程堆栈
        NSArray<BacktraceFrame *> *frames = [SimpleBacktrace captureMainThreadBacktrace:50];
        NSString *result = [SimpleBacktrace formatBacktrace:frames];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendOutput:@"\n📸 从子线程捕获到的主线程堆栈：\n"];
            [self appendOutput:result];
            [self appendOutput:@"\n✅ 成功定位到卡顿位置！\n"];
        });
    });
    
    // 模拟主线程卡顿（睡眠 2 秒）
    [NSThread sleepForTimeInterval:2.0];
}

/**
 * 测试3：多层函数调用
 */
- (void)testNestedCalls {
    [self appendOutput:@"\n=== 测试3：多层函数调用 ===\n"];
    [self level1];
}

- (void)level1 {
    [self level2];
}

- (void)level2 {
    [self level3];
}

- (void)level3 {
    [self level4];
}

- (void)level4 {
    // 在第4层捕获堆栈
    NSArray<BacktraceFrame *> *frames = [SimpleBacktrace captureCurrentThreadBacktrace:50 skipFrames:2];
    NSString *result = [SimpleBacktrace formatBacktrace:frames];
    
    [self appendOutput:@"📸 在第4层函数中捕获的堆栈：\n"];
    [self appendOutput:result];
    [self appendOutput:@"\n✅ 可以看到完整的调用链：level4 → level3 → level2 → level1\n"];
}

/**
 * 清空输出
 */
- (void)clearOutput {
    self.textView.text = @"👆 点击上方按钮测试堆栈获取\n";
}

/**
 * 追加输出
 */
- (void)appendOutput:(NSString *)text {
    self.textView.text = [self.textView.text stringByAppendingString:text];
    
    // 滚动到底部
    NSRange bottom = NSMakeRange(self.textView.text.length - 1, 1);
    [self.textView scrollRangeToVisible:bottom];
}

@end
