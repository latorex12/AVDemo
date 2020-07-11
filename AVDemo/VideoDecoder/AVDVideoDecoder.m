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
    AVFrame *pFrame, *pFrameRGBA32, *pAFrame;
    struct SwsContext *sws_ctx;
    struct SwrContext *swr_ctx;
    unsigned char *out_buffer, *a_out_buffer;
    int v_out_buffer_size, out_linesize, a_out_buffer_size;
    AVPacket *packet;
}

@property (nonatomic, strong) NSThread *decodeThread;

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, assign) BOOL pause;

@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) NSTimeInterval totalDuration;

@property (nonatomic, assign) int videoW;
@property (nonatomic, assign) int videoH;
@property (nonatomic, assign) int lineSize;

@property (nonatomic, assign) BOOL isEOF;

@end

@implementation AVDVideoDecoder

- (void)dealloc {
    [self stopDecode];
    [self.decodeThread cancel];
}

- (instancetype)init {
    if (self = [super init]) {
        //注册
        av_register_all();
        [self setupDecodeThread];
    }
    return self;
}

- (void)setupDecodeThread {
    NSThread *decodeThread = [[NSThread alloc] initWithBlock:^{
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }];
    
    decodeThread.name = @"AVD Decode";
    [decodeThread start];
    
    self.decodeThread = decodeThread;
}

- (void)startDecode:(NSString *)filePath {
    if (![NSThread.currentThread isEqual:self.decodeThread]) {
        [self performSelector:@selector(startDecode:) onThread:self.decodeThread withObject:filePath waitUntilDone:NO];
        return;
    }
    
    NSLog(@"Decoder start decode:%@", filePath);
    
    if (self.filePath) {
        printf("⚠️当前正在解码，无法重复解码");
        return;
    }
    
    self.filePath = filePath;
    
    @synchronized (self) {
        if (![self prepare]) {
            [self free];
            [self.delegate onDecodeError];
            return;
        }
    }

    self.isEOF = NO;
    
    [self startParse];
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
    pFrameRGBA32 = av_frame_alloc();
    
    v_out_buffer_size = avpicture_get_size(AV_PIX_FMT_BGRA, pVCodecCtx->width, pVCodecCtx->height);
    out_buffer = (uint8_t*)av_malloc(v_out_buffer_size * sizeof(uint8_t));
    
    avpicture_fill((AVPicture*)pFrameRGBA32, out_buffer, AV_PIX_FMT_RGB24, pVCodecCtx->width, pVCodecCtx->height);
    
    a_out_buffer_size = av_samples_get_buffer_size(&out_linesize,
                                                     pACodecCtx->channels,
                                                     pACodecCtx->frame_size,
                                                     pACodecCtx->sample_fmt,
                                                     1);
    
    a_out_buffer = av_malloc(a_out_buffer_size);
    
    ///设置音视频属性
    self.videoW = pVCodecCtx->width;
    self.videoH = pVCodecCtx->height;
    self.lineSize = pFrameRGBA32->linesize[0];

    return YES;
}

- (void)startParse {
    if (self.isEOF) {
        return;
    }
    
    while (av_read_frame(pFormatCtx, packet) >= 0) {
        if (!self.filePath || self.pause) {
            NSLog(@"Decoder stop decode or paused.");
            return;
        }
        
        NSLog(@"read frame");
        [self decode];
    }
        
    [self.delegate onDecodeEnd:NO];
    [self free];
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
    NSLog(@"Decoder decode video frame");
    
    int frameFinished = 0;
    //解码
    int r = avcodec_decode_video2(pVCodecCtx, pFrame, &frameFinished, packet);
    packet->size -= r;
    packet->data += r;
    
    if (frameFinished) {
        sws_scale(sws_ctx, (uint8_t const * const *)pFrame->data, pFrame->linesize, 0, pVCodecCtx->height, pFrameRGBA32->data, pFrameRGBA32->linesize);
        
        NSTimeInterval timestamp = pFrame->pts * 1.0f * av_q2d(vStream->time_base);
        self.currentTime = timestamp;
        
        void *data = malloc(v_out_buffer_size);
        memcpy(data, out_buffer, v_out_buffer_size);
        
        NSLog(@"decoded frame %, timestamp:%f", data, timestamp);
        
        [self.delegate onDecodeVideoFrame:data len:v_out_buffer_size timestamp:timestamp];
    }
}

- (void)decodeAudio {
    NSLog(@"Decoder decode audio frame");
    
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
    
    //初始化内存空间
    void *out_buffer = av_malloc(a_out_buffer_size);
    
    // 转换
    int ret = swr_convert(swr_ctx, &out_buffer, pFrame->nb_samples*2, (const uint8_t **)pFrame->data , pFrame->nb_samples);
    
    if (ret < 0) {
        printf("Send audio data to Resample Convertor failed.");
        return;
    }
    
    NSTimeInterval timestamp = pFrame->pts * 1.0f * av_q2d(aStream->time_base);
    if (timestamp <= 0) {
        return;
    }
    
    [self.delegate onDecodeAudioFrame:out_buffer len:ret*2 timestamp:timestamp];
}

- (void)stopDecode {
    @synchronized (self) {
        NSLog(@"Decoder stop decode");
        
        if (!pFormatCtx) {
            return;
        }
        
        [self free];
        [self.delegate onDecodeEnd:YES];
    }
}

- (void)free {
    self.filePath = nil;
    
    if (out_buffer) {
        av_free(out_buffer);
        out_buffer = NULL;
    }
    
    if (pFrame) {
        av_frame_free(&pFrame);
    }
    if (pFrameRGBA32) {
        av_frame_free(&pFrameRGBA32);
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
    
    self.isEOF = YES;
}

- (void)pauseDecode {
    @synchronized (self) {
        NSLog(@"Decoder pause decode");
        
        if (!self.filePath) {
            return;
        }
        
        self.pause = YES;
    }
}

- (void)resumeDecode {
    @synchronized (self) {
        NSLog(@"Decoder resume decode");
        
        if (!self.filePath) {
            return;
        }
        
        self.pause = NO;
    }
    
    [self performSelector:@selector(startParse) onThread:self.decodeThread withObject:nil waitUntilDone:NO];
}

- (void)seekTo:(NSTimeInterval)time {
    @synchronized (self) {
        if (!self.filePath) {
            return;
        }
        
        int64_t timestamp = time / av_q2d(vStream->time_base);
        int ret = av_seek_frame(pFormatCtx, videoIndex, timestamp, AVSEEK_FLAG_BACKWARD);
        
        if (ret < 0) {
            NSLog(@"seek frame failed:%d", ret);
        }
    }
}

@end
