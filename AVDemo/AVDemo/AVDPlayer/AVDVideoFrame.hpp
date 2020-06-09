//
//  AVDVideoFrame.hpp
//  AVDemo
//
//  Created by SkyRim on 2020/6/10.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#ifndef AVDVideoFrame_hpp
#define AVDVideoFrame_hpp

#include <stdio.h>
#include <MacTypes.h>

namespace AVD {
/// 一个视频帧
struct VideoFrame {
    int width;//宽
    int height;//高
    Byte* data;//数据体
    int format;//类型
    
    float position;//时间戳
};
}

#endif /* AVDVideoFrame_hpp */
