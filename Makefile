APP := build/Build/Products/Release/LiteMD.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: project build test run install clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project LiteMD.xcodeproj -scheme LiteMD -configuration Release -derivedDataPath build -quiet build

test: project
	xcodebuild -project LiteMD.xcodeproj -scheme LiteMDTests -derivedDataPath build -quiet test

run: build
	open $(APP)

# Copies the build to /Applications and registers the Quick Look extension.
install: build
	pkill -x LiteMD || true
	rm -rf /Applications/LiteMD.app
	cp -R $(APP) /Applications/
	# Forget the build-folder copy so Quick Look only uses the installed extension.
	$(LSREGISTER) -u $(APP)
	pluginkit -a /Applications/LiteMD.app/Contents/PlugIns/LiteMDQuickLook.appex
	qlmanage -r >/dev/null

clean:
	rm -rf build LiteMD.xcodeproj
