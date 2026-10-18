// SPDX-License-Identifier: GPL-3.0-or-later
#import "AudioFeedbackBridge.h"

void VSDAudioFeedbackStop(AVAudioEngine *engine) {
    @try { [engine stop]; } @catch (NSException *exception) { }
}
bool VSDAudioFeedbackReady(AVAudioEngine *engine, AVAudioPlayerNode *node) {
    @try { return engine && node && engine.running && node.playing && node.engine == engine; }
    @catch (NSException *exception) { return false; }
}
bool VSDAudioFeedbackStart(AVAudioEngine *engine, AVAudioPlayerNode *node, AVAudioPCMBuffer *buffer) {
    @try {
        [engine attachNode:node];
        [engine connect:node to:engine.mainMixerNode format:buffer.format];
        node.volume = 1;
        [engine prepare];
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) { VSDAudioFeedbackStop(engine); return false; }
        // The device can disappear after start succeeds and before play.
        [node play];
        if (!VSDAudioFeedbackReady(engine, node)) { VSDAudioFeedbackStop(engine); return false; }
        return true;
    } @catch (NSException *exception) {
        VSDAudioFeedbackStop(engine);
        return false;
    }
}
bool VSDAudioFeedbackSchedule(AVAudioEngine *engine, AVAudioPlayerNode *node, AVAudioPCMBuffer *buffer) {
    @try {
        if (!VSDAudioFeedbackReady(engine, node)) return false;
        [node scheduleBuffer:buffer atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:nil];
        return true;
    } @catch (NSException *exception) { return false; }
}
