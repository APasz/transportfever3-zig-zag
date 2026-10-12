# Zigzag Station

A platform-free railway station for reversing trains and building switchback or zigzag lines in Transport Fever 3.

## Features

- One to eight parallel station tracks with connectable nodes at both ends.
- A centred reversing point, with closely spaced passenger and cargo stops when loading is enabled.
- Compatible with both passenger and cargo consists in the line manager.
- Independently optional passenger and cargo loading.
- Passenger capacity adjustable from 0.5× to 3×, with 1× as the default.
- Catchment radius adjustable from 50 to 300 metres, with 150 metres as the default.
- No visible platform, including when loading is enabled.
- Adjustable lengths of 5, 10, and 20 metres, then 40-metre steps through 440 metres;
  10 metres is the default.
- Adjustable track spacing from 3 to 20 metres, in one-metre steps, with 5 metres as the default.
- Four construction and maintenance cost models: no cost, selected-track cost, equivalent
  vanilla track-module cost, or track-module cost plus matching passenger/cargo platforms.
  New games default to module cost; old Off/On configurations migrate to No Cost/Track Cost.
- Vanilla track type, high-speed track, and catenary options during construction.
- Compatible track mods can be applied afterwards with the normal track-upgrade tool.
- Track upgrades apply to every track in a Zigzag Station together.
- Track upgrades derive and persist the selected template's electric capability, including
  third-rail and other always-electric tracks.
- A dedicated zigzag menu icon, rather than the vanilla passenger-station placeholder.
- Localised construction text for every language shipped with Transport Fever 3.

The station does not explicitly command a train to reverse. Transport Fever's route solver reverses the train when the next leg of its line requires departure in the opposite direction.

## Development

Generate runtime Lua and run the structural tests with:

```sh
tl gen -c -o content/mod.script.lua src/mod.script.tl
tl gen -c -o content/zigzag/logging_config.lua src/zigzag/logging_config.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.con.lua src/stations/rail/zigzag/zigzag.con.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.params.gui.lua src/stations/rail/zigzag/zigzag.params.gui.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.script.lua src/stations/rail/zigzag/zigzag.script.tl
lua tests/zigzag_check.lua
```

User-facing text is defined in `strings.json`. Its translation keys are namespaced
with `apasz_zigzag_` to avoid collisions with other mods.

Runtime logging uses the shared `_logging` module. Debug logging is disabled by default in
`src/zigzag/logging_config.tl`.

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
