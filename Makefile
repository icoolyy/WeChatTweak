.PHONY: build test clean
SWIFT ?= swift
ARCHS ?= arm64 x86_64

build::
	mkdir -p dist
	@for arch in $(ARCHS); do \
		$(SWIFT) build -c release --arch $$arch || exit $$?; \
	done
	lipo -create $(foreach arch,$(ARCHS),.build/$(arch)-apple-macosx/release/wechattweak) -output dist/wechattweak
	cp -f config.json dist/config.json
	$(MAKE) native

.PHONY: native
native:
	mkdir -p dist
	clang++ -std=c++17 -arch arm64 -mmacosx-version-min=12.0 -fobjc-arc -dynamiclib -framework Foundation -framework ImageIO -framework CoreGraphics -Wall -Wextra -Werror \
		Native/Bridge/Protocol.mm Native/Bridge/Credentials.mm Native/Bridge/Server.mm Native/Bridge/NativeOperation.mm Native/Bridge/Host.mm \
		Native/269602/Adapter.mm Native/269602/ContactCache.mm Native/269602/ContactSearch.mm Native/269602/AvatarCache.mm Native/269602/AvatarFile.mm Native/269602/AvatarNative.mm Native/269602/AvatarStore.mm Native/269602/AvatarDownload.mm -o dist/WeChatTweakBridge.dylib
	codesign --force --sign - dist/WeChatTweakBridge.dylib

test:
	$(SWIFT) build
	$(SWIFT) run core-tests
	python3 tools/test_cli.py .build/debug/wechattweak
	python3 tools/test_native.py
	python3 tools/test_bridge_transport.py

clean::
	rm -rf .build
	rm -f wechattweak
	rm -rf dist
