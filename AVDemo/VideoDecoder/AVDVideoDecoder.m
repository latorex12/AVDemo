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
#include <libswresample/swresample.h>
#include <libavutil/samplefmt.h>

@interface AVDVideoDecoder (){
    AVFormatContext *pFormatCtx;
    int videoIndex, audioIndex;
    AVCodecContext *pVCodecCtx, *pACodecCtx;
    AVCodec *pVCodec, *pACodec;
    AVStream *vStream, *aStream;
    AVFrame *pFrame, *pFrameRGB24, *pAFrame;
    struct SwsContext *sws_ctx;
    struct SwrContext *swr_ctx;
    unsigned char *out_buffer, *a_out_buffer;
    int out_linesize, a_out_buffer_size;
    AVPacket *packet;
}

@property (nonatomic, strong) dispatch_queue_t decodeQueue;

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) unsigned int countRemaining;

@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) NSTimeInterval totalDuration;

@property (nonatomic, assign) int videoW;
@property (nonatomic, assign) int videoH;

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
        if (vStream->codec->codec_type == AVMEDIA_TYPE_VIDEO && pVCodec == NULL) {
            videoIndex = i;
            pVCodecCtx = vStream->codec;
            self.totalDuration = vStream->duration * 1.f * av_q2d(vStream->time_base);
            
            int audioStreamIndex = av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, videoIndex, NULL, 0);
            if (audioStreamIndex != AVERROR_STREAM_NOT_FOUND) {
                audioIndex = audioStreamIndex;
                aStream = pFormatCtx->streams[audioStreamIndex];
                pACodecCtx = aStream->codec;
            }
            
            break;
        }
        
    }
    
    if (pVCodecCtx == NULL || pACodecCtx == NULL) {
        printf("⚠️没有找到音+视频流");
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    ///STEP4.获取对应解码器
    pVCodec = avcodec_find_decoder(pVCodecCtx->codec_id);
    res = avcodec_open2(pVCodecCtx, pVCodec, NULL);
    if (res != 0) {
        printf("⚠️初始化视频解码环境失败, err:%d", res);
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    pACodec = avcodec_find_decoder(pACodecCtx->codec_id);
    res = avcodec_open2(pACodecCtx, pACodec, NULL);
    if (res != 0) {
        printf("⚠️初始化音频解码环境失败, err:%d", res);
        avcodec_close(pVCodecCtx);
        avformat_close_input(&pFormatCtx);
        return NO;
    }
    
    ///STEP5.配置转换器
    sws_ctx = sws_getContext(pVCodecCtx->width, pVCodecCtx->height, pVCodecCtx->pix_fmt,
        pVCodecCtx->width, pVCodecCtx->height, AV_PIX_FMT_RGB24, SWS_BILINEAR, NULL, NULL, NULL);
    
    swr_ctx = swr_alloc_set_opts(NULL,
                                 AV_CH_LAYOUT_MONO,
                                 AV_SAMPLE_FMT_S16,
                                 44100,
                                 pACodecCtx->channel_layout,
                                 pACodecCtx->sample_fmt,
                                 pACodecCtx->sample_rate,
                                 0,
                                 NULL);
    swr_init(swr_ctx);
    
    ///STEP6.配置packet/frame
    packet = av_packet_alloc();

    pFrame = av_frame_alloc();
    pFrameRGB24 = av_frame_alloc();
    
    int numBytes = avpicture_get_size(AV_PIX_FMT_RGB24, pVCodecCtx->width, pVCodecCtx->height);
    out_buffer = (uint8_t*)av_malloc(numBytes * sizeof(uint8_t));
    
    avpicture_fill((AVPicture*)pFrameRGB24, out_buffer, AV_PIX_FMT_RGB24, pVCodecCtx->width, pVCodecCtx->height);
    
    a_out_buffer_size = av_samples_get_buffer_size(&out_linesize,
                                                     pACodecCtx->channels,
                                                     pACodecCtx->frame_size,
                                                     pACodecCtx->sample_fmt,
                                                     1);
    
    a_out_buffer = av_malloc(a_out_buffer_size);
    
    ///设置音视频属性
    self.videoW = pVCodecCtx->width;
    self.videoH = pVCodecCtx->height;

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
            return;
        }
        
        NSLog(@"read frame");
        [self decode];
    }
        
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate onDecodeEnd:NO];
        [self free];
    });
}

