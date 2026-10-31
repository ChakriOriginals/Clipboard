SHELL := /bin/bash
# ClipFlow build entry points. Requires Xcode 16+ and `brew install xcodegen`.
DERIVED := build/DerivedData
XCB := xcodebuild -project ClipFlow.xcodeproj -scheme ClipFlow -derivedDataPath $(DERIVED)

.PHONY: generate test test-core test-core-release test-app app run privacy-check clean

generate:
	xcodegen generate --quiet

test: test-core test-app privacy-check

test-core:
	cd Packages/ClipFlowCore && swift test

test-core-release:
	cd Packages/ClipFlowCore && swift test -c release

test-app: generate
	$(XCB) -destination 'platform=macOS,arch=$(shell uname -m)' test 2>&1 | grep -E '^(Test Case|Test Suite|Executed|.*error:|[*][*] TEST)' ; exit $${PIPESTATUS[0]}

app: generate
	$(XCB) -configuration Release build
	rm -rf build/ClipFlow.app && cp -R $(DERIVED)/Build/Products/Release/ClipFlow.app build/ClipFlow.app
	@echo "Built build/ClipFlow.app"

run: app
	open build/ClipFlow.app

privacy-check:
	scripts/privacy-check.sh

clean:
	rm -rf build Packages/ClipFlowCore/.build ClipFlow.xcodeproj
