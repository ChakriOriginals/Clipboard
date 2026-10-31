SHELL := /bin/bash
# Clipboard build entry points. Requires Xcode 16+ and `brew install xcodegen`.
DERIVED := build/DerivedData
XCB := xcodebuild -project Clipboard.xcodeproj -scheme Clipboard -derivedDataPath $(DERIVED)

.PHONY: generate test test-core test-core-release test-app app run privacy-check clean

generate:
	xcodegen generate --quiet

test: test-core test-app privacy-check

test-core:
	cd Packages/ClipboardCore && swift test

test-core-release:
	cd Packages/ClipboardCore && swift test -c release

test-app: generate
	$(XCB) -destination 'platform=macOS,arch=$(shell uname -m)' test 2>&1 | grep -E '(Test Case .*failed|Executed [0-9]+ tests|[*][*] TEST|[.]swift:[0-9]+:.*error:)' ; exit $${PIPESTATUS[0]}

app: generate
	$(XCB) -configuration Release CLANG_ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO build
	rm -rf build/Clipboard.app && cp -R $(DERIVED)/Build/Products/Release/Clipboard.app build/Clipboard.app
	@echo "Built build/Clipboard.app"

run: app
	open build/Clipboard.app

privacy-check:
	scripts/privacy-check.sh

clean:
	rm -rf build Packages/ClipboardCore/.build Clipboard.xcodeproj
