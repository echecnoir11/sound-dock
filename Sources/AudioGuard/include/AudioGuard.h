#include <stdbool.h>
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Translates Objective-C exceptions from Apple audio units into recoverable errors.
FOUNDATION_EXPORT NSError * _Nullable SDRunSafely(void (NS_NOESCAPE ^operation)(void));
NS_ASSUME_NONNULL_END

#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
NS_ASSUME_NONNULL_BEGIN
typedef struct SDCapture SDCapture;
FOUNDATION_EXPORT SDCapture * _Nullable SDCaptureBufferCreate(void);
FOUNDATION_EXPORT UInt32 SDCapturePush(SDCapture *capture, UInt32 frames, const float *left, const float *right);
FOUNDATION_EXPORT SDCapture * _Nullable SDCaptureCreate(AudioDeviceID device, double sampleRate, NSError * _Nullable * _Nullable error);
/// Configure only while capture and render callbacks are stopped.
FOUNDATION_EXPORT bool SDCaptureConfigureBuffer(SDCapture *capture, double sampleRate, double prebufferSeconds, double capacitySeconds);
FOUNDATION_EXPORT OSStatus SDCaptureStart(SDCapture *capture);
FOUNDATION_EXPORT void SDCaptureRead(SDCapture *capture, UInt32 frames, AudioBufferList *buffers);
typedef struct { float input; float source; float output; uint64_t callbacks; uint64_t captured; uint64_t rendered; int32_t error; double queuedSeconds; double progress; bool buffering; uint64_t resyncs; } SDSignalLevels;
FOUNDATION_EXPORT SDSignalLevels SDCaptureGetLevels(SDCapture *capture);
FOUNDATION_EXPORT void SDCaptureMarkOutput(SDCapture *capture, UInt32 frames, const AudioBufferList *buffers);
FOUNDATION_EXPORT void SDCaptureDestroy(SDCapture *capture);
NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
/// Lightweight amplitude-envelope mailbox; no capture device, ring buffer or FFT.
typedef struct SDVisualizer SDVisualizer;
FOUNDATION_EXPORT SDVisualizer * _Nullable SDVisualizerCreate(void);
FOUNDATION_EXPORT void SDVisualizerProcess(SDVisualizer *meter, UInt32 frames, const AudioBufferList *buffers);
FOUNDATION_EXPORT uint64_t SDVisualizerCopy(SDVisualizer *meter, float *levels, UInt32 count);
FOUNDATION_EXPORT void SDVisualizerReset(SDVisualizer *meter);
FOUNDATION_EXPORT void SDVisualizerDestroy(SDVisualizer *meter);
NS_ASSUME_NONNULL_END
