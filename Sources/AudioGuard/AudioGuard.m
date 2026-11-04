#import "AudioGuard.h"
NSError *SDRunSafely(void (^operation)(void)) {
    @try { operation(); return nil; }
    @catch (NSException *exception) {
        return [NSError errorWithDomain:@"audio.sounddock.exception" code:1 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: exception.name}];
    }
}

#import <stdatomic.h>
#import <stdlib.h>
#import <string.h>
#import <math.h>
#define SD_RING_FRAMES 65536
#define SD_MAX_FRAMES 8192
struct SDCapture {
    AudioUnit unit;
    _Atomic uint64_t callbacks, captured, rendered;
    _Atomic int32_t lastError;
    _Atomic uint32_t inputPeak, sourcePeak, outputPeak;
    _Atomic uint64_t written;
    _Atomic uint64_t read;
    float *left, *right;
    UInt32 capacity, threshold, fadeRemaining;
    double sampleRate;
    _Atomic bool buffering, resyncRequested;
    _Atomic uint64_t resyncs;
    float scratchLeft[SD_MAX_FRAMES];
    float scratchRight[SD_MAX_FRAMES];
};
static void SDPeak(_Atomic uint32_t *destination, float value) {
    uint32_t peak = (uint32_t)(fminf(fabsf(value), 100) * 1000000);
    uint32_t old = atomic_load_explicit(destination, memory_order_relaxed);
    while (peak > old && !atomic_compare_exchange_weak_explicit(destination, &old, peak, memory_order_relaxed, memory_order_relaxed)) {}
}
static OSStatus SDInput(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    SDCapture *capture = context;
    atomic_fetch_add_explicit(&capture->callbacks, 1, memory_order_relaxed);
    if (frames > SD_MAX_FRAMES) return kAudioUnitErr_TooManyFramesToProcess;
    struct { UInt32 count; AudioBuffer buffers[2]; } storage;
    storage.count = 2;
    storage.buffers[0] = (AudioBuffer){1, frames * sizeof(float), capture->scratchLeft};
    storage.buffers[1] = (AudioBuffer){1, frames * sizeof(float), capture->scratchRight};
    OSStatus status = AudioUnitRender(capture->unit, flags, time, 1, frames, (AudioBufferList *)&storage);
    atomic_store_explicit(&capture->lastError, status, memory_order_relaxed);
    if (status != noErr) return status;
    float peak = 0;
    for (UInt32 i = 0; i < frames; i++) peak = fmaxf(peak, fmaxf(fabsf(capture->scratchLeft[i]), fabsf(capture->scratchRight[i])));
    SDPeak(&capture->inputPeak, peak);
    atomic_fetch_add_explicit(&capture->captured, frames, memory_order_relaxed);
    SDCapturePush(capture, frames, capture->scratchLeft, capture->scratchRight);
    return noErr;
}
SDCapture *SDCaptureBufferCreate(void) {
    SDCapture *capture = calloc(1, sizeof(SDCapture));
    if (!capture) return NULL;
    capture->capacity = SD_RING_FRAMES;
    capture->sampleRate = 48000;
    capture->left = calloc(capture->capacity, sizeof(float));
    capture->right = calloc(capture->capacity, sizeof(float));
    if (!capture->left || !capture->right) { SDCaptureDestroy(capture); return NULL; }
    atomic_init(&capture->written, 0); atomic_init(&capture->read, 0);
    atomic_init(&capture->callbacks, 0); atomic_init(&capture->captured, 0); atomic_init(&capture->rendered, 0);
    atomic_init(&capture->lastError, 0); atomic_init(&capture->inputPeak, 0); atomic_init(&capture->sourcePeak, 0); atomic_init(&capture->outputPeak, 0);
    atomic_init(&capture->buffering, false); atomic_init(&capture->resyncRequested, false); atomic_init(&capture->resyncs, 0);
    return capture;
}
bool SDCaptureConfigureBuffer(SDCapture *capture, double sampleRate, double prebufferSeconds, double capacitySeconds) {
    if (!isfinite(sampleRate) || sampleRate <= 0 || sampleRate > 192000 || !isfinite(capacitySeconds) || capacitySeconds <= 0 || capacitySeconds > 60 || !isfinite(prebufferSeconds) || prebufferSeconds < 0 || prebufferSeconds >= capacitySeconds) return NO;
    UInt32 capacity = (UInt32)ceil(sampleRate * capacitySeconds);
    UInt32 threshold = (UInt32)ceil(sampleRate * prebufferSeconds);
    float *left = calloc(capacity, sizeof(float)), *right = calloc(capacity, sizeof(float));
    if (!left || !right) { free(left); free(right); return NO; }
    free(capture->left); free(capture->right);
    capture->left = left; capture->right = right; capture->capacity = capacity;
    capture->threshold = threshold; capture->sampleRate = sampleRate; capture->fadeRemaining = threshold ? 256 : 0;
    atomic_store(&capture->written, 0); atomic_store(&capture->read, 0);
    atomic_store(&capture->buffering, threshold > 0); atomic_store(&capture->resyncRequested, false); atomic_store(&capture->resyncs, 0);
    return YES;
}
UInt32 SDCapturePush(SDCapture *capture, UInt32 frames, const float *left, const float *right) {
    uint64_t write = atomic_load_explicit(&capture->written, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&capture->read, memory_order_acquire);
    UInt32 available = (UInt32)(capture->capacity - (write - read));
    UInt32 count = MIN(frames, available);
    for (UInt32 i = 0; i < count; i++) {
        capture->left[(write + i) % capture->capacity] = left[i];
        capture->right[(write + i) % capture->capacity] = right[i];
    }
    atomic_store_explicit(&capture->written, write + count, memory_order_release);
    if (count < frames && capture->threshold > 0) atomic_store_explicit(&capture->resyncRequested, true, memory_order_release);
    return count;
}
SDCapture *SDCaptureCreate(AudioDeviceID device, double sampleRate, NSError **error) {
    SDCapture *capture = SDCaptureBufferCreate();
    if (!capture) { if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:12 userInfo:nil]; return NULL; }
    AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    OSStatus status = component ? AudioComponentInstanceNew(component, &capture->unit) : kAudioUnitErr_FailedInitialization;
    UInt32 enabled = 1, disabled = 0, maxFrames = SD_MAX_FRAMES;
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, sizeof(enabled));
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, sizeof(disabled));
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device));
    AudioStreamBasicDescription format = {0};
    format.mSampleRate = sampleRate; format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    format.mBytesPerPacket = sizeof(float); format.mFramesPerPacket = 1;
    format.mBytesPerFrame = sizeof(float); format.mChannelsPerFrame = 2; format.mBitsPerChannel = 32;
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format));
    SInt32 map[2] = {0, 1};
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1, map, sizeof(map));
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, sizeof(maxFrames));
    AURenderCallbackStruct callback = {SDInput, capture};
    if (status == noErr) status = AudioUnitSetProperty(capture->unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(callback));
    if (status == noErr) status = AudioUnitInitialize(capture->unit);
    if (status != noErr) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Initialisation de l’entrée BlackHole impossible (CoreAudio %d).", (int)status]}];
        SDCaptureDestroy(capture); return NULL;
    }
    return capture;
}
OSStatus SDCaptureStart(SDCapture *capture) { return AudioOutputUnitStart(capture->unit); }
void SDCaptureRead(SDCapture *capture, UInt32 frames, AudioBufferList *buffers) {
    uint64_t read = atomic_load_explicit(&capture->read, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&capture->written, memory_order_acquire);
    if (capture->threshold && atomic_exchange_explicit(&capture->resyncRequested, false, memory_order_acquire)) {
        // Only the consumer advances read: discard excess old audio, never overwrite
        // samples being rendered. Resume near live with a five-second reserve.
        read = write - MIN(write - read, (uint64_t)capture->threshold);
        atomic_store_explicit(&capture->read, read, memory_order_release);
        capture->fadeRemaining = 256;
        atomic_fetch_add_explicit(&capture->resyncs, 1, memory_order_relaxed);
    }
    bool waiting = atomic_load_explicit(&capture->buffering, memory_order_relaxed);
    if (waiting && write - read >= MAX((uint64_t)capture->threshold, (uint64_t)frames)) {
        waiting = false;
        atomic_store_explicit(&capture->buffering, false, memory_order_relaxed);
        capture->fadeRemaining = 256;
    }
    UInt32 available = waiting ? 0 : (UInt32)MIN((uint64_t)frames, write - read);
    if (!waiting && available < frames && capture->threshold) atomic_store_explicit(&capture->buffering, true, memory_order_relaxed);
    float peak = 0;
    for (UInt32 channel = 0; channel < buffers->mNumberBuffers; channel++) {
        AudioBuffer *buffer = &buffers->mBuffers[channel];
        if (!buffer->mData) continue;
        float *output = buffer->mData;
        for (UInt32 i = 0; i < frames; i++) {
            float gain = 1;
            if (capture->threshold) {
                gain = i < capture->fadeRemaining ? (256.0f - capture->fadeRemaining + i) / 256.0f : 1;
                if (available < frames && i < available) gain *= fminf(1, (available - i) / 256.0f);
            }
            for (UInt32 c = 0; c < buffer->mNumberChannels; c++) {
                UInt32 source = buffers->mNumberBuffers == 1 ? c : channel;
                float sample = i < available ? (source == 0 ? capture->left[(read + i) % capture->capacity] : source == 1 ? capture->right[(read + i) % capture->capacity] : 0) * gain : 0;
                output[i * buffer->mNumberChannels + c] = sample;
                peak = fmaxf(peak, fabsf(sample));
            }
        }
    }
    if (available) capture->fadeRemaining = available >= capture->fadeRemaining ? 0 : capture->fadeRemaining - available;
    SDPeak(&capture->sourcePeak, peak);
    atomic_fetch_add_explicit(&capture->rendered, available, memory_order_relaxed);
    atomic_store_explicit(&capture->read, read + available, memory_order_release);
}
void SDCaptureMarkOutput(SDCapture *capture, UInt32 frames, const AudioBufferList *buffers) {
    float peak = 0;
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        const float *data = buffer->mData;
        if (!data) continue;
        UInt32 count = MIN(frames * buffer->mNumberChannels, buffer->mDataByteSize / sizeof(float));
        for (UInt32 i = 0; i < count; i++) peak = fmaxf(peak, fabsf(data[i]));
    }
    SDPeak(&capture->outputPeak, peak);
}
SDSignalLevels SDCaptureGetLevels(SDCapture *capture) {
    uint64_t read = atomic_load_explicit(&capture->read, memory_order_acquire);
    uint64_t write = atomic_load_explicit(&capture->written, memory_order_acquire);
    uint64_t queued = write >= read ? MIN(write - read, (uint64_t)capture->capacity) : 0;
    return (SDSignalLevels){
        atomic_exchange_explicit(&capture->inputPeak, 0, memory_order_relaxed) / 1000000.0f,
        atomic_exchange_explicit(&capture->sourcePeak, 0, memory_order_relaxed) / 1000000.0f,
        atomic_exchange_explicit(&capture->outputPeak, 0, memory_order_relaxed) / 1000000.0f,
        atomic_load_explicit(&capture->callbacks, memory_order_relaxed),
        atomic_load_explicit(&capture->captured, memory_order_relaxed),
        atomic_load_explicit(&capture->rendered, memory_order_relaxed),
        atomic_load_explicit(&capture->lastError, memory_order_relaxed),
        (double)queued / capture->sampleRate,
        capture->threshold ? fmin(1, (double)queued / capture->threshold) : 1,
        atomic_load_explicit(&capture->buffering, memory_order_relaxed),
        atomic_load_explicit(&capture->resyncs, memory_order_relaxed)
    };
}
void SDCaptureDestroy(SDCapture *capture) {
    if (!capture) return;
    if (capture->unit) { AudioOutputUnitStop(capture->unit); AudioUnitUninitialize(capture->unit); AudioComponentInstanceDispose(capture->unit); }
    free(capture->left); free(capture->right); free(capture);
}

