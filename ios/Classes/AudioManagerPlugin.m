#import "AudioManagerPlugin.h"
#if __has_include(<audio_manager/audio_manager-Swift.h>)
#import <audio_manager/audio_manager-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "audio_manager-Swift.h"
#endif

@implementation AudioManagerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAudioManagerPlugin registerWithRegistrar:registrar];
}
@end
