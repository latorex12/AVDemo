//
//  ViewController.m
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/14.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import "ViewController.h"
#import "AVDVideoDecoder.h"

@interface ViewController () <AVDVideoDecoderDelegate>
@property (weak, nonatomic) IBOutlet UIButton *startBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopBtn;
@property (weak, nonatomic) IBOutlet UIButton *pauseBtn;
@property (weak, nonatomic) IBOutlet UIButton *resumeBtn;

@property (nonatomic, strong) AVDVideoDecoder *decoder;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self.startBtn addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    [self.stopBtn addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    [self.pauseBtn addTarget:self action:@selector(pause) forControlEvents:UIControlEventTouchUpInside];
    [self.resumeBtn addTarget:self action:@selector(resume) forControlEvents:UIControlEventTouchUpInside];
    
    
    self.decoder = [[AVDVideoDecoder alloc] init];
    self.decoder.delegate = self;
}

- (void)start {
    NSString *filePath = [NSBundle.mainBundle pathForResource:@"test_video" ofType:@"mp4"];
    [self.decoder startDecode:filePath];
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

- (void)onDecodeVideoFrame:(nonnull CVPixelBufferRef)pixelBuffer {
    [self showPixel:pixelBuffer];
}

- (void)onDecodeEnd:(BOOL)manually {
    NSLog(@"onDecodeEnd,manaually:%@", manually ? @"Y":@"N");
    self.view.layer.contents = nil;
}

@end
