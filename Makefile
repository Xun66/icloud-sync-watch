APP_NAME := iCloud Sync Watch
EXECUTABLE_NAME := iCloudSyncWatch
VERSION ?= 0.1.0
BUILD_CONFIGURATION := release
DIST_DIR := dist
APP_DIR := $(DIST_DIR)/$(APP_NAME).app
ZIP_PATH := $(DIST_DIR)/$(APP_NAME)-$(VERSION).zip
ARM64_BIN := .build/arm64-apple-macosx/$(BUILD_CONFIGURATION)/$(EXECUTABLE_NAME)
X86_64_BIN := .build/x86_64-apple-macosx/$(BUILD_CONFIGURATION)/$(EXECUTABLE_NAME)
RESOURCE_BUNDLE := .build/arm64-apple-macosx/$(BUILD_CONFIGURATION)/$(EXECUTABLE_NAME)_$(EXECUTABLE_NAME).bundle
APP_ICON_SOURCE := Packaging/AppIcon.svg
APP_ICON_PATH := Packaging/AppIcon.icns

.PHONY: test build build-arm64 build-x86_64 build-icon package clean

test:
	swift test

build: build-arm64 build-x86_64

build-arm64:
	swift build -c $(BUILD_CONFIGURATION) --arch arm64

build-x86_64:
	swift build -c $(BUILD_CONFIGURATION) --arch x86_64

build-icon:
	rm -rf /tmp/$(EXECUTABLE_NAME).iconset /tmp/$(EXECUTABLE_NAME)-icon.png "$(APP_ICON_PATH)"
	qlmanage -t -s 1024 -o /tmp "$(APP_ICON_SOURCE)" >/dev/null
	mv /tmp/AppIcon.svg.png /tmp/$(EXECUTABLE_NAME)-icon.png
	mkdir -p /tmp/$(EXECUTABLE_NAME).iconset
	sips -z 16 16 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_16x16.png >/dev/null
	sips -z 32 32 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_16x16@2x.png >/dev/null
	sips -z 32 32 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_32x32.png >/dev/null
	sips -z 64 64 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_32x32@2x.png >/dev/null
	sips -z 128 128 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_128x128.png >/dev/null
	sips -z 256 256 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_256x256.png >/dev/null
	sips -z 512 512 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512 /tmp/$(EXECUTABLE_NAME)-icon.png --out /tmp/$(EXECUTABLE_NAME).iconset/icon_512x512.png >/dev/null
	cp /tmp/$(EXECUTABLE_NAME)-icon.png /tmp/$(EXECUTABLE_NAME).iconset/icon_512x512@2x.png
	iconutil -c icns /tmp/$(EXECUTABLE_NAME).iconset -o "$(APP_ICON_PATH)"

package: test build build-icon
	rm -rf "$(APP_DIR)" "$(ZIP_PATH)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp Packaging/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp Packaging/PkgInfo "$(APP_DIR)/Contents/PkgInfo"
	cp "$(APP_ICON_PATH)" "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_DIR)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP_DIR)/Contents/Info.plist"
	lipo -create "$(ARM64_BIN)" "$(X86_64_BIN)" -output "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE_NAME)"
	cp -R "$(RESOURCE_BUNDLE)" "$(APP_DIR)/Contents/Resources/$(EXECUTABLE_NAME)_$(EXECUTABLE_NAME).bundle"
	chmod +x "$(APP_DIR)/Contents/MacOS/$(EXECUTABLE_NAME)"
	codesign --force --sign - --timestamp=none "$(APP_DIR)"
	ditto -c -k --keepParent "$(APP_DIR)" "$(ZIP_PATH)"

clean:
	rm -rf .build "$(DIST_DIR)"
