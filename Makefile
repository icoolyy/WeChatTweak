.PHONY: build test clean

build::
	swift build -c release --arch arm64 --arch x86_64
	mkdir -p dist
	cp -f .build/apple/Products/Release/wechattweak dist/wechattweak
	cp -f config.json dist/config.json

test:
	swift build
	swift run core-tests
	python3 tools/test_cli.py .build/debug/wechattweak

clean::
	rm -rf .build
	rm -f wechattweak
	rm -rf dist
