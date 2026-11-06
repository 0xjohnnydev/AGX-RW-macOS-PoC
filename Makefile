KEXTRW ?= ../KextRW
BUILD_DIR ?= build
COMMON_SOURCES = src/poc.m src/gfx.c src/IOGPUDevice.c src/target.c
COMMON_HEADERS = src/poc.h src/gfx.h src/IOGPUDevice.h src/offsets.h \
	src/target.h
TARGET = $(BUILD_DIR)/gfx-write-poc
SOURCES = poc/write_main.m src/write_poc.m $(COMMON_SOURCES)
HEADERS = $(COMMON_HEADERS)
MICROPPL_TARGET = $(BUILD_DIR)/micro-ppl-ttbr1-probe
MICROPPL_SOURCES = poc/microppl_main.m src/microppl.m $(COMMON_SOURCES)
MICROPPL_HEADERS = src/microppl.h $(HEADERS)
AUTH_TARGET = $(BUILD_DIR)/gfx-auth-call-poc
AUTH_SOURCES = poc/auth_main.m src/auth_call.m $(COMMON_SOURCES)
AUTH_HEADERS = src/auth_call.h $(HEADERS)
PAC_TARGET = $(BUILD_DIR)/gfx-pac-reuse-poc
PAC_SOURCES = poc/pac_main.m src/read_poc.m $(COMMON_SOURCES)
PAC_HEADERS = src/read_poc.h $(HEADERS)
READ_TARGET = $(BUILD_DIR)/gfx-read-poc
READ_SOURCES = poc/read_main.m src/read_poc.m $(COMMON_SOURCES)
READ_HEADERS = src/read_poc.h $(HEADERS)

CFLAGS = -Wall -Wextra -Werror -O2 -fobjc-arc \
	-I$(KEXTRW)/build/include -Isrc
LDFLAGS = -Wl,-dead_strip
FRAMEWORKS = -framework Metal -framework Foundation \
	-framework IOKit -framework CoreFoundation

.PHONY: all clean

all: $(TARGET) $(MICROPPL_TARGET) $(AUTH_TARGET) $(PAC_TARGET) \
	$(READ_TARGET)

$(BUILD_DIR):
	mkdir -p $@

$(TARGET): $(SOURCES) $(HEADERS) | $(BUILD_DIR)
	xcrun clang $(CFLAGS) $(LDFLAGS) $(SOURCES) \
		$(KEXTRW)/build/lib/libkextrw.a $(FRAMEWORKS) -o $@
	codesign --force --sign - --timestamp=none \
		--entitlements $(KEXTRW)/tests/entitlements.plist $@

$(MICROPPL_TARGET): $(MICROPPL_SOURCES) $(MICROPPL_HEADERS) | $(BUILD_DIR)
	xcrun clang $(CFLAGS) $(LDFLAGS) $(MICROPPL_SOURCES) \
		$(KEXTRW)/build/lib/libkextrw.a $(FRAMEWORKS) -o $@
	codesign --force --sign - --timestamp=none \
		--entitlements $(KEXTRW)/tests/entitlements.plist $@

$(AUTH_TARGET): $(AUTH_SOURCES) $(AUTH_HEADERS) | $(BUILD_DIR)
	xcrun clang $(CFLAGS) $(LDFLAGS) $(AUTH_SOURCES) \
		$(KEXTRW)/build/lib/libkextrw.a $(FRAMEWORKS) -o $@
	codesign --force --sign - --timestamp=none \
		--entitlements $(KEXTRW)/tests/entitlements.plist $@

$(PAC_TARGET): $(PAC_SOURCES) $(PAC_HEADERS) | $(BUILD_DIR)
	xcrun clang $(CFLAGS) $(LDFLAGS) $(PAC_SOURCES) \
		$(KEXTRW)/build/lib/libkextrw.a $(FRAMEWORKS) -o $@
	codesign --force --sign - --timestamp=none \
		--entitlements $(KEXTRW)/tests/entitlements.plist $@

$(READ_TARGET): $(READ_SOURCES) $(READ_HEADERS) | $(BUILD_DIR)
	xcrun clang $(CFLAGS) $(LDFLAGS) $(READ_SOURCES) \
		$(KEXTRW)/build/lib/libkextrw.a $(FRAMEWORKS) -o $@
	codesign --force --sign - --timestamp=none \
		--entitlements $(KEXTRW)/tests/entitlements.plist $@

clean:
	rm -f $(TARGET) $(MICROPPL_TARGET) $(AUTH_TARGET) $(PAC_TARGET) \
		$(READ_TARGET)
	rmdir $(BUILD_DIR) 2>/dev/null || true