- (void)decode {
    if (packet->stream_index == videoIndex) {
        [self decodeVideo];
    }
    if (packet->stream_index == audioIndex) {
        [self decodeAudio];
    }
}

- (void)decodeVideo {
    int frameFinished = 0;
    //解码
    int r = avcodec_decode_video2(pVCodecCtx, pFrame, &frameFinished, packet);
    packet->size -= r;
    packet->data += r;
    
    if (frameFinished) {
        sws_scale(sws_ctx, (uint8_t const * const *)pFrame->data, pFrame->linesize, 0, pVCodecCtx->height, pFrameRGB24->data, pFrameRGB24->linesize);
        
        //写入pixelBuf
        CVPixelBufferRef pixel;
        
        //直接使用420p
        //                size_t planeWidth[3] = {pFrame->width, pFrame->width/2, pFrame->width/2};
        //                size_t planeHeight[3] = {pFrame->height, pFrame->height/2, pFrame->height/2};
        //                res = CVPixelBufferCreateWithPlanarBytes(nil, pCodecCtx->width, pCodecCtx->height, kCVPixelFormatType_420YpCbCr8Planar, NULL, NULL, 3, pFrame->data, planeWidth, planeHeight, pFrame->linesize, nil, nil, nil, &pixel);
        
        //使用rgb24
        CVPixelBufferCreateWithBytes(nil, pVCodecCtx->width, pVCodecCtx->height, kCVPixelFormatType_24RGB, pFrameRGB24->data[0], pFrameRGB24->linesize[0], nil, nil, nil, &pixel);
        
        NSTimeInterval timestamp = pFrame->pts * 1.0f * av_q2d(vStream->time_base);
        self.currentTime = timestamp;
        NSLog(@"decoded frame %p, timestamp:%f", pixel, timestamp);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate onDecodeVideoFrame:pixel timestamp:timestamp];
            CVPixelBufferRelease(pixel);
        });
        
        self.countRemaining--;
    }
}

- (void)decodeAudio {
    int gotFrame = 0;
    //解码
    int result = avcodec_decode_audio4(pACodecCtx, pFrame, &gotFrame, packet);
    packet->size -= result;
    packet->data += result;
    
    if (result < 0) {
        printf("Send audio data to decoder failed.");
        return;
    }
    
    if (gotFrame == 0) {
        return;
    }
    
    // 转换
    int ret = swr_convert(swr_ctx, &a_out_buffer, pFrame->nb_samples*2, (const uint8_t **)pFrame->data , pFrame->nb_samples);
    
    if (ret < 0) {
        printf("Send audio data to Resample Convertor failed.");
        return;
    }
    
    NSTimeInterval timestamp = pFrame->pts * 1.0f * av_q2d(aStream->time_base);
    if (timestamp <= 0) {
        return;
    }
    
    [self.delegate onDecodeAudioFrame:a_out_buffer len:ret*2 timestamp:timestamp];
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
    
    if (pVCodecCtx) {
        avcodec_close(pVCodecCtx);
        pVCodecCtx = NULL;
    }
    
    if (pFormatCtx) {
        avformat_close_input(&pFormatCtx);
    }
    
    if (sws_ctx) {
        sws_freeContext(sws_ctx);
        sws_ctx = NULL;
    }
    
    vStream = NULL;
    pVCodec = NULL;
}

- (void)pauseDecode {
    [self teardownDecodeTimer];
}

- (void)resumeDecode {
    [self setupDecodeTimer];
}

- (void)setupDecodeTimer {
    if (self.timer || !self.filePath) {
        return;
    }
    
    NSTimeInterval timeInterval = 1.f * vStream->avg_frame_rate.den / vStream->avg_frame_rate.num-0.02;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(decodeFrame) userInfo:nil repeats:YES];
}

- (void)teardownDecodeTimer {
    if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
}

- (void)seekTo:(NSTimeInterval)time {
    if (!self.filePath) {
        return;
    }
    
    int64_t timestamp = time / av_q2d(vStream->time_base);
    int ret = av_seek_frame(pFormatCtx, videoIndex, timestamp, AVSEEK_FLAG_BACKWARD);
    
    if (ret < 0) {
        NSLog(@"seek frame failed:%d", ret);
    }
}

@end
