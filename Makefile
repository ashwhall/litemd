APP := build/Build/Products/Release/LiteMD.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Optional overrides, used by the release workflow: make zip VERSION=1.2.0 BUILD=42
VERSION_FLAGS := $(if $(VERSION),MARKETING_VERSION=$(VERSION)) $(if $(BUILD),CURRENT_PROJECT_VERSION=$(BUILD))

.PHONY: project build test zip run install clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project LiteMD.xcodeproj -scheme LiteMD -configuration Release -derivedDataPath build -quiet build $(VERSION_FLAGS)

# ditto keeps the bundle's code signatures intact, unlike zip.
zip: build
	ditto -c -k --keepParent $(APP) build/LiteMD.zip

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
