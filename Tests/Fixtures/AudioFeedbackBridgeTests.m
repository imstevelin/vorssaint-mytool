// SPDX-License-Identifier: GPL-3.0-or-later
#import "AudioFeedbackBridge.h"

@interface TestEngine : NSObject
@property (getter=isRunning) BOOL running;
@property BOOL failStart, throwPrepare, throwStop;
@property int starts, stops;
- (void)attachNode:(id)node;
- (void)connect:(id)node to:(id)mixer format:(id)format;
- (id)mainMixerNode;
- (void)prepare;
- (BOOL)startAndReturnError:(NSError **)error;
- (void)stop;
@end
@implementation TestEngine
- (void)attachNode:(id)node { }
- (void)connect:(id)node to:(id)mixer format:(id)format { }
- (id)mainMixerNode { return nil; }
- (void)prepare { if (_throwPrepare) [NSException raise:@"RouteLost" format:@"prepare"]; }
- (BOOL)startAndReturnError:(NSError **)error { _starts++; return _running = !_failStart; }
- (void)stop { _stops++; _running = NO; if (_throwStop) [NSException raise:@"RouteLost" format:@"stop"]; }
@end
@interface TestNode : NSObject
@property (getter=isPlaying) BOOL playing;
@property BOOL throwPlay, throwSchedule;
@property float volume;
@property int scheduled;
@property (nonatomic, strong) TestEngine *engine;
- (void)play;
- (void)scheduleBuffer:(id)buffer atTime:(id)time options:(AVAudioPlayerNodeBufferOptions)options completionHandler:(id)handler;
@end
@implementation TestNode
- (void)play { if (_throwPlay) [NSException raise:@"RouteLost" format:@"play"]; _playing = YES; }
- (void)scheduleBuffer:(id)b atTime:(id)t options:(AVAudioPlayerNodeBufferOptions)o completionHandler:(id)c {
    if (_throwSchedule) [NSException raise:@"RouteLost" format:@"schedule"]; _scheduled++;
}
@end
@interface TestBuffer : NSObject
- (id)format;
@end
@implementation TestBuffer
- (id)format { return nil; }
@end
static int checks, failures;
#define CHECK(value) do { checks++; if (!(value)) { failures++; fprintf(stderr, "Audio bridge check failed at line %d\n", __LINE__); } } while(0)
int main(void) {
    @autoreleasepool {
        TestEngine *e = [TestEngine new]; TestNode *n = [TestNode new]; n.engine = e;
        AVAudioEngine *engine = (id)e; AVAudioPlayerNode *node = (id)n; AVAudioPCMBuffer *buffer = (id)[TestBuffer new];
        CHECK(VSDAudioFeedbackStart(engine, node, buffer));
        CHECK(VSDAudioFeedbackReady(engine, node));
        for (int i = 0; i < 3; i++) CHECK(VSDAudioFeedbackSchedule(engine, node, buffer));
        CHECK(n.scheduled == 3);
        e.running = NO;
        CHECK(!VSDAudioFeedbackSchedule(engine, node, buffer));
        e.failStart = YES;
        CHECK(!VSDAudioFeedbackStart(engine, node, buffer));
        e.failStart = NO; n.throwPlay = YES;
        CHECK(!VSDAudioFeedbackStart(engine, node, buffer)); // Exact crashing call, now contained.
        CHECK(!e.running);
        n.throwPlay = NO; e.throwPrepare = YES;
        CHECK(!VSDAudioFeedbackStart(engine, node, buffer));
        e.throwPrepare = NO;
        CHECK(VSDAudioFeedbackStart(engine, node, buffer));
        n.throwSchedule = YES;
        CHECK(!VSDAudioFeedbackSchedule(engine, node, buffer));
        e.throwStop = YES; VSDAudioFeedbackStop(engine);
        CHECK(!e.running);
        printf("AUDIO FEEDBACK BRIDGE TESTS %s (%d checks)\n", failures ? "FAILED" : "OK", checks);
    }
    return failures ? 1 : 0;
}
