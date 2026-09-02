# Guda

A comprehensive **bag and bank management addon** for **World of Warcraft 1.12.1**, fully compatible with **Turtle WoW**.

Guda provides a modern, unified bag/bank experience with multi-character support, sorting, item tracking, and quality-of-life tools.

---

## 📦 Features

### 🎒 Bag Management

- **Unified Bag View** – All bags displayed in one window
- **Category View** – Group items by category for easier organization
- **Recently Looted** – A category that surfaces items you just looted or received
  (default 10-minute window, matching Turtle WoW's BoP raid-loot trade grace period)
- **BoP / BoE categories** – Bind-on-Pickup and Bind-on-Equip gear are split into
  their own categories so freshly looted raid gear is easy to spot
- **Smart Sorting** – Sort by quality, name, or item type
- **Search Box** – Quickly find items; the magnifying-glass icon sits left of the
  utility buttons (Pick Lock / Disenchant / Sort) and stays available even when
  the search bar is hidden
- **Quality Filter Bar** – Filter items by rarity with one-click quality buttons (above the search bar; left-click to toggle a quality, right-click to clear)
- **Quality Borders** – Items are visually color-coded based on rarity

### 🏦 Bank Management

- **Remote Bank Viewing** – View cached bank contents from anywhere
- **One-Click Sorting** – Organize your bank easily
- **Category View** – Group bank items by category
- **Persistent Storage** – Bank data saved between sessions

### 📊 Tracked Item Bar

- **Item Tracking** – Alt + Left-Click on any bag item to track it
- **Stack Display** – Shows tracked items as a single stack with total count
- **Farm Counter** – Displays how many items you currently have in your bags
- **Grinding Helper** – Perfect for tracking materials while farming
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 📜 Quest Item Bar

- **Quest Item Display** – Shows usable quest items in up to 2 dedicated bars
- **Quick Swap** – Hover over a quest item bar slot to see available quest items
- **One-Click Replace** – Click on a popup item to swap it into the bar slot
- **Keybindable** – Set custom keybindings for quick quest item use
- **Draggable** – Shift + Left-Click to drag the bar anywhere on screen

### 👥 Multi-Character Support

- **Cross-Character Viewing** – View bags & banks of any character
- **Money Tracking** – See total gold across all characters, grouped by account and realm
- **Character Selector** – Switch characters quickly
- **Faction Filtering** – Shows only characters from the same faction
- **Global Item Counting** – Item totals across all characters, including:
    - Bags
    - Banks
    - Equipped items
    - Tooltip breakdown per character
- **Character Management** – Right-click the money frame to show/hide characters or remove deleted ones

### 💰 Money Display

- **Current Character Money**
- **Total Money Across All Characters**
- **Per-Character Overview** in the selector

### 🔗 Cross-Account Sharing (Optional)

Share character data (gold, bags, bank, mail, equipped items) between different WoW accounts on the same PC. Requires the companion [GudaIO](https://github.com/vatichild/GudaIO) DLL.

**How it works:**
- GudaIO runs once when the game starts, before the login screen appears
- It reads each account's saved character data from `WTF/Account/*/SavedVariables/Guda.lua`
- It merges them into a single file (`GudaShared.lua`) that the addon loads automatically
- Characters from other accounts appear in the gold tooltip, inventory counts, and character dropdowns, separated by account
- The DLL does nothing after startup — no hooks, no background threads, no memory patches

**Setup:**
1. Download `GudaIO.dll` from [GudaIO releases](https://github.com/vatichild/GudaIO/releases)
2. Place it in your TurtleWoW folder (next to `WoW.exe`)
3. Add `GudaIO.dll` on a new line in `dlls.txt`
4. Log into each account at least once and log out properly
5. Restart the game — all accounts will see each other's characters

Without the DLL, the addon works normally with single-account data only. No errors or crashes.

---

## 📝 Slash Commands

| Command | Description |
|---------|-------------|
| `/guda` or `/gn` | Toggle bags |
| `/guda bank` | Toggle bank view |
| `/guda sort` | Sort your bags |
| `/guda sortbank` | Sort your bank (must be at bank) |
| `/guda debug` | Toggle debug mode |
| `/guda cleanup` | Remove characters not seen in 90 days |
| `/guda help` | Show help |

---

## 🔌 Public API (for other addons)

Guda exposes item-location helpers on the global `GudaBag` namespace, so other
addons (e.g. Automatonex 自动喊话) can locate items in bags and build item links
without manually tracking bag/slot numbers.

| Function | Description |
|----------|-------------|
| `GudaBag.FindItemInBags(itemIDOrLink, includeBank)` | Scan bags (and optionally bank) for an item by its numeric item ID, a link containing `item:<id>`, **or an item name** (case-insensitive substring match). Names are read from the item link's display name, so it works even before `GetItemInfo` caches an item. Returns `bagID, slotID, itemLink`, or `nil, nil, nil` if not found. |
| `GudaBag.GetItemLinkForShout(itemIDOrLink, includeBank)` | Convenience wrapper: returns just the item link for the item, or `nil` if not found. |
| `GudaBag.GetItemLinkAt(bagID, slotID)` | Returns the item link at a specific bag/slot (alias of `GetContainerItemLink`). |

Example for AutoShout-style usage:

```lua
-- Find where the item is, then insert its link into a message
local bag, slot, link = GudaBag.FindItemInBags(6948)          -- Hearthstone (by ID)
local link2        = GudaBag.GetItemLinkForShout("item:6948:0:0:0")  -- by link
local link3        = GudaBag.GetItemLinkForShout("烤鹌鹑")   -- by name
local link4        = GudaBag.GetItemLinkAt(bag, slot)
```

---

## 🚀 How to Use

### Basic Usage

1. Press **B** or type `/guda` to open your bags
2. Click **Characters** to switch characters
3. Click **Bank** to view your cached bank
4. Click **Sort** to organize your bags

### Sorting

- **Sort Bags**: Press **Sort** (left-click) or use `/guda sort`
- **Sort Bank**: Use **Sort Bank** (left-click) or `/guda sortbank`
- **Direction**: left-click sorts **ascending**, right-click sorts **descending** (OneBag-style)
- **Performance**: while a sort is running, the item grid is temporarily hidden (the window shell
  stays visible), which dramatically improves frame rate during the batch item moves. The grid is
  rebuilt automatically when the sort finishes.

### Search

- When "Show Search Bar" is **checked**, the search bar is always visible in both bags and bank.
- When it is **unchecked**, the search bar is hidden by default and a **magnifying-glass icon**
  appears on the bag *and* bank header; click it to expand the search bar (it collapses again
  when you click away or press Escape while empty).

### Quality Filter

- The quality filter bar sits directly above the search box in the bag view
- **Left-click** a quality button to filter the bag to that rarity (or clear it if already active)
- **Right-click** any quality button to clear the filter
- Hover over a button to see the item count for that rarity
- The "Common/Poor" button matches both Common (white) and Poor (gray) items, matching OneBag behavior

### Category View

- Toggle category view in bags or bank to group items by type
- Easily find items organized by their category

### Tracked Item Bar

1. Open your bags
2. Hold **Alt** and **Left-Click** on any item to start tracking it
3. The item appears in the Tracked Item Bar with total count
4. Use **Shift + Left-Click** on the bar to drag it to your preferred location

![Tracked Item Bar](https://github.com/user-attachments/assets/81a2a86f-f35e-4437-ae89-906ade98716d)

### Quest Item Bar

1. Quest items automatically appear in the Quest Item Bar
2. Set keybindings via **Esc → Key Bindings → Guda** for quick use
3. Hover over a bar slot to see other available quest items
4. Click a popup item to swap it into that slot
5. Use **Shift + Left-Click** on the bar to drag it to your preferred location

![Quest Item Bar](https://i.imgur.com/orMsS06.png)
---

## 🧠 Internal Systems

### 🔍 Bag Scanner

- Scans all bags at login
- Updates when looting, moving, or modifying items
- Stores item details (count, quality, name, link, etc.)

### 🏦 Bank Scanner

- Scans on bank open
- Saves snapshot for offline viewing
- Updates live while the bank is open

### 💰 Money Tracker

- Tracks money changes in real time
- Displays per-character, current character, and total money

### 🗄️ Data Storage

| Variable | Description |
|----------|-------------|
| `Guda_DB` | Global data: bag & bank contents, character money, timestamps, tracked items |
| `Guda_CharDB` | Per-character UI settings: bar positions, tracked item selections |

---


## ⚠️ Known Limitations

| Area | Limitation |
|------|------------|
| Sorting | Advanced sorting requires handling bag restrictions (soul bags, profession bags). Locked and soulbound items need special handling. |
| Bank Access | Must open the bank at least once to cache contents |
| Faction Restriction | Only shows characters from the same faction |

---

## 🖼️ Screenshots

| Guda Settings | Bag Single View                          | Bag Category View                  | Bank View                                    |
|---------------|------------------------------------------|------------------------------------|----------------------------------------------|
| ![Settings](https://github.com/user-attachments/assets/9ab1b985-1280-4c14-a733-3a1fffdaa7e4) | ![Bags](https://github.com/user-attachments/assets/1150de97-7db7-4267-b1cd-99c6267c4669) | ![Category](https://github.com/user-attachments/assets/825ada16-da49-400e-8b1b-4ae203786f0f) | ![Bank](https://github.com/user-attachments/assets/7a198526-85c8-4309-abeb-c2031645d828)     |

---

## 🐞 Common Issues

### Cannot open bags using B

Set the keybinding: **Esc → Key Bindings → Guda → Toggle Bags**

![Keybindings Fix](https://i.imgur.com/IJv36Lg.png)

---

## 🔧 Recent Fixes

- **Update() split into UpdateGrid() + view-agnostic tail (SUCC-bag inspired)** –
  `BagFrame:Update()`/`BankFrame:Update()` used to rerun money, hearthstone,
  utility-button scans (including the full-bag Thieves' Tools scan), bag-slot
  info and footer layout on every rebuild. The grid rebuild now lives in
  `UpdateGrid()`; the view-agnostic tail only runs in `Update()`. Hot paths
  were switched accordingly:
  - Ctrl+right-click item lock / set protection, Alt+right-click slot pin and
    Alt+left-click tracking now refresh only the affected icons on all visible
    buttons (`RefreshItemMarkers`) instead of rebuilding bag + bank.
  - Drag-drop placements (equipment into bag, drop onto empty slot) schedule a
    debounced fallback redraw (`ScheduleGridUpdate`) that is cancelled when the
    BAG_UPDATE incremental path handles the change – no more double rebuilds in
    the same frame.
  - Category reassignment drops still rebuild synchronously but only the grid
    (`UpdateGrid`).
  - Keyring / soul-bag toggles and right-click bag hiding rebuild only the
    grid.
  - Un-tracking an item (TrackedItemBar Alt+click) only refreshes the tracking
    checkmarks.
- **Item lock changes no longer trigger a full bag/bank rebuild (borrowed from
  SUCC-bag)** – In single view, any ITEM_LOCK_CHANGED (right-clicking an item
  into a mail attachment, trading, selling) scheduled a full `Update()`
  rebuild of the bag/bank layout just to grey out one icon. Both views now use
  the lightweight `UpdateLockStates()` pass (debounced), which only refreshes
  the desaturated state of each visible button – the same approach SUCC-bag
  uses (`FrameUpdateLock`), keeping the layout untouched.
- **No more hitch when attaching an item to mail** – Right-clicking an item
  into a mail attachment fires BAG_UPDATE, which invalidated the per-slot
  charge cache; the following full bag redraw then synchronously scanned the
  tooltip of every slot to rebuild it (the cache also never stored "no
  charges" results, so every charge-less item was re-scanned on every redraw),
  producing a visible freeze. Charge lookups in the layout path are now
  cache-only (never scanning tooltips), charge caches store a sentinel for
  scanned-but-chargeless items, and the cache is warmed in the background by
  CacheWarmer/tooltip hover like the other detection caches.
- **Auto Fill Rows now stays applied during a bag session** – The row-filling
  reorder (autoFillRows) was only computed on the first render after opening
  the bag; any later `Update()` (e.g. clicking an item or opening settings)
  rebuilt the category order from the original list, so the layout reverted to
  the unfilled order. The filled order is now cached for the whole bag session
  and reused on subsequent renders (still only kept stable while the bag is
  open; the layout re-fills on the next open).
- **Mailbox / bank / bag money frames no longer error on coin click** – The
  coin buttons inherited from the Blizzard `SmallMoneyFrameTemplate` call
  `OpenCoinPickupFrame`, which reads `CoinPickupFrame.maxMoney` (nil on
  read-only money displays) and threw "attempt to perform arithmetic on local
  'maxMoney' (a nil value)" when clicked (e.g. on a mailbox row's silver
  button). The coin buttons' OnClick is now overridden to a no-op on Guda's
  read-only money frames (mailbox rows, bank, bag); the bag/bank money
  interactions (tooltip, right-click gold-tracking menu) are unaffected.
- **Automation checkboxes no longer show stale state after /reload** – The
  "Auto Open Bags", "Auto Close Bags", "Reverse Stack Sort" and "Mark Unusable
  Items" checkboxes were only initialized in their XML OnLoad, which runs before
  SavedVariables are available, so after a reload they displayed the default
  checked state even when the saved setting was off (the setting itself was
  saved correctly). They are now refreshed from the saved settings every time
  the settings window opens, like all other checkboxes.
- **Bank category view no longer reflows immediately** – The bank now uses the
  same update strategy as the bag: after an item is added/removed, successful
  incremental slot updates cancel any pending full redraw instead of scheduling
  a "safety-net" redraw 0.3s later. Empty-slot placeholders keep their original
  positions while the bank stays open (blocks no longer shift to compact the
  gap right away); the layout re-flows on the next refresh, matching the bag.
- **Reverse stack sort now works** – The "Reverse Stack Sort" setting is now
  actually honored by the sort engine (previously it was only saved, never read,
  so toggling it had no effect and the partial/small stack always ended up at the
  front). With the option off, full/larger stacks of an item are placed first
  and the leftover partial stack goes last; with it on, the smaller partial
  stack is placed before the larger stacks. Works consistently for both the
  left-click and right-click sort directions.
- **Theme auto-detection** – On first load (no theme saved yet), Guda now
  checks for pfUI (`pfUI` namespace) → uses the pfUI theme, then for
  Dragonflight (`DFRL` namespace) → uses the Dragonflight theme, and defaults
  to the Guda theme when neither is installed.
- **Unified GudaBag namespace** – All global data tables moved under the single
  `GudaBag` namespace: `Guda_L`→`GudaBag.L`, `Guda_Patterns`→`GudaBag.Patterns`,
  `Guda_CategoryList`→`GudaBag.CategoryList`, `Guda_LSubtypes`→`GudaBag.LSubtypes`,
  `Guda_LItemTypes`→`GudaBag.LItemTypes`, `Guda_SharedCharacters`→`GudaBag.SharedCharacters`,
  and `SortBagsRightToLeft`→`GudaBag.SortBagsRightToLeft`. The OneBag-derived
  sort internals (`ObsMove`/`ObsSort`/`ObsStack`/`ObsTooltipInfo`/…/`OBS_*`/`obs*`)
  were renamed to a consistent `SE_`/`se` prefix. Frame names (e.g.
  `Guda_BagFrame`), SavedVariables (`Guda_CharDB`/`Guda_DB`), keybindings
  (`BINDING_*`), slash commands, and Blizzard API overrides (`OpenBag`,
  `ToggleBackpack`, `UseContainerItem`, …) are intentionally kept global so
  other addons keep working.
- **Dead code cleanup** – Removed unused functions to reduce load and runtime
  overhead: `ResizeTextureElements`/`UpdateQualityBorder` (ItemButton),
  `CanItemGoInBag` (BagReplacer), `ApplyBgQuadrants` (Theme), `ExtractHyperlink`
  (Utils), `IsEnAutoEquipLoaded`/`IsGBDswitcherLoaded` (EquipmentSets),
  `BankBagSlot_OnLeave` (BankFrame), `GetPlayerRaceIcon` (BagFrame),
  `GetGroupOrder` (CategoryManager), and `GetRecentLootTime`/`Prune`
  (RecentLoot).
- **GudaBag global namespace** – All global functions exposed by the addon now
  live under a single `GudaBag` table (e.g. `GudaBag.BagFrame_OnShow`, not
  `Guda_BagFrame_OnShow`), avoiding collisions with other addons' globals.
  Frame names (e.g. `Guda_BagFrame`, `Guda_ItemButtonTemplate`) and data globals
  (`Guda_L`, `Guda_Patterns`, `Guda_CategoryList`) are unchanged. Bindings.xml
  and XML handlers reference `GudaBag.*` accordingly.
- **Quest bar icon border follows theme** – The quest item bar buttons (main
  slots and the flyout/overflow menu) style the item icon itself according to
  the active theme: rounded styles (Guda / Blizzard default) keep the icon's
  original baked-in border, while the pfUI square style crops the icon border
  and replaces it with a black 1-pixel edge (and a square slot background so no
  rounded border leaks through). Switching themes in Settings now refreshes the
  quest bar icons immediately – both directions (rounded→pfUI and pfUI→rounded)
  work without a /reload. The flyout/overflow menu shows bare icons with no
  outer border: the flyout panel no longer applies the theme's NineSlice / gold
  gradient border, so no ring appears around the icons. The tracked item bar
  (Alt-clicked items) follows the same theme styling and also refreshes
  instantly on theme switch.
- **Recently Looted / BoP categories** – Ported from Bagshui: a new "Recently
  Looted" category (10-minute window, matching Turtle WoW's BoP raid-loot trade
  grace period) surfaces items you just looted or received via trade, and a new
  "BoP" (Bind on Pickup) category groups raid BoP gear. Detection is tooltip
  based (enUS + zhCN patterns), warmed in the background by CacheWarmer. Real
  loot is detected reliably via the `CHAT_MSG_LOOT` event (like LootAlert):
  only actual loot/trade pickup messages ("You receive…" / "你获得了…")
  timestamp an item, so unequipping gear or moving items between bag slots is
  never counted as a pickup.
- **Loot marker style dropdown** – The former "Pickup Marker" and "Pulsing
  Border" checkboxes are merged into a single dropdown (Icons tab, below
  "Mark Equipment Sets"): Off / Star Icon / Pulsing Border, stored as
  `lootMarkerMode` (0/1/2) with automatic migration from the old booleans.
- **Quality bar toggle** – A "Show Quality Bar" option in the Layout tab
  controls whether the quality filter bar appears above the search box in the
  bag view. When hidden, the bar's row collapses (like the hidden search bar):
  the search bar and bag content move up to reclaim the space, with no blank
  row left behind.
- **Quality filter bar** – Ported from OneBag: a row of color-coded quality
  buttons sits directly above the search box in the bag view. Left-click toggles
  a quality filter (dimming non-matching items in place, like search), right-click
  clears it, and hovering shows the item count per rarity. The "Common" button
  also matches Poor items.
- **Bank position persistence** – Moving the bank window now saves its position
  (per character), and it reopens where you placed it, including when opened
  through the bag frame's bank button or the `/guda bank` command.
- **Outfitter category deletions stick** – Equipment-set categories linked to
  Outfitter/ItemRack that you delete from the category settings are not
  recreated on the next login.
- **Direct drag-drop stacking** – Dragging a stack directly onto another stack
  of the same item now merges them in both the single view and the category
  view (in category view, dropping on a *different* item still reassigns the
  item's category as before).
- **Split stack dialog on top** – The bag and bank windows now use the `HIGH`
  frame strata (below the Blizzard `StackSplitFrame` at `FULLSCREEN`), so the
  stack-split dialog and its buttons are no longer hidden behind them.
- **Faster search filtering** – Typing in the search box now re-tints the
  existing buttons (dimming non-matches in place) instead of rebuilding the
  entire bag/bank layout on every keystroke (borrowed from OneBag's
  alpha-filtering approach).
- **EN_AutoEquip gear category fix** – Fixed an issue where weapons swapped out
  by EN_AutoEquip could fall into "Miscellaneous". Turtle WoW's `GetItemInfo`
  returns the item class at return position 5 (not 6), so the incremental
  slot-update paths now build `itemData.class` from the correct position, and
  EN_AutoEquip sets without a `name` (or with empty gear) are handled safely.
- **Toggle-aware bag entry points** – `OpenBackpack` and `OpenAllBags` are now
  routed through the bag's toggle (instead of a plain `Show`), so third-party
  "virtual" buttons that misuse them as toggles (e.g. minimap bag buttons,
  diminfo) can both open and close the bag view.
- **Auto-loot conflict avoidance** – `autoLoot` now defaults to ON only when no
  other addon (automaton / automatonEX / superapi) already provides auto-loot,
  preventing double-looting. The "物品已经被拾取" UI error is also suppressed.
- **Localized character removal** – The "Remove from Guda tracking?" confirmation
  dialog and its menu item are now localized (zhCN: 移除 / 从 … Guda 追踪中移除？).
- **Money tooltip overlay strata** – The gold-tracking overlay on the bag/bank
  money frame now uses `FULLSCREEN_DIALOG` (above the native money buttons), so
  clicks open Guda's own gold menu instead of falling through.
- **Custom close buttons** – All five window close buttons (bag, bank, mailbox,
  settings, category editor) now use the bundled `Assets/close.blp` icon with a
  hover highlight.
- **Disenchant / Pick Lock quick buttons** – When the player knows Disenchant
  (Enchanters) or Pick Lock (Rogues with Thieves' Tools), one-click cast buttons
  appear in the bag header, just left of the sort button. Spellbook scanning is
  locale-independent (English + zhCN names plus icon fallbacks), and the buttons
  refresh on `SPELLS_CHANGED` / entering the world. (Ported from OneBag; the
  old footer versions were removed to avoid duplication.)
- **Charges display (zhCN)** – Items with usage charges (Wizard Oil, Mana Oil,
  sharpening stones, etc.) now show their remaining count (e.g. "x5") in the
  corner of the icon. The tooltip charge detection now matches Chinese client
  text ("使用次数：5", "5 次", "剩余次数：5") in addition to English.
- **zhCN detection + localization pass** – Tooltip scanning now matches Chinese
  text for permanent enchant ("永久"), usable/equip ("使用"/"装备"), profession
  tools, and unmet requirements (需要/职业/种族/等级/声望/骑术 + class/race
  names) so junk / unusable-item tinting works on Chinese clients. Hardcoded
  English UI text was localized: hearthstone, bank slots, mail metadata, quest
  bar, item-ID drop zone, settings tabs/headers, restack & bag-swap errors,
  "Other Accounts", soul shards, and the hidden-bag hint.
- **Centralized locale detection (`Guda_Patterns`)** – All locale-dependent
  tooltip-detection strings (charges, quest, requirements, profession tools,
  restore tags, class/race names, permanent enchant, etc.) now live in
  `Localization.lua` under `Guda_Patterns`. The file auto-loads the active
  client language via `GetLocale()` (enUS defaults + zhCN overrides), and
  detection code uses `Guda_MatchAnyPattern` / `Guda_MatchNumberPattern` — so
  adding a language (or fixing a detection string) is a one-file change.
- **Chinese code comments** – All code comments across the Lua and XML files
  have been translated to Chinese (code fragments, API names, item IDs and
  regular expressions inside comments are kept verbatim).
- **Auto Fill Rows** – New "自动补位" option (General settings). When enabled,
  category blocks in Category View are reordered so each row is best-filled:
  the largest block that still fits the remaining row width is pulled forward,
  minimizing empty gaps between categories. Reordering only runs when the bag is
  first opened; while the bag stays open, category positions stay fixed (so
  selling or moving an item doesn't reshuffle the grid).
- **Category View drop to empty slot** – In Category View, dragging an item onto
  an empty category's slot indicator (or a just-emptied placeholder) now
  physically places the item into that free slot instead of returning it to its
  original bag.
- **Equipped item drop anywhere in Category View** – Dragging an equipped item
  (from the character paperdoll), a bank item, or any other cursor item onto an
  empty area / slot indicator / item button in Category View now places it into a
  real free bag slot (live-scanned, so it works even if the cached slot data is
  stale), instead of returning it to its original location or re-categorizing it.
  Dropping on a green category drop target still assigns the category.
- **Dragging items no longer hijacks frame dragging** – While the cursor is
  holding an item (equipping/placing from the paperdoll or bank), clicking or
  dragging inside the bag/bank no longer triggers the "drag the window" path
  (which temporarily hid the item grid for performance). This lets you drop items
  into free slots reliably.
- **Drop onto empty bag/bank areas** – The bag and bank frames (and their item
  containers) now register as drag/drop targets, so dropping a cursor item onto
  any blank area of the window places it into the first free slot (previously
  only item buttons / category drop targets accepted drops).
- **Item Borders merged** – The "Equipment Borders" and "Other Item Borders"
  checkboxes are merged into a single "Item Borders" option that controls both.
  The redundant "Mark Equipment Sets" checkbox was removed and the Icons tab was
  re-arranged to avoid overlapping controls.
- **Trinket category icon** – The trinket category icon now uses
  `INV_Jewelry_Talisman_07`.
- **Quality filter bar off by default** – The quality filter bar above the bag
  search box is now disabled by default (enable it in the Icons tab).
- **Morning Dew fix** – 晨露酒 (Morning Dew) is now kept in the Drink category.
  Its name contains "酒" but it is a non-alcoholic light wine, so the
  alcohol → Consumable rule now excludes it (CategoryManager + SortEngine).
- **Sort: last-item placement fix** – When sorting in single view, the last
  item could fail to reach its target position because the swap anti-oscillation
  guard used an order-independent key that also blocked the *required* final
  swap on later passes. The guard now only dedups swaps within the same pass, so
  the last item is placed correctly; true oscillations are still stopped by the
  no-progress safety limit.
- **GameTooltip price visibility fix** – The tooltip (and its sub-frames,
  including the vendor-price money frame) is now raised together to the TOOLTIP
  strata at a high frame level, so the item price no longer renders behind the
  tooltip as a greyed/obscured line. The money-frame offset that reserves space
  under Guda's inventory block is also restored.
- **Category view drop slots** – While dragging an item (e.g. after splitting a
  stack), every non-empty category now shows a green glowing drop slot at the
  end of its block. Dropping a cursor item onto it physically places it into a
  free bag slot and assigns it to that category, so you no longer need to drag
  it to another category or an empty area.
- **OneBag-style sorting (with confirm, left=asc / right=desc)** – The sort
  button (bags & bank) uses the sort logic ported from OneBag, **integrated into
  `Sorting/SortEngine.lua`** (no separate duplicate file): **left-click sorts
  ascending, right-click sorts descending** (tooltip shows both). It pops a
  confirmation dialog first, then reorders items **in rounds** exactly like
  OneBag: each round scans every slot and moves whatever is movable, but a move
  only happens when both source and target slots are unlocked, so locked slots
  are simply skipped (no stuck/grey items, no relog needed) while speed stays
  good. The old multi-phase sort
  algorithms (`SortBagsPass`/`SortBankPass`/`Analyze*`) and their now-unused
  helpers (specialized-bag routing, stack consolidation, grey-item splitting,
  sort-key builders, etc.) were removed; the public API
  (`SortEngine:SortBags`/`SortBank`/`ExecuteSort`/`sortingInProgress`/
  `UpdateSortButtonState`/`IsMount`) is unchanged. Category-view "merge stacks" still works
  as before.
- **Category view split placeholder** – When you split a stack in Category
  view, an empty slot placeholder appears right next to that item in its own
  category; clicking it merges the split-off portion back into the source slot,
  so you no longer have to drag it to another category or free slot.
- **Nampower acceleration (optional, silent)** – When the [Nampower](https://gitea.com/avitasia/nampower)
  client DLL is installed, Guda automatically (no checkbox) uses its low-level
  API to speed up: bag scanning (`GetBagItem` → direct item ID + remaining
  charges, no regex/tooltip scans), whole-bag fetching (`GetBagItems`), stack
  consolidation (`GetItemStatsField("stackable")`), and tracked-item counting
  (`GetBagItem` / `FindPlayerItemSlot`). **Fully silent**: without Nampower all
  code paths fall back to the vanilla API — behavior is identical.

## Non-empty bag swap

Dragging a new bag onto an **occupied** bag slot triggers an automatic
"evacuate then swap" (bag replacement): it stashes the new bag, moves the old
bag's contents out in batches (respecting specialized bags), equips the new bag,
and stashes the old bag. This is equivalent to (and more robust than) OneBag's
bag-swap — it adds specialized-bag routing, lock-waiting via `ITEM_LOCK_CHANGED`,
combat/sort guards, bank slow-mode, and server `BAG_UPDATE` confirmation.

Starting with a later build, **auto-swap also fires from any equip path**: if you
right-click a new bag from your inventory (or equip it from an action bar etc.)
while the target bag slot still holds items, Guda intercepts the
"bag is not empty" error and performs the same evacuate-then-swap automatically —
no need to drag the bag onto the slot.

If there aren't enough free slots to evacuate the old bag, Guda reports exactly
how many more are needed, e.g. "背包空位不足，替换此背包还需要 X 个空位（当前只有 Y 个）".

During a bag swap the item grid is temporarily hidden (like dragging and sorting),
which keeps the frame rate high while items are being evacuated and refilled; the
grid is rebuilt automatically when the swap finishes.

### Issues after updating the addon

Delete outdated saved variables:

```
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda.lua
WTF/Account/<ACCOUNT_NAME>/SavedVariables/Guda.lua.bak
```

---

## 📢 Support

For bugs or feature requests, please open an issue. Your feedback helps improve the addon!
