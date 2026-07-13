--@ module = true
--@ enable = true

-- Automatically cage juvenile animals and release them when they mature.

local repeat_util = require('repeat-util')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local CONFIG_KEY = 'autocage-juveniles/config'
local SCHEDULE_NAME = 'autocage-juveniles'
local CHECK_INTERVAL = 1
local CHECK_UNITS = 'months'

startup_enabled = startup_enabled or false

local help = [====[
autocage-juveniles
==================

Automatically assigns juvenile, non-grazing animals to built cages inside a
designated pen/pasture zone. Adults, grazers, and owned pets are released from
the managed cages.

Usage:
  autocage-juveniles set [zone-id]
  autocage-juveniles now
  autocage-juveniles status
  autocage-juveniles enable
  autocage-juveniles disable

With no zone ID, "set" uses the pen/pasture selected in the game UI.
]====]

local function get_config()
    if not dfhack.isWorldLoaded() then return nil end
    return dfhack.persistent.get(CONFIG_KEY)
end

local function save_config(zone_id, enabled)
    return dfhack.persistent.save{
        key = CONFIG_KEY,
        ints = {zone_id, enabled and 1 or 0},
    }
end

local function configured_zone()
    local config = get_config()
    if not config or config.ints[1] < 0 then return nil end
    return df.building.find(config.ints[1])
end

local function is_pasture(building)
    return building and
        building:getType() == df.building_type.Civzone and
        building.zone_flags.pen_pasture
end

local function validate_zone(building)
    if not is_pasture(building) then
        qerror('The configured building must be a pen/pasture zone.')
    end
end

local function cages_in_zone(zone)
    local cages = {}
    for _, building in ipairs(df.global.world.buildings.all) do
        if building:getType() == df.building_type.Cage and
                building.z == zone.z and
                building.x1 >= zone.x1 and building.x1 <= zone.x2 and
                building.y1 >= zone.y1 and building.y1 <= zone.y2 and
                building:getBuildStage() == building:getMaxBuildStage() then
            table.insert(cages, building)
        end
    end
    return cages
end

local function has_owner(unit)
    return unit.relationship_ids[df.unit_relationship_type.Pet] ~= -1
end

function is_cage_candidate(unit)
    return dfhack.units.isAnimal(unit) and
        dfhack.units.isOwnCiv(unit) and
        dfhack.units.isAlive(unit) and
        not dfhack.units.isMerchant(unit) and
        not has_owner(unit) and
        not dfhack.units.isGrazer(unit) and
        (dfhack.units.isBaby(unit) or dfhack.units.isChild(unit))
end

function should_release(unit)
    return not unit or not dfhack.units.isAlive(unit) or has_owner(unit) or
        dfhack.units.isGrazer(unit) or dfhack.units.isAdult(unit)
end

local function assigned_unit_ids()
    local assigned = {}
    for _, building in ipairs(df.global.world.buildings.all) do
        local building_type = building:getType()
        if building_type == df.building_type.Cage or
                building_type == df.building_type.Civzone then
            for _, unit_id in ipairs(building.assigned_units) do
                assigned[unit_id] = true
            end
        elseif building_type == df.building_type.Chain then
            if building.assigned then assigned[building.assigned.id] = true end
            if building.chained then assigned[building.chained.id] = true end
        end
    end
    return assigned
end

local function release_ineligible(cages)
    local released = 0
    for _, cage in ipairs(cages) do
        for index = #cage.assigned_units - 1, 0, -1 do
            local unit_id = cage.assigned_units[index]
            if should_release(df.unit.find(unit_id)) then
                cage.assigned_units:erase(index)
                released = released + 1
            end
        end
    end
    return released
end

local function least_loaded_cage(cages)
    local selected = cages[1]
    for index = 2, #cages do
        if #cages[index].assigned_units < #selected.assigned_units then
            selected = cages[index]
        end
    end
    return selected
end

