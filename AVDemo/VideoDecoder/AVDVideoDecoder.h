//
//  AVDVideoDecoder.h
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/14.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AVDVideoDecoderDelegate <NSObject>
- (void)onDecodeError;
- (void)onDecodeVideoFrame:(CVPixelBufferRef)pixelBuffer timestamp:(NSTimeInterval)timestamp;
- (void)onDecodeEnd:(BOOL)manually;
@end

@interface AVDVideoDecoder : NSObject

@property (nonatomic, assign, readonly) NSTimeInterval currentTime;
@property (nonatomic, assign, readonly) NSTimeInterval totalDuration;

@property (nonatomic, weak) id delegate;

- (BOOL)startDecode:(NSString *)filePath;
- (void)stopDecode;
- (void)pauseDecode;
- (void)resumeDecode;

- (void)seekTo:(NSTimeInterval)time;

@end

NS_ASSUME_NONNULL_END
