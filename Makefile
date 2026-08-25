APP = dist/Hubby.app
BIN = .build/release/Hubby

.PHONY: app build test clean run

build:
	swift build

test:
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Hubby
	cp packaging/Info.plist $(APP)/Contents/Info.plist
	cp packaging/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns 2>/dev/null || true
	@echo "Built $(APP)"

run: app
	open $(APP)

clean:
	rm -rf .build dist
