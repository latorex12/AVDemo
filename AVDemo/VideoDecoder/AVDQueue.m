//
//  AVDQueue.m
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/28.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import "AVDQueue.h"
@interface AVDQueueNode()
@property (nonatomic, assign) BOOL isEnqueue;
@end
@implementation AVDQueueNode

- (void)dealloc {
    if (_content != NULL) {
        free(_content);
    }
}

@end

@interface AVDQueue ()
@property (nonatomic, strong) NSMutableArray *nodes;
@end

@implementation AVDQueue

- (instancetype)init {
    if (self = [super init]) {
        _nodes = [NSMutableArray array];
    }
    return self;
}

- (void)enqueue:(AVDQueueNode *)node {
    NSAssert(!node.isEnqueue, @"Node Is Already Enqueue.");
    
    if (![node isKindOfClass:AVDQueueNode.class]) {
        NSAssert(NO, @"Enqueue Invalid Node Type.");
    }
    
    node.isEnqueue = YES;
    [self.nodes addObject:node];
}

- (AVDQueueNode *)dequeue {
    AVDQueueNode *node = self.nodes.firstObject;
    
    if (node) {
        node.isEnqueue = NO;
        [self.nodes removeObjectAtIndex:0];
        
        [self.delegate outBufferNode:node];
    }
    
    if (self.nodeCount > 64) {
        [self.delegate bufferEnd];
    }
    else if (self.nodeCount < 32) {
        [self.delegate bufferStart];
    }
    
    return node;
}

- (AVDQueueNode *)firstNode {
    return self.nodes.firstObject;
}

- (BOOL)isEmpty {
    return self.nodeCount == 0;
}

- (NSUInteger)nodeCount {
    return self.nodes.count;
}

@end
