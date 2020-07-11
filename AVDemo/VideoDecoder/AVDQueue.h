//
//  AVDQueue.h
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/28.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVDQueueNode : NSObject
@property (nonatomic, assign) NSTimeInterval pts;
@property (nonatomic, assign) void *content;
@property (nonatomic, assign) int len;
@end

@protocol AVDQueueDelegate <NSObject>
- (void)bufferStart;
- (void)bufferEnd;
- (void)outBufferNode:(AVDQueueNode *)node;
@end

//暂时使用可变数组实现
@interface AVDQueue : NSObject
@property (nonatomic, weak) id<AVDQueueDelegate> delegate;

- (void)enqueue:(AVDQueueNode *)node;
- (nullable AVDQueueNode *)dequeue;
- (nullable AVDQueueNode *)firstNode;
- (BOOL)isEmpty;
- (NSUInteger)nodeCount;
@end

NS_ASSUME_NONNULL_END
