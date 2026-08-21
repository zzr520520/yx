TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

ARCHS = arm64 arm64e
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeviceSpoofPro

DeviceSpoofPro_FILES = Tweak.xm SpoofManager.m KeychainHelper.m fishhook.c
DeviceSpoofPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DeviceSpoofPro_FRAMEWORKS = UIKit CoreFoundation Foundation CoreMotion Security
DeviceSpoofPro_PRIVATE_FRAMEWORKS = MobileGestalt
DeviceSpoofPro_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
