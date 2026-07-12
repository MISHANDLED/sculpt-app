#import "RealtimeAtomics.h"
#import <AVFAudio/AVFAudio.h>

#if __has_feature(objc_arc)
#error RealtimeTapBridge.m must be compiled with -fno-objc-arc
#endif

@interface RTSpectrumTapContext : NSObject {
@public
    void *_submitContext;
    RTSpectrumSubmitFunction _submit;
    void *_lifetimeContext;
    RTSpectrumReleaseFunction _releaseLifetime;
}
- (instancetype)initWithSubmitContext:(void *)submitContext
                                submit:(RTSpectrumSubmitFunction)submit
                       lifetimeContext:(void *)lifetimeContext
                       releaseLifetime:(RTSpectrumReleaseFunction)releaseLifetime;
@end

@implementation RTSpectrumTapContext
- (instancetype)initWithSubmitContext:(void *)submitContext
                                submit:(RTSpectrumSubmitFunction)submit
                       lifetimeContext:(void *)lifetimeContext
                       releaseLifetime:(RTSpectrumReleaseFunction)releaseLifetime {
    self = [super init];
    if (self != nil) {
        _submitContext = submitContext;
        _submit = submit;
        _lifetimeContext = lifetimeContext;
        _releaseLifetime = releaseLifetime;
    }
    return self;
}

- (void)dealloc {
    if (_releaseLifetime != NULL) {
        _releaseLifetime(_lifetimeContext);
    }
    [super dealloc];
}
@end

__attribute__((noinline))
static void rt_spectrum_tap_forward(
    RTSpectrumTapContext *context,
    AVAudioPCMBuffer *buffer
) {
    float * const *channels = buffer.floatChannelData;
    AVAudioFrameCount frameLength = buffer.frameLength;
    if (channels == NULL || channels[0] == NULL || frameLength == 0) {
        return;
    }
    context->_submit(
        context->_submitContext,
        channels[0],
        (intptr_t)frameLength
    );
}

void rt_audio_node_install_spectrum_tap(
    void *nodePointer,
    uint32_t bus,
    uint32_t bufferSize,
    void *submitContext,
    RTSpectrumSubmitFunction submit,
    void *lifetimeContext,
    RTSpectrumReleaseFunction releaseLifetime
) {
    AVAudioNode *node = (AVAudioNode *)nodePointer;
    RTSpectrumTapContext *context = [[RTSpectrumTapContext alloc]
        initWithSubmitContext:submitContext
        submit:submit
        lifetimeContext:lifetimeContext
        releaseLifetime:releaseLifetime];
    [node installTapOnBus:bus
               bufferSize:bufferSize
                   format:nil
                    block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        (void)when;
        rt_spectrum_tap_forward(context, buffer);
    }];
    [context release];
}
