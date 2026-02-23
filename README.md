# Sigil

A macOS menu bar app for browsing, customizing, and copying SVG icons from multiple icon packs — all without leaving your workflow.

![macOS 15+](https://img.shields.io/badge/macOS-15.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Instant search** — fuzzy search across 8,000+ icons from four built-in packs
- **Bulk search** — comma or `+` separated terms to find multiple icons at once
- **Customization** — change stroke width, size, corner radius, and color with live preview
- **Custom icon packs** — import any SVG folder, GitHub repo, npm package, or `.zip` URL
- **Pack management** — reorder, hide/show, rename, recolor, or remove packs from Settings
- **One-click copy** — copies the raw SVG file or `<svg>` code string to clipboard
- **Bulk export** — select multiple icons and copy all at once

## Built-in Packs

| Pack | Icons |
|------|-------|
| [Lucide](https://lucide.dev) | ~1,400 |
| [Phosphor](https://phosphoricons.com) | ~1,200 |
| [Radix](https://radix-ui.com/icons) | ~300 |
| [Tabler](https://tabler.io/icons) | ~5,000 |

## Importing Custom Packs

Open **Settings** (right-click the menu bar icon → Settings…) and use any of:

- **Drop zone** — drag a folder of `.svg` files onto the drop target
- **Browse** — pick a folder via the system file picker
- **URL import** — paste any of:
  - GitHub: `github.com/owner/repo` or `github.com/owner/repo/tree/main/src/icons`
  - npm: package name like `heroicons` or `@tabler/icons`
  - Direct `.zip` URL

Color normalization (hardcoded `#000` → `currentColor`) is applied automatically so the color picker works on every pack.

## Requirements

- macOS 15.0 Sequoia or later
- No external dependencies — entirely self-contained

## Building

```bash
# Debug (development)
xcodebuild -scheme Sigil -configuration Debug build

# Release + DMG (distribution)
./scripts/make-dmg.sh
```

The DMG script requires your Development Team to be configured in Xcode for code signing. Edit `scripts/make-dmg.sh` to set `TEAM_ID` before running.

## Project Structure

```
Sigil/
├── App/
│   └── AppDelegate.swift       # NSStatusItem, popover, settings window
├── Models/
│   ├── IconPack.swift          # Pack struct (built-in + custom)
│   ├── IconModel.swift         # Single icon model
│   └── IconCustomization.swift # Stroke/size/color customization state
├── Services/
│   ├── IconStore.swift         # SVG loading + fuzzy search (@Observable)
│   ├── CustomPackStore.swift   # Custom pack persistence + remote import (@Observable)
│   └── PackImporter.swift      # npm / GitHub Git Trees / ZIP resolvers
├── Views/
│   ├── ContentView.swift       # Main popover UI
│   ├── SettingsView.swift      # Settings window
│   ├── PackFilterBar.swift     # Pack filter chips
│   ├── IconGridView.swift      # Scrollable icon grid
│   ├── IconCellView.swift      # Individual icon cell
│   └── ...
└── Resources/
    └── Icons/                  # Bundled SVG files (lucide/, phosphor/, radix/, tabler/)
```

## License

MIT — see [LICENSE](LICENSE) for details.
