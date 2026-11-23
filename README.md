# Zigzag Station

A platform-free railway station for reversing trains and building switchback or zigzag lines in Transport Fever 3.

## Features

- One to eight parallel station tracks with connectable nodes at both ends.
- A centred reversing point, with closely spaced passenger and cargo stops when loading is enabled.
- Compatible with both passenger and cargo consists in the line manager.
- Independently optional passenger and cargo loading.
- Optional shared transfer warehouse with 250, 500, 1,000, 2,000 or 5,000 cargo units;
  zero disables storage and is the default. Select Universal, Bulk, Flatbed, Goods or Liquid.
  A Stocks card appears in the station window, including specialised cargo selectors.
- Passenger capacity adjustable from 0.5× to 3×, with 1× as the default.
- Catchment radius adjustable from 50 to 300 metres, with 150 metres as the default.
- No visible platform, including when loading is enabled.
- Adjustable lengths of 5, 10, and 20 metres, then 40-metre steps through 440 metres;
  10 metres is the default.
- Adjustable track spacing from 3 to 20 metres, in one-metre steps, with 5 metres as the default.
- Two always-visible curve-radius sliders, Start and End, each ranging from -2,000 to +2,000
  metres and controlling half the station. Negative values curve left, positive values curve
  right, and zero keeps that half straight. Both default to zero. Matching values form a continuous
  curve; opposite signs form an S-curve. Different radii and curves at only one end are supported.
- Parallel tracks stay concentric within each half, with matching loading lanes, passenger crossings
  and catchment points. Length and radii refer to the station's centre line. Passenger capacity
  and loading length follow each track's combined arc length.
- Four construction and maintenance cost models: no cost, selected-track cost, equivalent
  vanilla track-module cost, or track-module cost plus matching passenger/cargo platforms.
  Module Cost and Station Cost also include enabled warehouse storage at vanilla rates.
  New games default to module cost; old Off/On configurations migrate to No Cost/Track Cost.
- Select visible vanilla and modded tracks during construction, including electrified and
  third-rail variants, respecting their availability years and native menu order.
- Track dropdown entries show the track's existing icon beside its name, with text fallback
  when icon metadata is empty. Long names wrap within the construction panel's width.
- Track mods can also be applied afterwards with the normal track-upgrade tool.
- Track upgrades apply to every track in a Zigzag Station together.
- Track upgrades derive and persist the selected template's electric capability, including
  third-rail and other always-electric tracks.
- A dedicated zigzag menu icon, rather than the vanilla passenger-station placeholder.
- The vanilla station window opens on selection, with title renaming and stopping lines.
- Localised construction text for every language shipped with Transport Fever 3.

The station does not explicitly command a train to reverse. Transport Fever's route solver reverses the train when the next leg of its line requires departure in the opposite direction.

Load Zigzag after track packs and cost mods so its initial picker and cost snapshot include
their final changes. New placements default to the first available track in native menu order.
Existing stations retain their exact track when a mod hides it or it becomes unavailable for
new construction. If the selected build-menu track becomes unavailable as the year changes,
new placements switch to the first available track. Missing track or track-module cost data
produces one warning per track and cost type, with zero construction and maintenance costs
for that track contribution. Explicit
zero prices are accepted without warnings; Station Cost still includes enabled platform costs.

## Development

Generate runtime Lua and run the regression tests with:

```sh
tl gen -c -o content/mod.script.lua src/mod.script.tl
tl gen -c -o content/zigzag/logging_config.lua src/zigzag/logging_config.tl
tl gen -c -o content/zigzag/construction_path.lua src/zigzag/construction_path.tl
tl gen -c -o content/zigzag/track_selection.lua src/zigzag/track_selection.tl
tl gen -c -o content/zigzag/validation_metadata.lua src/zigzag/validation_metadata.tl
tl gen -c -o content/zigzag/cargo_storage.lua src/zigzag/cargo_storage.tl
tl gen -c -o content/zigzag/station_definition.lua src/zigzag/station_definition.tl
tl gen -c -o content/gui/zigzag/track_icons.script.lua src/gui/zigzag/track_icons.script.tl
tl gen -c -o content/gui/zigzag/track_icons.res.lua src/gui/zigzag/track_icons.res.tl
tl gen -c -o content/gui/zigzag/track_icons.css.lua src/gui/zigzag/track_icons.css.tl
tl gen -c -o content/gui/zigzag/cargo_storage.script.lua src/gui/zigzag/cargo_storage.script.tl
tl gen -c -o content/gui/zigzag/cargo_storage.res.lua src/gui/zigzag/cargo_storage.res.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.con.lua src/stations/rail/zigzag/zigzag.con.tl
tl gen -c -o content/stations/rail/zigzag/zigzag_single_bay.con.lua src/stations/rail/zigzag/zigzag_single_bay.con.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.metacon.lua src/stations/rail/zigzag/zigzag.metacon.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.template.script.lua src/stations/rail/zigzag/zigzag.template.script.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.params.gui.lua src/stations/rail/zigzag/zigzag.params.gui.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.window.script.lua src/stations/rail/zigzag/zigzag.window.script.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.selection.gs.lua src/stations/rail/zigzag/zigzag.selection.gs.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.selection.script.lua src/stations/rail/zigzag/zigzag.selection.script.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.script.lua src/stations/rail/zigzag/zigzag.script.tl
lua tests/zigzag_check.lua
python3 tests/track_icons_check.py "/path/to/Transport Fever 3"
python3 tests/cargo_storage_check.py "/path/to/Transport Fever 3"
python3 tests/compatibility_check.py "/path/to/mod.io/common/10640/mods"
```

