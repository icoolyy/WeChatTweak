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

test:
	$(SWIFT) build
	$(SWIFT) run core-tests
	python3 tools/test_cli.py .build/debug/wechattweak

clean::
	rm -rf .build
	rm -f wechattweak
	rm -rf dist
