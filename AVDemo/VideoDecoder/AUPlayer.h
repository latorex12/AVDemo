//
//  AUPlayer.h
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/21.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AVDQueue.h"

NS_ASSUME_NONNULL_BEGIN

//最简单的AudioUnit Player 输入
@interface AUPlayer : NSObject
- (instancetype)initWithSampleRate:(int)sampleRate channel:(int)channel bitPerChannel:(int)bitPerChannel queue:(AVDQueue *)queue;
- (void)start;
- (void)stop;
- (void)sendData:(void *)data dataLen:(int)dataLen;
@end

NS_ASSUME_NONNULL_END
