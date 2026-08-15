#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint audio_manager.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'audio_manager'
  s.version          = '0.9.2'
  s.summary          = 'A flutter plugin for music playback, including notification handling.'
  s.description      = <<-DESC
A flutter plugin for music playback, including notification handling.
                       DESC
  s.homepage         = 'https://github.com/jeromexiong/audio_manager'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Jerome Xiong' => 'jeromexiong@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'audio_manager/Sources/audio_manager/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