The two halves meet at a fixed station midpoint with a shared tangent. Both ends remain
connectable. Radius selections are never widened automatically: invalid combinations are
rejected with a message giving the minimum radius and affected end. The limit includes the
selected track's minimum build radius and station width, and limits each half's turn to 90
degrees. Existing stations without curve parameters keep their straight layout, stop nodes
and prices.

Radius validation uses namespaced construction metadata and the native builder's
`proposalCreate` and `proposalPrepareForApply` events, including track upgrades. Invalid
choices remain visible in the preview and are blocked with build errors. Reload the save
after updating so the game script installs these event subscriptions.

User-facing text is defined in `strings.json`. Its translation keys are namespaced
with `apasz_zigzag_` to avoid collisions with other mods.

Runtime logging uses the shared `_logging` module. Debug logging is disabled by default in
`src/zigzag/logging_config.tl`.

The metaconstruction picker saves `streetTemplate` and the track's electric capability into
the placed construction. Picker indices are transient; legacy `trackType` indices retain their
original vanilla mapping. The post-run catalogue includes invisible templates for saved stations
and upgrades, while the picker only offers visible railway templates in the native track menu.
Only the selected pricing model is captured, once, and looked up without resource API calls
during construction updates. The picker and upgrades share the same train-capable railway
check. Definition values and controls are shared by the legacy construction and new template.

Track icons use the native parameter's `images` array. A GUI bootstrap resource decorates only
Zigzag's namespaced picker and carries its row renderer through the native UI conversion by
function identity. The extension retains the native dropdown and compact callout, and delegates
unrelated selectors to the previous renderer. Icon metadata is read during menu construction;
rendering uses cached rows. Availability periods are indexed once for metadata lookup, and
expired selections update the native stored value after rendering. Namespaced styles set the
thumbnail size, spacing and name wrapping using the native `construction_sizes.lua` panel
width, falling back to 400 pixels on older builds such as 40425 where that module is absent.

The GUI checks compile the current renderer from the game's `base/content/gui.zip`, then test
the extension against it. Use `--tl /path/to/tl` if the Teal compiler is not on PATH. Coverage
includes year-filtered IDs, expired selections, reordered entries, empty icons, compact callouts,
both signed curve sliders (including zero and negative values),
native and fallback stylesheet widths, layout spacing, existing GUI
wrappers, and avoiding resource lookups during rendering. In-game checks should
include dropdown clipping and controller input at different UI scales.

The track tests cover hidden vanilla and modded templates, third rail, availability boundaries,
saved identity after catalogue reordering, wrapped scripts, zero-price fallbacks, cost scaling,
rejected tram-only upgrades, and avoiding unused pricing reads.
In-game verification should include NEP³ before Zigzag, a save with existing Zigzag stations,
new placements with several track variants, and catenary and track upgrades after reloading.

Track categories are discovered from the game's `menu_category` resources for the `TRACKS`
menu, including custom tabs supplied by track packs. Roads, tram-only templates and internal
tracks without a menu entry remain excluded. The installed-mod check reads the actual track
and category definitions, checks picker membership and electrification, and builds curved
stations with storage for each eligible template. These resource checks do not simulate other
mods' post-run visibility changes; the regression suite checks visibility separately.
It also runs Catchment Control, Warehouse Stock Limits, Modular Build Ahead and Passenger Cargo
Unloading in both modifier orders, checking both warehouse bay layouts and every storage type.
Passenger Cargo Unloading retains its intended effect on passenger terminals.

Curve tests cover every pair of end radii, short and long stations, multiple track counts,
every loading combination, physical track spacing, tangent continuity, sampled arc accuracy,
terminal references, passenger access connections, shared midpoint tangents, one-ended curves,
S-curves, asymmetric capacities, radius limits, saved parameters and upgrades. Build-validation
checks cover both ends, stricter upgrade radii, unrelated proposals and saved event subscriptions.
An optional first argument to `tests/zigzag_check.lua` loads a compiled copy of the game's
`scripts/construction/street_util_serialized.tl` to check against the native tangent helper.
In-game checks should also cover connected approaches at both ends, reversing trains, catenary
appearance on tight curves, invalid-radius messages and save/reload.

