#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint audio_manager.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'audio_manager'
  s.version          = '1.0.0'
  s.summary          = 'A flutter plugin for music playback, including notification handling.'
  s.description      = <<-DESC
A flutter plugin for music playback, including notification handling.
                       DESC
  s.homepage         = 'https://github.com/jeromexiong/audio_manager'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Jerome Xiong' => 'jeromexiong@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'audio_manager/Sources/audio_manager/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.9'
end
