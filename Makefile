APP := NoSleep.app
BIN := /usr/local/bin/nosleep

.PHONY: build bundle install clean test

ARM := .build/arm64-apple-macosx/release
X86 := .build/x86_64-apple-macosx/release

build:
	swift build -c release

# Universal (arm64 + x86_64) binaries. `swift build --arch a --arch b` needs
# Xcode's xcbuild, which isn't installed here, so build each slice with an
# explicit triple and lipo them together. The installer declares support for
# both architectures — shipping an arm64-only binary made the pkg install
# "successfully" on Intel Macs and then never launch.
universal:
	swift build -c release --triple arm64-apple-macosx13.0
	swift build -c release --triple x86_64-apple-macosx13.0

test:
	swift test

bundle: universal
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	lipo -create $(ARM)/NoSleepApp $(X86)/NoSleepApp -output $(APP)/Contents/MacOS/NoSleepApp
	lipo -create $(ARM)/nosleep    $(X86)/nosleep    -output $(APP)/Contents/MacOS/nosleep
	@lipo -archs $(APP)/Contents/MacOS/NoSleepApp | grep -q x86_64 || \
		{ echo "FATAL: app binary is not universal"; exit 1; }
	@lipo -archs $(APP)/Contents/MacOS/nosleep | grep -q arm64 || \
		{ echo "FATAL: cli binary is not universal"; exit 1; }
	cp Resources/Info.plist      $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns    $(APP)/Contents/Resources/AppIcon.icns
	# Bundle the KeyboardShortcuts SPM resource bundle so Bundle.module resolves
	# at runtime instead of fatalError-ing. ditto (not cp -R): the bundle's .lproj
	# dirs are read-only, which trips up cp.
	ditto $(ARM)/KeyboardShortcuts_KeyboardShortcuts.bundle $(APP)/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle
	codesign --force --deep --sign - $(APP)

install: bundle
	@echo "Copy $(APP) to /Applications, then symlink the CLI:"
	@echo "  ln -sf /Applications/$(APP)/Contents/MacOS/nosleep $(BIN)"

clean:
	rm -rf .build $(APP)
