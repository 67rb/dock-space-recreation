# Docklet upgrade · stock tracking focus

The user asked to make the single app substantially better, then chose stocks and market tracking as the focus. Preserve their real Dock, current ticker list, four live tiles, one signed app process, and stable Accessibility identity.

Implemented in 0.5.1:
- Watchlist up to 12 tickers, saved quotes, company search, ticker selection, and deletion with a safe final-entry guard.
- Live 1D, 1W, 1M and 1Y price charts; hover inspection, range labels, min/max, refresh and offline snapshots.
- Safe Bitcoin search distinguishing the Bitcoin USD market symbol from the unrelated BTC listing.
- Fixed-height, scrolling stock popover with opaque background and a floating window level above the Dock widgets. Smaller chart and intact quote labels at actual Dock tile width.
- Focus/break presets, countdown extension, finish sound control, durable focus-session count, stopwatch lap splits and reset.
- Local autosaving Quick Notes widget and keyboard shortcut.
- Named saved layouts, Focus/Markets/Minimal presets, delete undo, layout undo, quick tile menu controls.
- Actual-sized setting previews; concise collapsed Add gallery and layout sections.
- Celsius/Fahrenheit weather, forecast caching, and city-change stale-data protection.

Checks: `./check-features.sh`, `./check-layout.sh`, release build; confirm build/installation with existing persistent signing certificate, existing app permission, unchanged unrelated Dock entries, visible actual Dock panels, company search for Bitcoin, and the final scrollable elevated Stocks controls. Then add a dated factual result to `verification/upgrade/` and mark the goal complete only after evidence.
