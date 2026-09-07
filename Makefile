PROJECT   := Clipbit.xcodeproj
SCHEME    := Clipbit
DERIVED   := build
CONFIG    ?= Release
APP       := $(DERIVED)/Build/Products/$(CONFIG)/ClipBit.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -quiet

.PHONY: generate build run test release release-dry clean

# Regenerate the project from project.yml (needed after adding/removing source files).
generate:
	xcodegen generate

$(PROJECT): project.yml
	xcodegen generate

build: $(PROJECT)
	$(XCODEBUILD) -configuration $(CONFIG) build

run: build
	open $(APP)

test: $(PROJECT)
	$(XCODEBUILD) -configuration Debug test

# Archive, export, and upload to App Store Connect (see scripts/release-macos.sh).
release:
	scripts/release-macos.sh

release-dry:
	scripts/release-macos.sh --dry-run

clean:
	rm -rf $(DERIVED)
