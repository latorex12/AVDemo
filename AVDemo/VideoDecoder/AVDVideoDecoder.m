//
//  AVDVideoDecoder.m
//  VideoDecoder
//
//  Created by SkyRim on 2020/6/14.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#import "AVDVideoDecoder.h"
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>

@interface AVDVideoDecoder (){
    AVFormatContext *pFormatCtx;
    int videoIndex;
    AVCodecContext *pCodecCtx;
    AVCodec *pCodec;
    AVStream *vStream;
    AVFrame *pFrame, *pFrameRGB24;
    struct SwsContext *sws_ctx;
    unsigned char *out_buffer;
    AVPacket *packet;
}

@property (nonatomic, strong) dispatch_queue_t decodeQueue;
//@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) unsigned int countRemaining;

@property (nonatomic, strong) NSTimer *timer;

@end

@implementation AVDVideoDecoder

- (void)dealloc {
    [self stopDecode];
}

- (instancetype)init {
    if (self = [super init]) {
        //注册
        av_register_all();
        
        _decodeQueue = dispatch_queue_create("avd_decode", NULL);
//        _semaphore = dispatch_semaphore_create(1);
    }
    return self;
}

- (BOOL)startDecode:(NSString *)filePath {
    if (self.filePath) {
        printf("⚠️当前正在解码，无法重复解码");
        return NO;
    }
    
    self.filePath = filePath;
    if (![self prepare]) {
        [self free];
        [self.delegate onDecodeError];
        return NO;
    }

    [self setupDecodeTimer];
    
    return YES;
}

- (BOOL)prepare {
    //打开文件准备读取头信息
    int res = avformat_open_input(&pFormatCtx, self.filePath.UTF8String, NULL, NULL);
    if (res < 0) {
        printf("⚠️无法打开文件:%s, err:%d", self.filePath.UTF8String, res);
        return NO;
    }
    
    //读取
    res = avformat_find_stream_info(pFormatCtx, NULL);
    if (res < 0) {
        printf("⚠️查找音视频流信息失败, err:%d", res);
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    for (int i = 0; i<pFormatCtx->nb_streams; i++) {
        vStream = pFormatCtx->streams[i];
        if (vStream->codec->codec_type == AVMEDIA_TYPE_VIDEO && pCodec == NULL) {
            videoIndex = i;
            pCodecCtx = vStream->codec;
            break;
        }
    }
    
    if (pCodecCtx == NULL) {
        printf("⚠️没有找到视频流");
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    ///STEP4.获取对应解码器
    pCodec = avcodec_find_decoder(pCodecCtx->codec_id);
    res = avcodec_open2(pCodecCtx, pCodec, NULL);
    if (res != 0) {
        printf("⚠️初始化视频解码环境失败, err:%d", res);
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    ///STEP5.配置转换器
    sws_ctx = sws_getContext(pCodecCtx->width, pCodecCtx->height, pCodecCtx->pix_fmt,
        pCodecCtx->width, pCodecCtx->height, AV_PIX_FMT_RGB24, SWS_BILINEAR, NULL, NULL, NULL);
    
    ///STEP6.配置packet/frame
    packet = av_packet_alloc();

    pFrame = av_frame_alloc();
    pFrameRGB24 = av_frame_alloc();
    
    int numBytes = avpicture_get_size(AV_PIX_FMT_RGB24, pCodecCtx->width, pCodecCtx->height);
    out_buffer = (uint8_t*)av_malloc(numBytes * sizeof(uint8_t));
    
    avpicture_fill((AVPicture*)pFrameRGB24, out_buffer, AV_PIX_FMT_RGB24, pCodecCtx->width, pCodecCtx->height);
    
    return YES;
}

- (void)decodeFrame {
    @synchronized (self) {
        self.countRemaining = 1;
        
        dispatch_async(self.decodeQueue, ^{
            [self readBuffer];
        });
    }
}

- (void)readBuffer {
    while (av_read_frame(pFormatCtx, packet) >= 0) {
        if (self.countRemaining == 0 || !self.filePath) {
            NSLog(@"read frame stop");
            return;
        }
        
        NSLog(@"read frame");
        [self decode];
    }
    
    [self teardownDecodeTimer];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate onDecodeEnd:NO];
    });
}

- (void)decode {
    if (packet->stream_index == videoIndex) {
        int frameFinished = 0;
        //解码
        int r = avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, packet);
        packet->size -= r;
        packet->data += r;
        
        if (frameFinished) {
            sws_scale(sws_ctx, (uint8_t const * const *)pFrame->data, pFrame->linesize, 0, pCodecCtx->height, pFrameRGB24->data, pFrameRGB24->linesize);
            
            //写入pixelBuf
            CVPixelBufferRef pixel;
            
            //直接使用420p
            //                size_t planeWidth[3] = {pFrame->width, pFrame->width/2, pFrame->width/2};
            //                size_t planeHeight[3] = {pFrame->height, pFrame->height/2, pFrame->height/2};
            //                res = CVPixelBufferCreateWithPlanarBytes(nil, pCodecCtx->width, pCodecCtx->height, kCVPixelFormatType_420YpCbCr8Planar, NULL, NULL, 3, pFrame->data, planeWidth, planeHeight, pFrame->linesize, nil, nil, nil, &pixel);
            
            //使用rgb24
            CVPixelBufferCreateWithBytes(nil, pCodecCtx->width, pCodecCtx->height, kCVPixelFormatType_24RGB, pFrameRGB24->data[0], pFrameRGB24->linesize[0], nil, nil, nil, &pixel);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate onDecodeVideoFrame:pixel];
                CVPixelBufferRelease(pixel);
            });
            
            self.countRemaining--;
        }
    }
}

- (void)stopDecode {
    if (!pFormatCtx) {
        return;
    }
    
    [self free];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate onDecodeEnd:YES];
    });
}

- (void)free {
    self.filePath = nil;
    
    [self teardownDecodeTimer];
    
    if (out_buffer) {
        av_free(out_buffer);
        out_buffer = NULL;
    }
    
    if (pFrame) {
        av_frame_free(&pFrame);
    }
    if (pFrameRGB24) {
        av_frame_free(&pFrameRGB24);
    }
    
    if (packet) {
        av_free_packet(packet);
        packet = NULL;
    }
    
    if (pCodecCtx) {
        avcodec_close(pCodecCtx);
        pCodecCtx = NULL;
    }
    
    if (pFormatCtx) {
        avformat_close_input(&pFormatCtx);
    }
    
    if (sws_ctx) {
        sws_freeContext(sws_ctx);
        sws_ctx = NULL;
    }
    
    vStream = NULL;
    pCodec = NULL;
}

- (void)pauseDecode {
    [self teardownDecodeTimer];
}

- (void)resumeDecode {
    [self setupDecodeTimer];
}

- (void)setupDecodeTimer {
    if (self.timer) {
        return;
    }
    
    NSTimeInterval timeInterval = 1.f * vStream->avg_frame_rate.den / vStream->avg_frame_rate.num;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(decodeFrame) userInfo:nil repeats:YES];
}

- (void)teardownDecodeTimer {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
}

@end
