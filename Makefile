PROJECT   := Clipbit.xcodeproj
SCHEME    := Clipbit
DERIVED   := build
CONFIG    ?= Release
APP       := $(DERIVED)/Build/Products/$(CONFIG)/Clipbit.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -quiet

.PHONY: generate build run test clean

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

clean:
	rm -rf $(DERIVED)
