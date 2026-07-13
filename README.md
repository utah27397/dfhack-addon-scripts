# DFHack Addon Scripts for 0.47.05-r8

Animal-management overlays for Dwarf Fortress 0.47.05 and DFHack 0.47.05-r8.

## Install

Place [`autoassign-animals.lua`](autoassign-animals.lua) and
[`autocage-juveniles.lua`](autocage-juveniles.lua) in DFHack's `hack/scripts`
directory. Enable their interface controls once from the DFHack console:

```text
overlay enable autoassign-animals.pasture_rule
overlay enable autocage-juveniles.cage_autocage
```

DFHack stores the overlay settings, so those commands do not need to be run for
each fortress.

## Adult pasture assignment

Open a pen/pasture zone and use **Ctrl+A: Configure adult rule**. Select a
species and choose whether the pasture accepts females, males, or either sex.
The rule is stored in the fortress save and checked once per in-game month.

The script assigns only adult animals belonging to your civilization. It skips
animals already assigned to a pasture, cage, or restraint, along with merchants.
Sex-specific pasture rules take precedence over rules that accept either sex.

DFHack 0.47.05-r8 cannot construct the old pasture-assignment reference from
scratch. If no animal has ever been assigned to a pasture in the current save,
manually assign one first; automation works normally after that.

## Juvenile cage assignment

Build one or more cages inside a pen/pasture. Open a cage or its animal
assignment page and use **Ctrl+J: Enable juvenile autocaging**. All completed
cages in that pasture are managed as one balanced pool. Use the same control to
disable it.

The script cages juvenile animals and releases their assignments when they
become adults. Grazers, merchants, and owned pets are not caged. Grazers, pets,
adults, and dead animals already assigned to a managed cage are released on the
next monthly check. Slaughter designations do not exclude animals from adult
pasture or juvenile cage rules.

This compatibility branch manages one cage pasture at a time. Enabling the
control from a cage in another pasture moves juvenile autocaging to that
pasture.

## Console commands

The GUI is the normal configuration path. These commands are also available:

```text
autoassign-animals now       Run adult pasture assignment immediately
autoassign-animals status    Show the number of enabled pasture rules
autocage-juveniles now       Run juvenile cage assignment immediately
autocage-juveniles status    Show the configured pasture and state
autocage-juveniles set       Use the pasture selected in the game UI
enable autocage-juveniles    Start monthly juvenile checks
disable autocage-juveniles   Stop monthly juvenile checks
```

To resume a console-configured juvenile rule automatically after restarting
DFHack, add `enable autocage-juveniles` to `dfhack.init`. Rules enabled through
the cage interface resume when the overlay module loads.

## Compatibility

This branch targets DFHack 0.47.05-r8. Use the repository's `main` branch with
current DFHack releases.

## License

MIT. See [`LICENSE`](LICENSE).
