TARGET = Inject.dylib
SDK = $(shell xcrun --sdk iphoneos --show-sdk-path)
ARCH = arm64
CC = clang
CFLAGS = -arch $(ARCH) -isysroot $(SDK) -mios-version-min=14.0 -fobjc-arc -fmodules

# SSZipArchive 源码目录（需要手动下载或由 CI 下载）
SSZIP_DIR = SSZipArchive
SSZIP_SOURCES = $(shell find $(SSZIP_DIR) -name "*.m" -o -name "*.c" 2>/dev/null)

$(TARGET): Inject.m $(SSZIP_SOURCES)
	$(CC) $(CFLAGS) -dynamiclib -o $@ $^ \
		-I$(SSZIP_DIR) -I$(SSZIP_DIR)/minizip \
		-framework UIKit -framework Foundation -framework Security \
		-lz

clean:
	rm -f $(TARGET)

.PHONY: clean
