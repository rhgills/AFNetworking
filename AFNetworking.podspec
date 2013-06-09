Pod::Spec.new do |s|
  s.name     = 'AFNetworking'
  s.version  = '1.2.3'
  s.license  = 'MIT'
  s.summary  = 'A delightful iOS and OS X networking framework.'
  s.homepage = 'https://github.com/rhgills/AFNetworking'
  s.authors  = { 'Mattt Thompson' => 'm@mattt.me', 'Scott Raymond' => 'sco@gowalla.com' }
  s.source   = { :git => 'https://github.com/rhgills/AFNetworking.git', :tag => '1.2.3' }
  s.source_files = 'AFNetworking'
  s.requires_arc = true

  s.platform = :ios, '5.0'
  s.ios.frameworks = 'MobileCoreServices', 'SystemConfiguration', 'Security'

  s.dependency 'RXCollections'
  s.dependency 'CocoaLumberjack'
  s.dependency 'RGKit'

  s.prefix_header_contents = <<-EOS
#import <Availability.h>

#define _AFNETWORKING_PIN_SSL_CERTIFICATES_

#if __IPHONE_OS_VERSION_MIN_REQUIRED
  #import <SystemConfiguration/SystemConfiguration.h>
  #import <MobileCoreServices/MobileCoreServices.h>
#else
  #import <SystemConfiguration/SystemConfiguration.h>
  #import <CoreServices/CoreServices.h>
#endif
EOS
end
