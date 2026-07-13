# DFHack Addon Scripts for 0.47.05-r8

Additional DFHack scripts for Dwarf Fortress 0.47.05 and DFHack 0.47.05-r8.

## Juvenile autocaging

`autocage-juveniles` assigns juvenile animals to built cages inside a designated
pen/pasture. It checks once per in-game month and removes cage assignments when
animals become adults.

The script never cages grazers, merchants, or animals with owners. If a grazer
or owned pet is already assigned to one of the managed cages, the script removes
that assignment on its next check.

### Install

Place [`autocage-juveniles.lua`](autocage-juveniles.lua) in DFHack's
`hack/scripts` directory.

### Configure

Build one or more cages inside a pen/pasture zone. Select the zone in the game
UI, then run:

```text
autocage-juveniles set
enable autocage-juveniles
```

You can also provide the zone's building ID explicitly:

```text
autocage-juveniles set 123
```

The zone ID is stored in the fortress save. To enable the script automatically
after restarting DFHack, add this line to `dfhack.init`:

```text
enable autocage-juveniles
```

### Commands

```text
autocage-juveniles now       Run a check immediately
autocage-juveniles status    Show the configuration and current state
enable autocage-juveniles    Start monthly checks
disable autocage-juveniles   Stop monthly checks
```

Only cages built inside the configured pasture are managed. The script balances
new assignments across those cages and leaves cages elsewhere untouched.

## Compatibility

These scripts target DFHack 0.47.05-r8. They are not intended for current DFHack
releases, whose APIs and built-in tools differ.

## License

MIT. See [`LICENSE`](LICENSE).
