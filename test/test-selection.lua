dfhack_flags = {module = true}

df = {}

dfhack = {
    units = {},
    onStateChange = {},
}

DEFAULT_NIL = {}
COLOR_GREEN = 2
COLOR_RED = 4

function defclass(_, base)
    local cls = {super=base or {}}
    cls.ATTRS = function() end
    return setmetatable(cls, {
        __call=function(_, attrs) return attrs or {} end,
    })
end

package.preload['repeat-util'] = function()
    return {cancel = function() end, repeating = {}}
end

package.preload['utils'] = function()
    return {
        assign = function() end,
        insert_sorted = function() end,
    }
end

package.preload['gui'] = function()
    return {ZScreenModal={}}
end

package.preload['plugins.overlay'] = function()
    return {OverlayWidget={}}
end

package.preload['gui.widgets'] = function()
    local function widget(attrs) return attrs or {} end
    return {
        Window=widget,
        Label=widget,
        FilteredList=widget,
        CycleHotkeyLabel=widget,
        ToggleHotkeyLabel=widget,
        HotkeyLabel=widget,
        TextButton=widget,
    }
end

local function flag(name)
    dfhack.units[name] = function(unit) return unit[name] or false end
end

for _, name in ipairs{
    'isAnimal', 'isOwnCiv', 'isAlive', 'isMerchant', 'isGrazer',
    'isBaby', 'isChild', 'isAdult', 'isPet',
} do
    flag(name)
end

SC_MAP_LOADED = 1
SC_MAP_UNLOADED = 2

dofile('autocage-juveniles.lua')

local function animal(overrides)
    local unit = {
        isAnimal = true,
        isOwnCiv = true,
        isAlive = true,
        isChild = true,
    }
    for key, value in pairs(overrides or {}) do unit[key] = value end
    return unit
end

assert(is_cage_candidate(animal()))
assert(not is_cage_candidate(animal{isGrazer = true}))
assert(not is_cage_candidate(animal{isAdult = true, isChild = false}))
assert(not is_cage_candidate(animal{isPet = true}))
assert(not is_cage_candidate(animal{isMerchant = true}))
assert(is_cage_candidate(animal{isMarkedForSlaughter = true}))

assert(should_release(animal{isAdult = true, isChild = false}))
assert(should_release(animal{isGrazer = true}))
assert(should_release(animal{isPet = true}))
assert(should_release(animal{isAlive = false}))
assert(not should_release(animal{isMarkedForSlaughter = true}))
assert(not should_release(animal()))

dofile('autoassign-animals.lua')

assert(matches_rule(animal{race=7, sex=0, isAdult=true, isChild=false},
    {race=7, sex=0}))
assert(matches_rule(animal{race=7, sex=1, isAdult=true, isChild=false},
    {race=7, sex=-1}))
assert(not matches_rule(animal{race=8, sex=0, isAdult=true, isChild=false},
    {race=7, sex=0}))
assert(not matches_rule(animal{race=7, sex=1, isAdult=true, isChild=false},
    {race=7, sex=0}))
assert(not matches_rule(animal{race=7, sex=0, isAdult=false, isChild=true},
    {race=7, sex=0}))
assert(matches_rule(
    animal{race=7, sex=0, isAdult=true, isChild=false, isMarkedForSlaughter=true},
    {race=7, sex=0}))

print('selection tests passed')
