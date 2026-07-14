--@ module = true
--@ enable = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local repeat_util = require('repeat-util')
local utils = require('utils')
local widgets = require('gui.widgets')

local GLOBAL_KEY = 'autoassign-animals'
local SCHEDULE_NAME = GLOBAL_KEY
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

local function get_default_state()
    return {enabled=false, rules={}}
end

state = state or get_default_state()

local function load_state()
    state = get_default_state()
    utils.assign(state, dfhack.persistent.getSiteData(GLOBAL_KEY, state))
    for _, rule in pairs(state.rules) do
        rule.life_stage = normalize_life_stage(rule.life_stage)
    end
end

local function persist_state()
    dfhack.persistent.saveSiteData(GLOBAL_KEY, state)
end

local function get_rule(zone_id)
    return state.rules[tostring(zone_id)]
end

local function has_enabled_rules()
    for _, rule in pairs(state.rules) do
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

local function assign_to_pasture(zone, unit)
    local ref = df.new(df.general_ref_building_civzone_assignedst)
    ref.building_id = zone.id
    unit.general_refs:insert('#', ref)
    utils.insert_sorted(zone.assigned_units, unit.id)
end

function run_cycle(quiet)
    if not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then
        return false
    end

    local assigned_ids = get_assigned_ids()
    local assigned = 0
    local ordered_rules = {}
    for zone_id, rule in pairs(state.rules) do
        table.insert(ordered_rules, {zone_id=zone_id, rule=rule})
    end
    table.sort(ordered_rules, function(a, b)
        local a_specific = rule_specificity(a.rule)
        local b_specific = rule_specificity(b.rule)
        if a_specific ~= b_specific then return a_specific > b_specific end
        return tonumber(a.zone_id) < tonumber(b.zone_id)
    end)

    for _, entry in ipairs(ordered_rules) do
        local zone_id, rule = entry.zone_id, entry.rule
        local zone = df.building.find(tonumber(zone_id))
        if rule.enabled and zone and dfhack.buildings.isPenPasture(zone) then
            for _, unit in ipairs(df.global.world.units.active) do
                if not assigned_ids[unit.id] and matches_rule(unit, rule) then
                    assign_to_pasture(zone, unit)
                    assigned_ids[unit.id] = true
                    assigned = assigned + 1
                end
            end
        end
    end

    if not quiet or assigned > 0 then
        print(('autoassign-animals: assigned %d animal(s)'):format(assigned))
    end
    return true
end

local function start()
    repeat_util.cancel(SCHEDULE_NAME)
    if not state.enabled or not has_enabled_rules() then return end
    repeat_util.scheduleEvery(
        SCHEDULE_NAME, 1, 'months', function() run_cycle(true) end)
end

local function update_rule(zone_id, rule)
    rule.life_stage = normalize_life_stage(rule.life_stage)
    state.rules[tostring(zone_id)] = rule
    state.enabled = has_enabled_rules()
    persist_state()
    start()
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
                search_key=raw.creature_id..' '..dfhack.units.getRaceNameById(unit.race),
                race=unit.race,
                selected=unit.race == selected_race,
            })
        end
    end
    table.sort(choices, function(a, b) return a.text < b.text end)
    if selected_race then
        table.sort(choices, function(a, b)
            if a.selected ~= b.selected then return a.selected end
            return a.text < b.text
        end)
    end
    return choices
end

RuleScreen = defclass(RuleScreen, gui.ZScreenModal)
RuleScreen.ATTRS{
    focus_path='autoassign-animals/rule',
    zone_id=DEFAULT_NIL,
}

function RuleScreen:init()
    local rule = get_rule(self.zone_id) or {
        race=-1,
        sex=-1,
        life_stage=LIFE_STAGE_ADULT,
        enabled=true,
    }
    self:addviews{
        widgets.Window{
            frame={w=58, h=24},
            frame_title=('Pasture rule #%d'):format(self.zone_id),
            subviews={
                widgets.Label{
                    frame={t=0},
                    text='Species',
                },
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
                    label='Gender:',
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
                    label='Life stage:',
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
                    label='Automatic assignment:',
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
            },
        },
    }
end

function RuleScreen:save()
    local _, choice = self.subviews.species:getSelected()
    if not choice then
        qerror('No fort animal species are available to select.')
    end
    update_rule(self.zone_id, {
        race=choice.race,
        sex=self.subviews.sex:getOptionValue(),
        life_stage=self.subviews.life_stage:getOptionValue(),
        enabled=self.subviews.enabled:getOptionValue(),
    })
    run_cycle(true)
    self:dismiss()
end

local function selected_pasture()
    local zone = dfhack.gui.getSelectedCivZone(true)
    if zone and dfhack.buildings.isPenPasture(zone) then return zone end
end

PastureRuleOverlay = defclass(PastureRuleOverlay, overlay.OverlayWidget)
PastureRuleOverlay.ATTRS{
    desc='Configures automatic animal assignment for the selected pasture.',
    default_pos={x=7, y=18},
    default_enabled=true,
    viewscreens='dwarfmode/Zone/Some/Pen',
    frame={w=32, h=3},
}

function PastureRuleOverlay:init()
    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0, w=27, h=1},
            label='Auto-assign animals',
            key='CUSTOM_CTRL_A',
            on_activate=function()
                local zone = selected_pasture()
                if zone then RuleScreen{zone_id=zone.id}:show() end
            end,
        },
        widgets.Label{
            frame={t=1, l=0, w=32, h=1},
            text=function()
                local zone = selected_pasture()
                local rule = zone and get_rule(zone.id)
                if not rule then return 'Rule: not configured' end
                local species = dfhack.units.getRaceNameById(rule.race)
                if #species > 23 then species = species:sub(1, 22)..'.' end
                return ('Species: %s'):format(species)
            end,
        },
        widgets.Label{
            frame={t=2, l=0, w=32, h=1},
            text=function()
                local zone = selected_pasture()
                local rule = zone and get_rule(zone.id)
                if not rule then return '' end
                local sex = ({[-1]='either gender', [0]='female', [1]='male'})[rule.sex]
                return ('%s / %s'):format(sex, life_stage_label(rule.life_stage))
            end,
        },
    }
end

OVERLAY_WIDGETS = {pasture_rule=PastureRuleOverlay}

function isEnabled()
    return state.enabled
end

dfhack.onStateChange[GLOBAL_KEY] = function(code)
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
if dfhack_flags.enable then
    state.enabled = dfhack_flags.enable_state
    persist_state()
    start()
elseif args[1] == 'now' then
    run_cycle(false)
elseif not args[1] or args[1] == 'status' then
    local count = 0
    for _, rule in pairs(state.rules) do
        if rule.enabled then count = count + 1 end
    end
    print(('autoassign-animals: %d enabled pasture rule(s)'):format(count))
else
    print('Configure pasture rules from the pasture interface, or run:')
    print('  autoassign-animals now')
    print('  autoassign-animals status')
end
