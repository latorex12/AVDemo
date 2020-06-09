//
//  AVDAudioFrame.hpp
//  AVDemo
//
//  Created by SkyRim on 2020/6/10.
//  Copyright © 2020 SkyRim. All rights reserved.
//

#ifndef AVDAudioFrame_hpp
#define AVDAudioFrame_hpp

#include <stdio.h>
#include <MacTypes.h>

namespace AVD {
struct AudioFrame {
    int sampleRate;
    int channelCount;
    Byte* data;
    int format;
        
    float position;
};
}

#endif /* AVDAudioFrame_hpp */
