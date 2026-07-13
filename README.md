# DFHack Addon Scripts

Additional scripts for current DFHack releases. The `0.47.05-r8` branch contains
versions adapted for Dwarf Fortress 0.47.05 and DFHack 0.47.05-r8.

## Install

Place these files in DFHack's `hack/scripts` directory:

- [`autoassign-animals.lua`](autoassign-animals.lua)
- [`autocage-juveniles.lua`](autocage-juveniles.lua)

Restart DFHack after installing them. If DFHack is already running, enter
`enable` with no arguments once to reload available script modules and overlays.

## Adult pasture assignment

Select a pasture and choose **Auto-assign adults**. Select a species, choose
female, male, or either gender, and save the rule.

Each pasture can have one rule. Once per in-game month, unassigned adult animals
that match the rule are assigned to that pasture. Existing assignments are not
changed. When rules overlap, gender-specific rules take priority over
either-gender rules.

## Juvenile autocaging

Build one or more cages and draw a pasture over them. Select any cage and turn
**Autocage juveniles** on in the cage interface. Every completed cage under that
pasture becomes part of the managed cage pool.

Once per in-game month, juvenile animals are distributed across managed cages.
Their cage assignment is removed when they become adults. Grazers, merchants,
animals with owners, and animals marked for slaughter are never caged. Any of
those animals already assigned to managed cages are released on the next check.

Rules and enabled cage pastures are stored per fortress and resume automatically
when that fortress is loaded again.

## Commands

```text
autoassign-animals now       Run adult pasture rules immediately
autoassign-animals status    Show the number of enabled pasture rules
autocage-juveniles now       Run a check immediately
autocage-juveniles status    Show the configuration and current state
```

## Older DFHack

`main` targets the current stable DFHack API. For DFHack 0.47.05-r8, use the
[`0.47.05-r8`](../../tree/0.47.05-r8) branch; its README includes the startup
instructions required by that release.

## License

MIT. See [`LICENSE`](LICENSE).
