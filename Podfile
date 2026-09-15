platform :ios, '26.5'

target 'stopwatch' do
  use_frameworks!

  pod 'MobileVLCKit', '3.7.3'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |configuration|
      configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
