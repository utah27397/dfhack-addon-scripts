--@ module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local repeat_util = require('repeat-util')
local utils = require('utils')
local widgets = require('gui.widgets')

local RULE_PREFIX = 'autoassign-animals/rule/'
local SCHEDULE_NAME = 'autoassign-animals'
local LIFE_STAGE_ADULT = 0
local LIFE_STAGE_JUVENILE = 1
local LIFE_STAGE_EITHER = 2

local function normalize_life_stage(life_stage)
    if life_stage == LIFE_STAGE_JUVENILE or
            life_stage == LIFE_STAGE_EITHER then
        return life_stage
    end
    return LIFE_STAGE_ADULT
end

local function life_stage_label(life_stage)
    return ({
        [LIFE_STAGE_ADULT]='adult',
        [LIFE_STAGE_JUVENILE]='juvenile',
        [LIFE_STAGE_EITHER]='either stage',
    })[normalize_life_stage(life_stage)]
end

rules = rules or {}

local function load_rules()
    rules = {}
    for _, entry in ipairs(dfhack.persistent.get_all(RULE_PREFIX, true) or {}) do
        local zone_id = entry.ints[1]
        rules[zone_id] = {
            entry=entry,
            race=entry.ints[2],
            sex=entry.ints[3],
            life_stage=normalize_life_stage(entry.ints[5]),
            enabled=entry.ints[4] == 1,
        }
    end
end

local function save_rule(zone_id, rule)
    local entry = rule.entry or dfhack.persistent.save{
        key=RULE_PREFIX..zone_id,
        ints={
            zone_id,
            rule.race,
            rule.sex,
            rule.enabled and 1 or 0,
            normalize_life_stage(rule.life_stage),
        },
    }
    entry.ints[1] = zone_id
    entry.ints[2] = rule.race
    entry.ints[3] = rule.sex
    entry.ints[4] = rule.enabled and 1 or 0
    entry.ints[5] = normalize_life_stage(rule.life_stage)
    entry:save()
    rule.life_stage = normalize_life_stage(rule.life_stage)
    rule.entry = entry
    rules[zone_id] = rule
end

local function has_enabled_rules()
    for _, rule in pairs(rules) do
        if rule.enabled then return true end
    end
    return false
end

local function get_assigned_ids()
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

local function matches_life_stage(unit, life_stage)
    life_stage = normalize_life_stage(life_stage)
    if life_stage == LIFE_STAGE_EITHER then return true end
    if life_stage == LIFE_STAGE_JUVENILE then
        return dfhack.units.isBaby(unit) or dfhack.units.isChild(unit)
    end
    return dfhack.units.isAdult(unit)
end

function matches_rule(unit, rule)
    return dfhack.units.isAnimal(unit) and
        dfhack.units.isOwnCiv(unit) and
        dfhack.units.isAlive(unit) and
        not dfhack.units.isMerchant(unit) and
        unit.race == rule.race and
        (rule.sex == -1 or unit.sex == rule.sex) and
        matches_life_stage(unit, rule.life_stage)
end

function rule_specificity(rule)
    return (rule.sex ~= -1 and 1 or 0) +
        (normalize_life_stage(rule.life_stage) ~= LIFE_STAGE_EITHER and 1 or 0)
end

local function make_zone_ref(zone_id)
    for _, unit in ipairs(df.global.world.units.active) do
        for _, ref in ipairs(unit.general_refs) do
            if ref:getType() == df.general_ref_type.BUILDING_CIVZONE_ASSIGNED then
                local new_ref = ref:new()
                new_ref.building_id = zone_id
                return new_ref
            end
        end
    end
end

local function assign_to_pasture(zone, unit)
    local ref = make_zone_ref(zone.id)
    if not ref then return false end
    unit.general_refs:insert('#', ref)
    utils.insert_sorted(zone.assigned_units, unit.id)
    return true
end

