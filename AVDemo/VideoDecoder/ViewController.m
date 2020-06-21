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
@property (weak, nonatomic) IBOutlet UILabel *currentTImeLbl;
@property (weak, nonatomic) IBOutlet UILabel *totalTimeLbl;
@property (weak, nonatomic) IBOutlet UISlider *processSlider;

@property (nonatomic, assign) BOOL isSlide;

@property (nonatomic, strong) AVDVideoDecoder *decoder;
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
    
    self.decoder = [[AVDVideoDecoder alloc] init];
    self.decoder.delegate = self;
}

- (void)start {
    NSString *filePath = [NSBundle.mainBundle pathForResource:@"test_video" ofType:@"mp4"];
    if ([self.decoder startDecode:filePath]) {
        self.totalTimeLbl.text = [NSString stringWithFormat:@"%.2f", self.decoder.totalDuration];
        self.processSlider.minimumValue = 0;
        self.processSlider.maximumValue = self.decoder.totalDuration;
        
        [self updateCurrentTime];
    }
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

- (void)onDecodeVideoFrame:(nonnull CVPixelBufferRef)pixelBuffer timestamp:(NSTimeInterval)timestamp {
    [self updateCurrentTime];
    [self showPixel:pixelBuffer];
}

- (void)onDecodeEnd:(BOOL)manually {
    NSLog(@"onDecodeEnd,manaually:%@", manually ? @"Y":@"N");
    self.view.layer.contents = nil;
}

@end
