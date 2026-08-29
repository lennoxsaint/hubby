APP = dist/Hubby.app
BIN = .build/release/Hubby
IDENTITY = Developer ID Application: Lennox Saint (XSL2TFT3P9)
NOTARY_KEY = $(HOME)/.appstoreconnect/private_keys/AuthKey_K6GKYTJTBR.p8
NOTARY_KEY_ID = K6GKYTJTBR
# Single source of truth for the version: the VERSION file. The app target
# stamps it into the bundle's Info.plist so the app never misreports itself
# (v1.0.0 shipped claiming 0.1.0 — hardcoded plist vs hardcoded Makefile).
VERSION = $(shell cat VERSION)
BUILD_NUMBER = $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
DMG = dist/Hubby-$(VERSION).dmg
ZIP = dist/Hubby-$(VERSION).zip

.PHONY: app build test clean run icon sign dmg notarize release

build:
	swift build

test:
	swift test

icon:
	swift packaging/make-icon.swift /tmp/hubby-icon.iconset
	iconutil -c icns /tmp/hubby-icon.iconset -o packaging/AppIcon.icns
	rm -rf /tmp/hubby-icon.iconset

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Hubby
	cp packaging/Info.plist $(APP)/Contents/Info.plist
	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleShortVersionString $(VERSION)" \
		-c "Set :CFBundleVersion $(BUILD_NUMBER)" \
		$(APP)/Contents/Info.plist
	cp packaging/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@echo "Built $(APP)"

run: app
	open $(APP)

sign: app
	codesign --force --deep --options runtime --timestamp \
		--entitlements packaging/Hubby.entitlements \
		--sign "$(IDENTITY)" $(APP)
	codesign --verify --deep --strict --verbose=2 $(APP)

dmg: sign
	rm -rf dist/dmg-root $(DMG)
	mkdir -p dist/dmg-root
	cp -R $(APP) dist/dmg-root/
	ln -s /Applications dist/dmg-root/Applications
	hdiutil create -volname "Hubby" -srcfolder dist/dmg-root -ov -format UDZO $(DMG)
	rm -rf dist/dmg-root
	@echo "Built $(DMG)"

# ISSUER set from the App Store Connect Integrations page:
#   make notarize ISSUER=<uuid>
notarize: dmg
	xcrun notarytool submit $(DMG) \
		--key $(NOTARY_KEY) --key-id $(NOTARY_KEY_ID) --issuer "$(ISSUER)" --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)

zip: sign
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

release: notarize zip
	shasum -a 256 $(DMG) $(ZIP) > dist/checksums.txt
	@echo "Ready: $(DMG) $(ZIP)"

clean:
	rm -rf .build dist
