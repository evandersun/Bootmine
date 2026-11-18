.PHONY: all clean build_clean

APP_VERSION := $(shell cat ../BaseBin/_external/basebin/.version)-$(shell cat ../BaseBin/_external/basebin/.version-roothide)

all: Bootmine.ipa

Bootmine.ipa: build/Build/Products/Debug-iphoneos/Bootmine.app
	@echo Ad-Hoc signing Bootmine
	xattr -rc build/Build/Products/Debug-iphoneos/Bootmine.app
	ldid -SBootmine/Bootmine.entitlements build/Build/Products/Debug-iphoneos/Bootmine.app/Bootmine
	ldid -s build/Build/Products/Debug-iphoneos/Bootmine.app
	rm -rf Payload Bootmine.ipa
	mkdir Payload
	cp -r build/Build/Products/Debug-iphoneos/Bootmine.app Payload/Bootmine.app
	zip -Ar Bootmine.ipa Payload
	rm -rf Payload
	rm -rf Bootmine.tipa
	cp Bootmine.ipa Bootmine.tipa
	mv Bootmine.ipa Bootmine-roothide-"$(APP_VERSION)".ipa
	mv Bootmine.tipa Bootmine-roothide-"$(APP_VERSION)".tipa

ifeq ($(NIGHTLY), 1)
build/Build/Products/Debug-iphoneos/Bootmine.app: FORCE
	xcodebuild -scheme Bootmine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO GCC_PREPROCESSOR_DEFINITIONS='NIGHTLY=1 COMMIT_HASH=\"$(COMMIT_HASH)\"'
else
build/Build/Products/Debug-iphoneos/Bootmine.app: FORCE
	xcodebuild -scheme Bootmine -derivedDataPath build -destination 'generic/platform=iOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
endif
	touch build/Build/Products/Debug-iphoneos/Bootmine.app/Bootmine.roothide
	cp -a Bootmine/Resources/*.deb build/Build/Products/Debug-iphoneos/Bootmine.app/
	cp ../BaseBin/.build/libroothider.dylib build/Build/Products/Debug-iphoneos/Bootmine.app/
	plutil -replace CFBundleIdentifier -string "com.opa334.Dopamine-roothide" build/Build/Products/Debug-iphoneos/Bootmine.app/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(APP_VERSION)" build/Build/Products/Debug-iphoneos/Bootmine.app/Info.plist
# ifeq ($(PALEHIDE), 1)
	make -C Bootmine/Exploits/palera1n package
	cp -a Bootmine/Exploits/palera1n/.framework build/Build/Products/Debug-iphoneos/Bootmine.app/Frameworks/palera1n.framework
# endif


clean:
	make -C Bootmine/Exploits/palera1n clean
	rm -rf build Payload Bootmine.ipa Bootmine.tipa

build_clean:
	rm -rf Payload build

FORCE: ;