function run_cycle(quiet)
    if not dfhack.isMapLoaded() then return false end
    local assigned_ids = get_assigned_ids()
    local assigned, missing_ref = 0, false
    local ordered = {}
    for zone_id, rule in pairs(rules) do
        table.insert(ordered, {zone_id=zone_id, rule=rule})
    end
    table.sort(ordered, function(a, b)
        local a_specific = rule_specificity(a.rule)
        local b_specific = rule_specificity(b.rule)
        if a_specific ~= b_specific then return a_specific > b_specific end
        return a.zone_id < b.zone_id
    end)

    for _, entry in ipairs(ordered) do
        local zone = df.building.find(entry.zone_id)
        if entry.rule.enabled and zone and dfhack.buildings.isPenPasture(zone) then
            for _, unit in ipairs(df.global.world.units.active) do
                if not assigned_ids[unit.id] and matches_rule(unit, entry.rule) then
                    if assign_to_pasture(zone, unit) then
                        assigned_ids[unit.id] = true
                        assigned = assigned + 1
                    else
                        missing_ref = true
                    end
                end
            end
        end
    end

    if missing_ref then
        dfhack.printerr('autoassign-animals: manually pasture one animal first')
    end
    if not quiet or assigned > 0 then
        print(('autoassign-animals: assigned %d animal(s)'):format(assigned))
    end
    return true
end

local function start()
    repeat_util.cancel(SCHEDULE_NAME)
    if has_enabled_rules() then
        repeat_util.scheduleEvery(
            SCHEDULE_NAME, 1, 'months', function() run_cycle(true) end)
    end
end

local function selected_pasture()
    local zone = dfhack.gui.getSelectedBuilding(true)
    if zone and dfhack.buildings.isPenPasture(zone) then return zone end
end

