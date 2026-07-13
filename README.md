# DFHack Addon Scripts

Additional scripts for current DFHack releases. The `0.47.05-r8` branch contains
versions adapted for Dwarf Fortress 0.47.05 and DFHack 0.47.05-r8.

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

The zone ID and enabled state are stored per fortress. Once enabled, the script
resumes automatically when that fortress is loaded again.

### Commands

```text
autocage-juveniles now       Run a check immediately
autocage-juveniles status    Show the configuration and current state
enable autocage-juveniles    Start monthly checks
disable autocage-juveniles   Stop monthly checks
```

Only cages built inside the configured pasture are managed. The script balances
new assignments across those cages and leaves cages elsewhere untouched.

## Older DFHack

`main` targets the current stable DFHack API. For DFHack 0.47.05-r8, use the
[`0.47.05-r8`](../../tree/0.47.05-r8) branch; its README includes the startup
instructions required by that release.

## License

MIT. See [`LICENSE`](LICENSE).