Cargo storage uses a separate, stably tagged warehouse subconstruction and storage shared by all tracks.
Universal storage uses one mixed-cargo stock. Specialised storage uses one cargo type per bay,
with native Bulk, Flatbed, Goods or Liquid filtering, frozen delivery timers and faster loading.
The Stocks card supports the native per-bay cargo selector; its choices survive edits and upgrades.
An empty model supplies bounds at the fixed station midpoint without visible geometry or collision.
The game handles loading and unloading; other cargo stations can use the warehouse when their
catchment reaches it. Industries do not exchange cargo with it automatically. Delivery timers
continue running in universal storage. Zigzag's cargo loading must be enabled for its trains to
use storage; disabling loading retains the warehouse and its contents.

The **Specialised bays** mod setting selects 500-unit bays (default) or one bay
using the full selected capacity. The 250-unit preset produces one 250-unit bay. Universal storage
always remains one mixed stock. The template selects one of two construction resources with
fixed bay layouts, so changing the mod setting never repartitions existing stations on reload.
Both resources share the definition, update code, cost capture and station UI.

Storage capacity is independent of station length and track count. Module Cost and Station Cost
use the selected vanilla warehouse module's price and upkeep per unit, captured after cost mods
have run. No Cost remains free, and Track Cost charges only for track. Existing stations default
to no storage. Capacity reductions, disabling storage and bulldozing are blocked while the proposed
capacity of an affected bay is below the amount stored in that bay. Changing warehouse type
requires its existing bays to be empty. Both preview and pre-apply checks read the current cargo count,
so a delivery arriving after preview cannot bypass this check. Collect or explicitly discard cargo
using the native Stocks control before removing a filled warehouse.

The station window's native extension point adds a Stocks card for each Zigzag warehouse in
the station group. It reuses the native stock display and discard action, with editing restricted
to the owner. Regression checks cover all capacity presets and cost modes, stable stock identities
through layout and loading changes, live capacity checks, demolition, grouped stations and foreign
ownership. In-game verification should include two lines transferring freight through the store,
catchment visibility, saved cargo after reloading, and cargo retention through edits and upgrades.
The native storage check runs vanilla warehouse assembly and all five module types with geometry
stubbed, comparing the final stock's capacity, mixed-cargo rules and loading modifier. This catches
differences between module arguments and the effective stock produced by the warehouse.
It also loads the Stocks plugin through native React plugin discovery and `util.useFn`, checking
the runtime script resource's required `data()` entry point with storage off and on. Add
`--sorting-modes-dir ../sorting_modes` to check both plugin-loading orders with Sorting Modes'
renderer wrapper enabled. Native cargo-icon callbacks are exercised for setting and resetting
cargo, including their construction replacement command and mapping from stock IDs to bay tags.
Add `--terminal-selector-dir /path/to/gameburrow_terminalselector` to load the installed Terminal
Selector plugin alongside Stocks, including when Sorting Modes is enabled. This checks native
plugin discovery, ordering and coexistence; it does not simulate line editing or transfers.

Selecting a frozen Zigzag track forwards the native selection event to its owning construction.
The construction's window hook then supplies vanilla station-group content and renames the
construction name stem. It returns the native station recipe directly and uses the game's
action-binding helper, avoiding repeated dispatch through global window-factory wrappers.
The selection game script must be loaded by reloading the save after updating the mod.

The window tests cover callback loading through `data()`, track-selection forwarding,
generated construction names, native station content, and the construction rename target.
For in-game verification, check existing and newly placed stations, rename persistence after
reloading, stopping lines on each terminal, and ordinary track selection.

Passenger and cargo loading are disabled by default. The non-loading terminal uses an invisible,
non-linkable `PERSON` lane. TpF3 requires every terminal's `personEdges` to resolve unambiguously
to either `PERSON` or `CARGO`. Both terminal compatibility flags are enabled because the line
manager otherwise rejects one vehicle class; zero capacity and an empty catchment prevent the
station from acting as a normal platform.

When either loading mode is enabled, each track has separate invisible passenger and cargo
terminals. A disabled mode retains a zero-capacity, zero-transfer terminal so that its trains can
still use the station for reversing. The terminals use distinct stop nodes one metre apart because
TpF3 requires every vehicle stop node to identify one terminal. Passenger capacity scales with the
selected track length and capacity multiplier. Linkable pedestrian lanes are only generated for
passenger loading; they cross the tracks at both ends and the midpoint, extending ten metres beyond
each outer track. Loading stations have catchment areas at both ends and the midpoint using the
selected radius.
