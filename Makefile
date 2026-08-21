TARGET = Inject.dylib
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
ARCH = arm64
CC = clang
CFLAGS = -arch $(ARCH) -isysroot $(SDK) -mios-version-min=14.0 -fobjc-arc -fmodules

$(TARGET): Inject.m
	$(CC) $(CFLAGS) -dynamiclib -o $@ $^ -framework UIKit -framework Foundation -framework Security

clean:
	rm -f $(TARGET)

.PHONY: clean
