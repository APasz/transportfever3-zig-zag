# Zigzag Station

A platform-free railway station for reversing trains and building switchback or zigzag lines in Transport Fever 3.

## Features

- One straight station track with connectable nodes at both ends.
- A single operational terminal at the track centre.
- Compatible with both passenger and cargo consists in the line manager.
- No passenger/cargo capacity, visible platform, or catchment area.
- Lengths of 10, 40, 80, 120, 160, 240, and 320 metres, with 10 metres as the default.
- Vanilla track type, high-speed track, and catenary options during construction.
- Compatible track mods can be applied afterwards with the normal track-upgrade tool.
- Track upgrades derive and persist the selected template's electric capability, including
  third-rail and other always-electric tracks.
- A dedicated zigzag menu icon, rather than the vanilla passenger-station placeholder.
- Localised construction text for every language shipped with Transport Fever 3.

The station does not explicitly command a train to reverse. Transport Fever's route solver reverses the train when the next leg of its line requires departure in the opposite direction.

## Development

Generate runtime Lua and run the structural tests with:

```sh
tl gen -c -o content/stations/rail/zigzag/zigzag.con.lua src/stations/rail/zigzag/zigzag.con.tl
tl gen -c -o content/stations/rail/zigzag/zigzag.script.lua src/stations/rail/zigzag/zigzag.script.tl
lua tests/zigzag_check.lua
```

User-facing construction text is defined in `strings.json`. Its translation keys are namespaced
with `apasz_zigzag_` to avoid collisions with other mods.

The non-loading terminal uses an invisible, non-linkable `PERSON` lane. TpF3 requires every
terminal's `personEdges` to resolve unambiguously to either `PERSON` or `CARGO`. Both terminal
compatibility flags are enabled because the line manager otherwise rejects one vehicle class;
zero capacity and an empty catchment prevent the station from acting as a normal platform.
