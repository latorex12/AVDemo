//
//  ViewController.m
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/14.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import "ViewController.h"
#import "AVDVideoDecoder.h"
#import "AUPlayer.h"
#import "AVDQueue.h"

@interface ViewController () <AVDVideoDecoderDelegate, AVDQueueDelegate>
@property (weak, nonatomic) IBOutlet UIButton *startBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopBtn;
@property (weak, nonatomic) IBOutlet UIButton *pauseBtn;
@property (weak, nonatomic) IBOutlet UIButton *resumeBtn;
@property (weak, nonatomic) IBOutlet UILabel *currentTImeLbl;
@property (weak, nonatomic) IBOutlet UILabel *totalTimeLbl;
@property (weak, nonatomic) IBOutlet UISlider *processSlider;

@property (nonatomic, assign) BOOL isSlide;

@property (nonatomic, strong) AVDVideoDecoder *decoder;
@property (nonatomic, strong) AUPlayer *auPlayer;

@property (nonatomic, strong) AVDQueue *aQueue;
@property (nonatomic, strong) AVDQueue *vQueue;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.startBtn addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    [self.stopBtn addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    [self.pauseBtn addTarget:self action:@selector(pause) forControlEvents:UIControlEventTouchUpInside];
    [self.resumeBtn addTarget:self action:@selector(resume) forControlEvents:UIControlEventTouchUpInside];
    [self.processSlider addTarget:self action:@selector(startSlide) forControlEvents:UIControlEventTouchDown];
    [self.processSlider addTarget:self action:@selector(stopSlide) forControlEvents:UIControlEventTouchUpInside];
    [self.processSlider addTarget:self action:@selector(stopSlide) forControlEvents:UIControlEventTouchUpOutside];
    
    self.aQueue = [[AVDQueue alloc] init];
    self.aQueue.delegate = self;
    self.vQueue = [[AVDQueue alloc] init];

    self.decoder = [[AVDVideoDecoder alloc] init];
    self.decoder.delegate = self;
    
    self.auPlayer = [[AUPlayer alloc] initWithSampleRate:44100 channel:1 bitPerChannel:16 queue:self.aQueue];
}

- (void)start {
    NSString *filePath = [NSBundle.mainBundle pathForResource:@"test_video" ofType:@"mp4"];
    [self.decoder startDecode:filePath];
    
    self.totalTimeLbl.text = [NSString stringWithFormat:@"%.2f", self.decoder.totalDuration];
    self.processSlider.minimumValue = 0;
    self.processSlider.maximumValue = self.decoder.totalDuration;
    
    [self updateCurrentTime];
    
    [self.auPlayer start];
}

- (void)stop {
    [self.decoder stopDecode];
}

- (void)pause {
    [self.decoder pauseDecode];
}

- (void)resume {
    [self.decoder resumeDecode];
}
     
- (void)startSlide {
    [self pause];
}

- (void)stopSlide {
    [self resume];
    NSTimeInterval timestamp = self.processSlider.value;
    [self.decoder seekTo:timestamp];
}

- (void)updateCurrentTime {
    self.currentTImeLbl.text = [NSString stringWithFormat:@"%.2f", self.decoder.currentTime];
    self.processSlider.value = self.decoder.currentTime;
}

- (void)renderVideoDataIfNeeded:(NSTimeInterval)audioPts {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVDQueueNode *node = [self.vQueue firstNode];
        if (!node || node.pts > audioPts) {
            return;
        }
        
        NSLog(@"renderVideoDataIfNeeded:%f", node.pts);
        
        [self updateCurrentTime];
        
        //写入pixelBuf
        CVPixelBufferRef pixel;
        CVPixelBufferCreateWithBytes(nil, self.decoder.videoW, self.decoder.videoH, kCVPixelFormatType_24RGB, node.content, self.decoder.lineSize, nil, nil, nil, &pixel);
        [self showPixel:pixel];
        
        [self.vQueue dequeue];
    });
}

- (void)showPixel:(CVPixelBufferRef)pixel {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixel];
    CIContext *temporaryContext = [CIContext contextWithOptions:nil];
    CGImageRef videoImage = [temporaryContext createCGImage:ciImage fromRect:CGRectMake(0, 0, CVPixelBufferGetWidth(pixel), CVPixelBufferGetHeight(pixel))];

    self.view.layer.contents = CFBridgingRelease(videoImage);
    
    static int idx = 0;
    NSLog(@"Frame:%d", idx++);
}

#pragma mark - AVDVideoDecoderDelegate

- (void)onDecodeError {
    NSLog(@"onDecodeError");
}

- (void)onDecodeVideoFrame:(void *)data len:(int)len timestamp:(NSTimeInterval)timestamp {
    AVDQueueNode *node = [[AVDQueueNode alloc] init];
    node.pts = timestamp;
    node.content = data;
    node.len = len;
    
    [self.vQueue enqueue:node];
}

- (void)onDecodeAudioFrame:(void *)data len:(int)len timestamp:(NSTimeInterval)timestamp {
    AVDQueueNode *node = [[AVDQueueNode alloc] init];
    node.pts = timestamp;
    node.content = data;
    node.len = len;
    
    [self.aQueue enqueue:node];
    
//    dispatch_async(dispatch_get_main_queue(), ^{
//        AVDQueueNode *node = [self.aQueue dequeue];
//        if (!node) {
//            return;
//        }
//
//        [self.auPlayer sendData:node.content dataLen:node.len];
        
//        free(node.content);
//    });
}

- (void)onDecodeEnd:(BOOL)manually {
    NSLog(@"onDecodeEnd,manaually:%@", manually ? @"Y":@"N");
    self.view.layer.contents = nil;
    [self.auPlayer stop];
}

#pragma mark - AVDQueueDelegate

- (void)bufferStart {
    [self.decoder resumeDecode];
}

- (void)bufferEnd {
    [self.decoder pauseDecode];
}

- (void)outBufferNode:(AVDQueueNode *)node {
    [self renderVideoDataIfNeeded:node.pts];//音频驱动视频
}

@end