#define SD_VISUALIZER_BARS 16
struct SDVisualizer {
    _Atomic uint32_t peaks[SD_VISUALIZER_BARS];
    _Atomic uint64_t generation;
};
SDVisualizer *SDVisualizerCreate(void) {
    SDVisualizer *meter = calloc(1, sizeof(SDVisualizer));
    if (meter) {
        for (UInt32 i = 0; i < SD_VISUALIZER_BARS; i++) atomic_init(&meter->peaks[i], 0);
        atomic_init(&meter->generation, 0);
    }
    return meter;
}
void SDVisualizerProcess(SDVisualizer *meter, UInt32 frames, const AudioBufferList *buffers) {
    if (!frames) return;
    float peaks[SD_VISUALIZER_BARS] = {0};
    for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
        const AudioBuffer *buffer = &buffers->mBuffers[b];
        const float *data = buffer->mData;
        if (!data || !buffer->mNumberChannels) continue;
        UInt32 count = MIN((uint64_t)frames * buffer->mNumberChannels, buffer->mDataByteSize / sizeof(float));
        for (UInt32 i = 0; i < count; i++) {
            UInt32 frame = i / buffer->mNumberChannels;
            UInt32 bar = (UInt32)MIN(15, (uint64_t)frame * SD_VISUALIZER_BARS / frames);
            peaks[bar] = fmaxf(peaks[bar], fabsf(data[i]));
        }
    }
    for (UInt32 i = 0; i < SD_VISUALIZER_BARS; i++) atomic_store_explicit(&meter->peaks[i], (uint32_t)(fminf(1, peaks[i]) * 1000000), memory_order_relaxed);
    atomic_fetch_add_explicit(&meter->generation, 1, memory_order_release);
}
uint64_t SDVisualizerCopy(SDVisualizer *meter, float *levels, UInt32 count) {
    uint64_t generation = atomic_load_explicit(&meter->generation, memory_order_acquire);
    for (UInt32 i = 0; i < count; i++) levels[i] = i < SD_VISUALIZER_BARS ? atomic_load_explicit(&meter->peaks[i], memory_order_relaxed) / 1000000.0f : 0;
    return generation;
}
void SDVisualizerReset(SDVisualizer *meter) {
    for (UInt32 i = 0; i < SD_VISUALIZER_BARS; i++) atomic_store_explicit(&meter->peaks[i], 0, memory_order_relaxed);
    atomic_store_explicit(&meter->generation, 0, memory_order_release);
}
void SDVisualizerDestroy(SDVisualizer *meter) { free(meter); }
