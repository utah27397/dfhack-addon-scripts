--@ module = true
--@ enable = true

-- Automatically cage juvenile animals and release them when they mature.

local repeat_util = require('repeat-util')
local utils = require('utils')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local CONFIG_KEY = 'autocage-juveniles'
local SCHEDULE_NAME = 'autocage-juveniles'
local CHECK_INTERVAL = 1
local CHECK_UNITS = 'months'

local function get_default_state()
    return {enabled = false, zone_ids = {}}
end

state = state or get_default_state()

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

local function load_state()
    state = get_default_state()
    local persisted = dfhack.persistent.getSiteData(CONFIG_KEY, state)
    utils.assign(state, persisted)
    if persisted.zone_id and persisted.zone_id >= 0 then
        state.zone_ids[tostring(persisted.zone_id)] = true
        state.zone_id = nil
    end
end

local function persist_state()
    dfhack.persistent.saveSiteData(CONFIG_KEY, state)
end

local function is_pasture(building)
    return building and dfhack.buildings.isPenPasture(building)
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
                dfhack.buildings.containsTile(zone, building.x1, building.y1) and
                building:getBuildStage() == building:getMaxBuildStage() then
            table.insert(cages, building)
        end
    end
    return cages
end

local function get_managed_cages()
    local cages, seen = {}, {}
    for zone_id, managed in pairs(state.zone_ids) do
        local zone = managed and df.building.find(tonumber(zone_id))
        if is_pasture(zone) then
            for _, cage in ipairs(cages_in_zone(zone)) do
                if not seen[cage.id] then
                    seen[cage.id] = true
                    table.insert(cages, cage)
                end
            end
        end
    end
    return cages
end

function is_cage_candidate(unit)
    return dfhack.units.isAnimal(unit) and
        dfhack.units.isOwnCiv(unit) and
        dfhack.units.isAlive(unit) and
        not dfhack.units.isMerchant(unit) and
        not dfhack.units.isMarkedForSlaughter(unit) and
        not dfhack.units.isPet(unit) and
        not dfhack.units.isGrazer(unit) and
        (dfhack.units.isBaby(unit) or dfhack.units.isChild(unit))
end

function should_release(unit)
    return not unit or not dfhack.units.isAlive(unit) or
        dfhack.units.isMarkedForSlaughter(unit) or dfhack.units.isPet(unit) or
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

    local cages = get_managed_cages()
    if #cages == 0 then
        if not quiet then
            dfhack.printerr(
                'autocage-juveniles: no completed cages are in managed pastures')
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

local function start()
    repeat_util.cancel(SCHEDULE_NAME)
    if not state.enabled then return end

    if #get_managed_cages() == 0 then
        dfhack.printerr(
            'autocage-juveniles: disabled until a managed pasture contains a cage')
        return
    end

    repeat_util.scheduleEvery(
        SCHEDULE_NAME, CHECK_INTERVAL, CHECK_UNITS,
        function() run_cycle(true) end)
end

local function set_enabled(enabled)
    if enabled then
        if #get_managed_cages() == 0 then
            qerror('Mark a caged pasture first from a cage interface.')
        end
    end

    state.enabled = enabled
    start()
    persist_state()
    print('autocage-juveniles is ' .. (enabled and 'enabled' or 'disabled'))
end

local function set_zone(zone_id)
    local zone
    if zone_id then
        local parsed_id = tonumber(zone_id)
        if not parsed_id then qerror('Zone ID must be a number.') end
        zone = df.building.find(parsed_id)
    else
        zone = dfhack.gui.getSelectedCivZone(true)
    end
    validate_zone(zone)

    state.zone_ids[tostring(zone.id)] = true
    state.enabled = true
    persist_state()
    start()
    print(('autocage-juveniles: using pen/pasture #%d with %d completed cage(s)')
        :format(zone.id, #cages_in_zone(zone)))
end

local function print_status()
    print('autocage-juveniles is ' .. (state.enabled and 'enabled' or 'disabled'))
    local count = 0
    for zone_id, managed in pairs(state.zone_ids) do
        if managed then
            count = count + 1
            local zone = df.building.find(tonumber(zone_id))
            print(('Managed pasture: #%s%s'):format(
                zone_id, is_pasture(zone) and '' or ' (missing or invalid)'))
        end
    end
    print(('Managed pastures: %d; completed cages: %d'):format(
        count, #get_managed_cages()))
end

local function pasture_for_selected_cage()
    local cage = dfhack.gui.getSelectedBuilding(true)
    if not cage or cage:getType() ~= df.building_type.Cage then return end
    for _, zone in ipairs(df.global.world.buildings.other.ZONE_PEN) do
        if zone.z == cage.z and
                dfhack.buildings.containsTile(zone, cage.x1, cage.y1) then
            return zone
        end
    end
end

local function set_selected_cage_managed(managed)
    local zone = pasture_for_selected_cage()
    if not zone then return end
    state.zone_ids[tostring(zone.id)] = managed or nil
    state.enabled = next(state.zone_ids) ~= nil
    persist_state()
    start()
end

CageAutocageOverlay = defclass(CageAutocageOverlay, overlay.OverlayWidget)
CageAutocageOverlay.ATTRS{
    desc='Controls juvenile autocaging for the pasture covering a selected cage.',
    default_pos={x=-39, y=34},
    default_enabled=true,
    viewscreens='dwarfmode/ViewSheets/BUILDING/Cage',
    frame={w=31, h=2},
}

function CageAutocageOverlay:init()
    self:addviews{
        widgets.ToggleHotkeyLabel{
            view_id='managed',
            frame={t=0, l=0, w=31, h=1},
            label='Autocage juveniles:',
            key='CUSTOM_CTRL_J',
            options={
                {label='On', value=true, pen=COLOR_GREEN},
                {label='Off', value=false, pen=COLOR_RED},
            },
            enabled=function() return pasture_for_selected_cage() ~= nil end,
            on_change=set_selected_cage_managed,
        },
        widgets.Label{
            frame={t=1, l=0, w=31, h=1},
            text=function()
                local zone = pasture_for_selected_cage()
                return zone and ('Cage pasture #%d'):format(zone.id) or
                    'Place a pasture over this cage'
            end,
        },
    }
end

function CageAutocageOverlay:onRenderBody(painter)
    local zone = pasture_for_selected_cage()
    local managed = zone and state.enabled and state.zone_ids[tostring(zone.id)] or false
    self.subviews.managed:setOption(not not managed)
end

OVERLAY_WIDGETS = {cage_autocage=CageAutocageOverlay}

function isEnabled()
    return state.enabled
end

dfhack.onStateChange[CONFIG_KEY] = function(code)
    if code == SC_MAP_LOADED and dfhack.world.isFortressMode() then
        load_state()
        start()
    elseif code == SC_MAP_UNLOADED then
        repeat_util.cancel(SCHEDULE_NAME)
    end
end

if dfhack_flags.module then return end

if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then
    qerror('A loaded fortress map is required.')
end

load_state()

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
