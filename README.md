# Docklet — one app with Dock widgets

Docklet 0.5.1 runs music, timer, stocks, weather, calendar, reminders, clock and private Quick Notes in **one process**. It no longer packages, installs or launches one app per widget.

## Use

Open `~/Applications/Docklet.app` (the `../Docklet.app` workspace link also opens the installed copy). On the Widgets page, click **Enable Accessibility**, then turn on **Docklet** in macOS System Settings → Privacy & Security → Accessibility. Widgets attach automatically after access is available.

Use **Add widget** to add a feature, then adjust its individual width beside the actual-size preview. Right-click a Dock tile for quick actions, width choices and removal. Timer controls include focus and break presets, progress, optional completion sound, extra time, and stopwatch lap splits. Stocks includes a 12-symbol watchlist, company search, daily/weekly/monthly/yearly charts, hover inspection, range lows/highs and saved quotes for offline viewing. Search for “Bitcoin” to choose the Bitcoin USD market symbol, BTC-USD; ticker BTC is a different listing. Quick Notes saves locally as you type. Weather supports Celsius or Fahrenheit. Save named Dock layouts, choose a Focus, Markets or Minimal preset, and undo layout changes. All controls and data sources belong to the same Docklet process.

Size & Appearance changes widget text, rounded corners, and the size/height of the macOS Dock. Apple's Dock can shrink icons to fit the screen. Width choices reserve one to five icon spaces; a crowded Dock therefore gives each widget less physical room.

Use the menu bar icon to reopen settings or controls. Closing settings leaves widgets running. Quit stops the widgets and removes their reserved spaces. Show Dock Widgets pauses/resumes integration. Repair Placement rebuilds reserved spaces if they have been moved manually.

## Dock integration

Apple's public app Dock tile API is square. Docklet instead reserves native Dock spacer tiles beside its one app icon, then draws interactive panels over those measured spaces. Accessibility is used only to read Dock item geometry; it does not read the contents of other applications. Panels follow Dock movement and magnification and are hidden when their measured positions are off screen or cannot be safely established.

The renderer verifies the available area and avoids placing wide panels over another application's icon. Layout changes briefly reload the system Dock. Before each change the pinned-app array is backed up under `~/Library/Application Support/Docklet/Dock Backups`. Existing unrelated Dock entries are preserved. macOS discards custom spacer identifiers, so the app records the number of reserved spaces immediately after its own anchor and uses that bounded range for resizing and cleanup. Rapid layout edits are grouped into one reload.

This reproduces the intended single-app interaction. It is our implementation; Dockspace's internal implementation is not documented on its site. Live alignment requires Accessibility access and depends on the Dock's accessibility geometry. We do not bypass macOS permissions. If alignment is unavailable, controls remain usable from settings/menu bar, and no approximate overlay is shown.

## Data

Stocks: Yahoo Finance watchlist with company search, daily changes, cached quotes and 1D/1W/1M/1Y charts; data may be delayed or temporarily unavailable. Weather: user-selected city and four-day forecast from Open-Meteo, refreshed every 15 minutes. Music: Apple Music/Spotify after explicit connection. Calendar/Reminders: explicit EventKit access; upcoming events, incomplete reminders, adding and completing reminders. Timer: persisted countdown/stopwatch, pause/resume/reset. Clock: local time/date and 12/24-hour preference.

## Build and checks

```sh
./check-layout.sh
./check-features.sh
./package-app.sh
python3 install-app.py
open ~/Applications/Docklet.app
```

Requires macOS 14+, Swift 5.10+ and command line tools. No third-party dependencies. Packaging creates exactly one application bundle. Checks cover Dock preference preservation, safe geometry allocation, local timer state, watchlist and layout persistence, temperature conversion, stock search results and chart ranges; Dock layout checks do not edit the real Dock. Live Dock alignment must be checked after Accessibility is granted.

Personal builds now use a persistent signing certificate in a dedicated local keychain under `~/Library/Application Support/Docklet/Signing`. Its private credentials stay outside the source tree. Signing temporarily includes that keychain in the search list, then restores the original list. No certificate trust settings are changed. The designated requirement binds the app identifier to that certificate, keeping its identity consistent across updates. The first switch from the previous ad-hoc build requires a fresh Accessibility approval. If you have a macOS signing certificate, set `DOCKLET_SIGN_IDENTITY` when packaging instead.

The installer places the app outside synchronized Documents, preserves other native Dock entries, updates the single Docklet entry, removes its stale file bookmark, and links the workspace app path to the installed copy. Previous copies are archived locally under `~/Library/Application Support/Docklet/Previous Builds`.

Widget shortcuts use `docklet://widget/add/stocks`, `docklet://widget/remove/stocks`, `docklet://widget/size/stocks/3`, and `docklet://widget/open/stocks` (replace stocks with another widget name). These call the same actions as settings. Dock alignment diagnostics are saved to `~/Library/Application Support/Docklet/dock-diagnostics.json`; launch with `--diagnostics` to save tile images. The stock popover uses an opaque scrollable surface sized to the display and floats above the Dock widgets while open.

The old per-widget applications have been retired from this personal installation. Their copies are archived under `~/Library/Application Support/Docklet/Retired Widget Apps`, and their prior Dock entries are backed up with the other Dock snapshots.
