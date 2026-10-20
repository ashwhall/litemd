# LiteMD

<sub>🤖 Mostly vibe-coded with an AI assistant. It does the job, but expect the odd rough edge.</sub>

A tiny, fast markdown viewer and editor for macOS, with space-bar previews in Finder.

- GitHub Flavored Markdown: tables, task lists, strikethrough, autolinks, footnotes
- Syntax-highlighted code blocks
- Switch between reading and editing the markdown source with <kbd>⌘E</kbd>
- Tick task-list checkboxes straight from the rendered view
- Save with <kbd>⌘S</kbd>, with a save or discard prompt when closing
- Reloads automatically when the file changes on disk
- Light, dark or system appearance, remembered between launches
- An "Edit in…" button that opens the file in the editor of your choice
- Quick Look: select a `.md` file in Finder and press space

Requires macOS 14 or later on Apple Silicon.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/ashwhall/litemd/main/install.sh | sh
```

Run the same command again to update.

## Build from source

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make build     # build into build/
make run       # build and launch
make install   # build, copy to /Applications and register Quick Look
```

Builds are ad-hoc signed by default, so no Apple Developer account is needed. To sign with your own certificate, create `Config/Signing.local.xcconfig` (gitignored). See `Config/Base.xcconfig` for an example.

If space-bar preview doesn't show the rendered file, run:

```sh
pluginkit -a /Applications/LiteMD.app/Contents/PlugIns/LiteMDQuickLook.appex
qlmanage -r
```
