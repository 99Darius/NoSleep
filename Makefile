APP := NoSleep.app
BIN := /usr/local/bin/nosleep

.PHONY: build bundle install clean test

build:
	swift build -c release

test:
	swift test

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/NoSleepApp $(APP)/Contents/MacOS/NoSleepApp
	cp .build/release/nosleep    $(APP)/Contents/MacOS/nosleep
	cp Resources/Info.plist      $(APP)/Contents/Info.plist
	codesign --force --deep --sign - $(APP)

install: bundle
	@echo "Copy $(APP) to /Applications, then symlink the CLI:"
	@echo "  ln -sf /Applications/$(APP)/Contents/MacOS/nosleep $(BIN)"

clean:
	rm -rf .build $(APP)