local function assign_juveniles(cages)
    local assigned_ids = assigned_unit_ids()
    local assigned = 0
    for _, unit in ipairs(df.global.world.units.active) do
        if not assigned_ids[unit.id] and is_cage_candidate(unit) then
            local cage = least_loaded_cage(cages)
            cage.assigned_units:insert('#', unit.id)
            assigned_ids[unit.id] = true
            assigned = assigned + 1
        end
    end
    return assigned
end

function run_cycle(quiet)
    if not dfhack.isMapLoaded() then return false end

    local zone = configured_zone()
    if not zone or not is_pasture(zone) then
        if not quiet then
            dfhack.printerr('autocage-juveniles: no valid pen/pasture is configured')
        end
        return false
    end

    local cages = cages_in_zone(zone)
    if #cages == 0 then
        if not quiet then
            dfhack.printerr('autocage-juveniles: the configured pasture contains no completed cages')
        end
        return false
    end

    local released = release_ineligible(cages)
    local assigned = assign_juveniles(cages)
    if not quiet or released > 0 or assigned > 0 then
        print(('autocage-juveniles: assigned %d, released %d'):format(
            assigned, released))
    end
    return true
end

local function set_enabled(enabled)
    startup_enabled = enabled
    repeat_util.cancel(SCHEDULE_NAME)

    local config = get_config()
    if config then
        config.ints[2] = enabled and 1 or 0
        config:save()
    end

    if enabled and dfhack.isMapLoaded() then
        if not configured_zone() then
            qerror('Configure a pen/pasture first with: autocage-juveniles set')
        end
        repeat_util.scheduleEvery(
            SCHEDULE_NAME, CHECK_INTERVAL, CHECK_UNITS,
            function() run_cycle(true) end)
    end

    print('autocage-juveniles is ' .. (enabled and 'enabled' or 'disabled'))
end

