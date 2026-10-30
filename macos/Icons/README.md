# Ghostty-TC custom icon

`GhosttyTC-1024.png` is the 1024 × 1024 RGBA master with transparent exterior. `GhosttyTC.icns` and `GhosttyTC.iconset` contain all standard macOS representations. The original supplied artwork is preserved as `GhosttyTC-original.png`.

The built-in imagegen tool refined the supplied image using this prompt: “Create a NEW clean vector-style rendering of the attached icon, not a pixel copy. A smooth black rounded square with light gray border and the same blue ghost terminal emblem positioned upper left. A perfect smooth geometric rounded square outer silhouette, with absolutely NO white debris around edges. Transparent outside. 1024x1024. Preserve emblem design. Uniform gray border. Entire art inset 70px. Re-render from scratch so no rough pixels remain.” A final native geometric edge mask and resize produced the master.

`macos/build-tc.py` copies this ICNS into the packaged TC bundle before signing. Packaged TC builds omit the upstream Dock override plugin. The packaging helper recompiles the complete image catalog using the custom appiconset instead of the upstream Tahoe Icon Composer artwork, so Finder and Dock resolve the same icon. Upstream Ghostty assets are unchanged. Build/install using `python3 scripts/build-and-install.py`; do not replace the master with the upstream holographic icon.

To regenerate ICNS from the preserved iconset: `iconutil -c icns macos/Icons/GhosttyTC.iconset -o macos/Icons/GhosttyTC.icns`.
