#pragma once
#import <AVFAudio/AVFAudio.h>
#include <stdbool.h>
// AVFAudio can raise NSException during a hardware route transition. Keep
// those exceptions entirely inside Objective-C; Swift catch handles NSError.
bool VSDAudioFeedbackStart(AVAudioEngine *engine, AVAudioPlayerNode *node, AVAudioPCMBuffer *buffer);
bool VSDAudioFeedbackReady(AVAudioEngine *engine, AVAudioPlayerNode *node);
bool VSDAudioFeedbackSchedule(AVAudioEngine *engine, AVAudioPlayerNode *node, AVAudioPCMBuffer *buffer);
void VSDAudioFeedbackStop(AVAudioEngine *engine);