local function set_zone(zone_id)
    if not dfhack.isMapLoaded() then qerror('A fortress map must be loaded.') end

    local zone
    if zone_id then
        local parsed_id = tonumber(zone_id)
        if not parsed_id then qerror('Zone ID must be a number.') end
        zone = df.building.find(parsed_id)
    else
        zone = dfhack.gui.getSelectedBuilding(true)
    end
    validate_zone(zone)

    local old = get_config()
    local enabled = old and old.ints[2] == 1 or false
    save_config(zone.id, enabled)
    print(('autocage-juveniles: using pen/pasture #%d with %d completed cage(s)')
        :format(zone.id, #cages_in_zone(zone)))
end

local function print_status()
    if not dfhack.isWorldLoaded() then
        print('autocage-juveniles: no world is loaded')
        return
    end
    local config = get_config()
    local zone = configured_zone()
    local enabled = repeat_util.repeating[SCHEDULE_NAME] ~= nil
    print('autocage-juveniles is ' .. (enabled and 'enabled' or 'disabled'))
    if config then
        print(('Configured zone: #%d%s'):format(
            config.ints[1], is_pasture(zone) and '' or ' (missing or invalid)'))
        if is_pasture(zone) then
            print(('Completed cages in zone: %d'):format(#cages_in_zone(zone)))
        end
    else
        print('Configured zone: none')
    end
end

local function selected_cage()
    local building = dfhack.gui.getSelectedBuilding(true)
    if building and building:getType() == df.building_type.Cage then
        return building
    end
end

local function pasture_for_cage(cage)
    if not cage then return nil end
    for _, building in ipairs(df.global.world.buildings.all) do
        if is_pasture(building) and building.z == cage.z and
                dfhack.buildings.containsTile(
                    building, cage.x1, cage.y1, false) then
            return building
        end
    end
end

local function cage_pasture_state()
    local zone = pasture_for_cage(selected_cage())
    local config = get_config()
    local enabled = zone and config and config.ints[1] == zone.id and
        config.ints[2] == 1
    return zone, enabled
end

local function in_cage_interface()
    if not selected_cage() then return false end
    local focus = dfhack.gui.getFocusString()
    return focus:sub(1, #'dwarfmode/QueryBuilding/Some/Cage') ==
            'dwarfmode/QueryBuilding/Some/Cage' or
        focus:sub(1, #'dwarfmode/QueryBuilding/Some/Assign') ==
            'dwarfmode/QueryBuilding/Some/Assign'
end

local function toggle_selected_cage_pasture()
    local zone, enabled = cage_pasture_state()
    if not zone then return end
    if enabled then
        set_enabled(false)
        return
    end
    save_config(zone.id, true)
    startup_enabled = true
    repeat_util.cancel(SCHEDULE_NAME)
    repeat_util.scheduleEvery(
        SCHEDULE_NAME, CHECK_INTERVAL, CHECK_UNITS,
        function() run_cycle(true) end)
    run_cycle(true)
    print(('autocage-juveniles: managing cage pasture #%d'):format(zone.id))
end

CageAutocageOverlay = defclass(CageAutocageOverlay, overlay.OverlayWidget)
CageAutocageOverlay.ATTRS{
    default_pos={x=2, y=8},
    viewscreens='dwarfmode',
    frame={w=32, h=2},
}

function CageAutocageOverlay:init()
    self:addviews{
        widgets.HotkeyLabel{
            frame={t=0, l=0},
            key='CUSTOM_CTRL_J',
            label=function()
                local zone, enabled = cage_pasture_state()
                if not zone then return 'Juvenile autocaging unavailable' end
                return enabled and 'Disable juvenile autocaging' or
                    'Enable juvenile autocaging'
            end,
            on_activate=toggle_selected_cage_pasture,
        },
        widgets.Label{
            frame={t=1, l=0, w=32},
            text=function()
                local zone = pasture_for_cage(selected_cage())
                return zone and ('Cage pasture #%d'):format(zone.id) or
                    'Place a pasture over this cage'
            end,
        },
    }
end


function CageAutocageOverlay:render(dc)
    if in_cage_interface() then
        CageAutocageOverlay.super.render(self, dc)
    end
end

function CageAutocageOverlay:onInput(keys)
    if not in_cage_interface() then return false end
    return CageAutocageOverlay.super.onInput(self, keys)
end

OVERLAY_WIDGETS = {cage_autocage=CageAutocageOverlay}

dfhack.onStateChange.autocageJuveniles = function(code)
    if code == SC_MAP_LOADED then
        local config = get_config()
        startup_enabled = config and config.ints[2] == 1 or false
        if startup_enabled and config.ints[1] >= 0 then
            repeat_util.cancel(SCHEDULE_NAME)
            repeat_util.scheduleEvery(
                SCHEDULE_NAME, CHECK_INTERVAL, CHECK_UNITS,
                function() run_cycle(true) end)
        end
    elseif code == SC_MAP_UNLOADED then
        repeat_util.cancel(SCHEDULE_NAME)
    end
end

if dfhack.isMapLoaded() then
    local config = get_config()
    startup_enabled = config and config.ints[2] == 1 or false
    if startup_enabled and configured_zone() then
        repeat_util.cancel(SCHEDULE_NAME)
        repeat_util.scheduleEvery(
            SCHEDULE_NAME, CHECK_INTERVAL, CHECK_UNITS,
            function() run_cycle(true) end)
    end
end

if dfhack_flags.module then return end

local args = {...}
local command = args[1]

if dfhack_flags.enable then
    set_enabled(dfhack_flags.enable_state)
elseif command == 'set' then
    set_zone(args[2])
elseif command == 'now' then
    run_cycle(false)
elseif command == 'status' then
    print_status()
elseif command == 'enable' then
    set_enabled(true)
elseif command == 'disable' then
    set_enabled(false)
elseif command == 'help' or not command then
    print(help)
else
    qerror('Unknown command: ' .. command)
end
