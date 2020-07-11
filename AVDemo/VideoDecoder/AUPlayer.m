//
//  AUPlayer.m
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/21.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import "AUPlayer.h"
#import <AVFoundation/AVFoundation.h>

@interface AUPlayer ()

@property (nonatomic, assign) int sampleRate;
@property (nonatomic, assign) int channelCount;
@property (nonatomic, assign) int bitPerChannel;

@property (nonatomic, assign) AudioUnit audioUnit;

@property (nonatomic, strong) dispatch_queue_t playQueue;

@property (nonatomic, strong) AVDQueue *dataQueue;
@property (nonatomic, strong) NSMutableData *buffer;

@end

@implementation AUPlayer

- (instancetype)initWithSampleRate:(int)sampleRate channel:(int)channel bitPerChannel:(int)bitPerChannel queue:(AVDQueue *)queue {
    if (self = [super init]) {
        _sampleRate = sampleRate;
        _channelCount = channel;
        _bitPerChannel = bitPerChannel;
        _dataQueue = queue;
        _buffer = [NSMutableData data];
    }
    
    return self;
}

- (void)setupAudioSession {
    NSError *err;
    
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) {
        NSLog(@"AudioSession setCategory failed, err:%@", err);
        return;
    }
    
    [AVAudioSession.sharedInstance setActive:YES error:&err];
    
    if (err) {
        NSLog(@"AudioSession setActive failed, err:%@", err);
    }
}

- (void)setupAudioUnit {
    //初始化
    AudioComponentDescription outputDesc;
    outputDesc.componentType = kAudioUnitType_Output;
    outputDesc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    outputDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    outputDesc.componentFlags = 0;
    outputDesc.componentFlagsMask = 0;
    
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &outputDesc);
    OSStatus status = AudioComponentInstanceNew(outputComponent, &_audioUnit);
    
    CheckStatus(status, @"AudioUnit Init Error", YES);
    
    //设置输出格式
    int mFramesPerPacket = 1;
    int bytePerFrame = self.channelCount * self.bitPerChannel / 8;
    
    AudioStreamBasicDescription streamDesc;
    streamDesc.mFormatID = kAudioFormatLinearPCM;
    streamDesc.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;
    streamDesc.mSampleRate = self.sampleRate;
    streamDesc.mFramesPerPacket = mFramesPerPacket;
    streamDesc.mChannelsPerFrame = self.channelCount;
    streamDesc.mBitsPerChannel = self.bitPerChannel;
    streamDesc.mBytesPerFrame = bytePerFrame;
    streamDesc.mBytesPerPacket = bytePerFrame * mFramesPerPacket;
    
    int outputBus = 0;
    
    status = AudioUnitSetProperty(_audioUnit,
                                           kAudioUnitProperty_StreamFormat,
                                           kAudioUnitScope_Input,
                                           outputBus,
                                           &streamDesc,
                                           sizeof(streamDesc));
    
    CheckStatus(status, @"AudioUnit Set Output Format Error", YES);
    
    //设置回调
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = PlayCallback;
    playCallback.inputProcRefCon = (__bridge void *)self;
    AudioUnitSetProperty(_audioUnit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input,
                         outputBus,
                         &playCallback,
                         sizeof(playCallback));
    
    CheckStatus(status, @"AudioUnit SetProperty EnableIO failure", YES);
}

- (void)start {
    [self setupAudioSession];
    [self setupAudioUnit];
    
    AudioOutputUnitStart(_audioUnit);
}

- (void)stop {
    AudioOutputUnitStop(_audioUnit);
}

- (void)sendData:(void *)data dataLen:(int)dataLen {
//    [self.queue appendBytes:data length:(NSUInteger)dataLen];
//    NSLog(@"audio data+%d, remaining:%d",dataLen, self.data.length);
}

static OSStatus PlayCallback(void *inRefCon,
                             AudioUnitRenderActionFlags *ioActionFlags,
                             const AudioTimeStamp *inTimeStamp,
                             UInt32 inBusNumber,
                             UInt32 inNumberFrames,
                             AudioBufferList *ioData) {
    AudioBuffer audioBuffer = ioData->mBuffers[0];
    
    AUPlayer *player = (__bridge AUPlayer *)(inRefCon);
    NSMutableData *buffer = player.buffer;
    AVDQueue *dataQueue = player.dataQueue;
    
    BOOL playData = NO;
    if (buffer.length >= audioBuffer.mDataByteSize) {
        playData = YES;
    }
    else if (!dataQueue.isEmpty) {
        while (dataQueue.isEmpty || buffer.length < audioBuffer.mDataByteSize) {
            AVDQueueNode *node = [dataQueue dequeue];
            [buffer appendBytes:node.content length:node.len];
            
            NSLog(@"renderAudioData:%f", node.pts);
        }
        
        if (buffer.length > audioBuffer.mDataByteSize) {
            playData = YES;
        }
    }
    
    if (playData) {
        memcpy(audioBuffer.mData, buffer.bytes, audioBuffer.mDataByteSize);
        
        NSRange range = NSMakeRange(0, audioBuffer.mDataByteSize);
        [buffer replaceBytesInRange:range withBytes:NULL length:0];
    }
    else {
        memset(audioBuffer.mData, 0, audioBuffer.mDataByteSize);
        NSLog(@"No Audio Data");
    }
    
    return noErr;
}

static void CheckStatus(OSStatus status, NSString *message, BOOL fatal)
{
    if(status != noErr)
    {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        
        if(isprint(fourCC[0]) && isprint(fourCC[1]) && isprint(fourCC[2]) && isprint(fourCC[3]))
            NSLog(@"%@: %s", message, fourCC);
        else
            NSLog(@"%@: %d", message, (int)status);
        
        if(fatal)
            exit(-1);
    }
}

@end
