TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

ARCHS = arm64 arm64e
FINALPACKAGE = 1
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeviceSpoofProTweak
APPLICATION_NAME = DeviceSpoofProApp

# Tweak（后台 Hook dylib）
DeviceSpoofProTweak_FILES = Tweak.xm SpoofManager.m KeychainHelper.m fishhook.c
DeviceSpoofProTweak_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
DeviceSpoofProTweak_FRAMEWORKS = UIKit CoreFoundation Foundation CoreMotion Security
DeviceSpoofProTweak_LDFLAGS = -lsubstrate

# App（桌面图标 + 型号选择界面）
DeviceSpoofProApp_FILES = App/main.m App/AppDelegate.m App/ConfigViewController.m SpoofManager.m
DeviceSpoofProApp_CFLAGS = -fobjc-arc
DeviceSpoofProApp_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 SpringBoard"