local function in_pasture_interface()
    local focus = dfhack.gui.getCurFocus(true)
    return selected_pasture() and
        (focus == 'dwarfmode/Zones' or
         focus:sub(1, #'dwarfmode/ZonesPenInfo') ==
            'dwarfmode/ZonesPenInfo')
end

local function species_choices(selected_race)
    local seen, choices = {}, {}
    for _, unit in ipairs(df.global.world.units.active) do
        if dfhack.units.isAnimal(unit) and dfhack.units.isOwnCiv(unit) and
                not seen[unit.race] then
            seen[unit.race] = true
            local raw = df.creature_raw.find(unit.race)
            table.insert(choices, {
                text=('%s (%s)'):format(
                    dfhack.units.getRaceNameById(unit.race), raw.creature_id),
                search_key=raw.creature_id,
                race=unit.race,
                selected=unit.race == selected_race,
            })
        end
    end
    table.sort(choices, function(a, b)
        if a.selected ~= b.selected then return a.selected end
        return a.text < b.text
    end)
    return choices
end

rule_view = rule_view or nil

RuleScreen = defclass(RuleScreen, gui.FramedScreen)
RuleScreen.ATTRS{
    focus_path='autoassign-animals/rule',
    frame_title='Pasture rule',
    frame_width=58,
    frame_height=24,
    zone_id=DEFAULT_NIL,
}

function RuleScreen:init()
    local rule = rules[self.zone_id] or {
        race=-1,
        sex=-1,
        life_stage=LIFE_STAGE_ADULT,
        enabled=true,
    }
    self:addviews{
        widgets.Label{frame={t=0}, text=('Pasture #%d species'):format(self.zone_id)},
        widgets.FilteredList{
            view_id='species',
            frame={t=1, b=6},
            choices=species_choices(rule.race),
            selected=1,
            edit_key='CUSTOM_CTRL_F',
            on_submit=self:callback('save'),
        },
        widgets.CycleHotkeyLabel{
            view_id='sex',
            frame={b=4, l=0},
            label='Gender',
            key='CUSTOM_G',
            options={
                {label='Either', value=-1},
                {label='Female', value=0},
                {label='Male', value=1},
            },
            initial_option=rule.sex,
        },
        widgets.CycleHotkeyLabel{
            view_id='life_stage',
            frame={b=3, l=0},
            label='Life stage',
            key='CUSTOM_L',
            options={
                {label='Either', value=LIFE_STAGE_EITHER},
                {label='Juvenile', value=LIFE_STAGE_JUVENILE},
                {label='Adult', value=LIFE_STAGE_ADULT},
            },
            initial_option=normalize_life_stage(rule.life_stage),
        },
        widgets.ToggleHotkeyLabel{
            view_id='enabled',
            frame={b=2, l=0},
            label='Automatic assignment',
            key='CUSTOM_A',
            options={
                {label='Enabled', value=true, pen=COLOR_GREEN},
                {label='Disabled', value=false, pen=COLOR_RED},
            },
            initial_option=rule.enabled,
        },
        widgets.HotkeyLabel{
            frame={b=0, l=0},
            label='Save',
            key='SELECT',
            on_activate=self:callback('save'),
        },
        widgets.HotkeyLabel{
            frame={b=0, r=0},
            label='Cancel',
            key='LEAVESCREEN',
            on_activate=self:callback('dismiss'),
        },
    }
end

function RuleScreen:save()
    local _, choice = self.subviews.species:getSelected()
    if not choice then return end
    save_rule(self.zone_id, {
        race=choice.race,
        sex=self.subviews.sex:getOptionValue(),
        life_stage=self.subviews.life_stage:getOptionValue(),
        enabled=self.subviews.enabled:getOptionValue(),
        entry=rules[self.zone_id] and rules[self.zone_id].entry,
    })
    start()
    run_cycle(true)
    self:dismiss()
end

function RuleScreen:onDismiss()
    rule_view = nil
end

PastureRuleOverlay = defclass(PastureRuleOverlay, overlay.OverlayWidget)
PastureRuleOverlay.ATTRS{
    default_pos={x=2, y=8},
    viewscreens='dwarfmode',
    frame={w=30, h=3},
}

function PastureRuleOverlay:init()
    self:addviews{
        widgets.HotkeyLabel{
            frame={t=0, l=0},
            label='Configure pasture rule',
            key='CUSTOM_CTRL_A',
            on_activate=function()
                local zone = selected_pasture()
                if zone and not rule_view then
                    rule_view = RuleScreen{zone_id=zone.id}:show()
                end
            end,
        },
        widgets.Label{
            frame={t=1, l=0, w=30},
            text={{text=function()
                    local zone = selected_pasture()
                    local rule = zone and rules[zone.id]
                    if not rule then return 'Rule: not configured' end
                    local species = dfhack.units.getRaceNameById(rule.race)
                    if #species > 21 then species = species:sub(1, 20)..'.' end
                    return ('Species: %s'):format(species)
                end}},
        },
        widgets.Label{
            frame={t=2, l=0, w=30},
            text={{text=function()
                    local zone = selected_pasture()
                    local rule = zone and rules[zone.id]
                    if not rule then return '' end
                    local sex = ({[-1]='either gender', [0]='female', [1]='male'})[rule.sex]
                    return ('%s / %s'):format(sex, life_stage_label(rule.life_stage))
                end}},
        },
    }
end


function PastureRuleOverlay:render(dc)
    if in_pasture_interface() then
        PastureRuleOverlay.super.render(self, dc)
    end
end

function PastureRuleOverlay:onInput(keys)
    if not in_pasture_interface() then return false end
    return PastureRuleOverlay.super.onInput(self, keys)
end

OVERLAY_WIDGETS = {pasture_rule=PastureRuleOverlay}

function isEnabled()
    return has_enabled_rules()
end

dfhack.onStateChange[SCHEDULE_NAME] = function(code)
    if code == SC_MAP_LOADED then
        load_rules()
        start()
    elseif code == SC_MAP_UNLOADED then
        repeat_util.cancel(SCHEDULE_NAME)
    end
end

if dfhack.isMapLoaded() then
    load_rules()
    start()
end

if dfhack_flags.module then return end

if not dfhack.isMapLoaded() then qerror('A loaded fortress map is required.') end
load_rules()
local args = {...}
if args[1] == 'now' then
    run_cycle(false)
elseif not args[1] or args[1] == 'status' then
    local count = 0
    for _, rule in pairs(rules) do
        if rule.enabled then count = count + 1 end
    end
    print(('autoassign-animals: %d enabled pasture rule(s)'):format(count))
else
    print('Configure rules from the pasture interface.')
end
