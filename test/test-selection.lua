dfhack_flags = {module = true}

df = {
    unit_relationship_type = {Pet = 1},
}

dfhack = {
    buildings = {},
    gui = {},
    units = {},
    onStateChange = {},
    isMapLoaded = function() return false end,
    isWorldLoaded = function() return false end,
}

SC_MAP_LOADED = 1
SC_MAP_UNLOADED = 2
DEFAULT_NIL = nil

local function class(base)
    local cls = {super=base}
    cls.__index = cls
    cls.ATTRS = function() end
    return cls
end

defclass = function(_, base) return class(base) end

package.preload['gui'] = function()
    return {FramedScreen=class()}
end

package.preload['gui.widgets'] = function()
    local function widget() return function(args) return args end end
    return {
        CycleHotkeyLabel=widget(),
        FilteredList=widget(),
        HotkeyLabel=widget(),
        Label=widget(),
        ToggleHotkeyLabel=widget(),
    }
end

package.preload['plugins.overlay'] = function()
    return {OverlayWidget=class()}
end

package.preload['repeat-util'] = function()
    return {cancel=function() end, repeating={}}
end

package.preload['utils'] = function()
    return {insert_sorted=function() end}
end

local function flag(name)
    dfhack.units[name] = function(unit) return unit[name] or false end
end

for _, name in ipairs{
    'isAnimal', 'isOwnCiv', 'isAlive', 'isMerchant', 'isGrazer',
    'isBaby', 'isChild', 'isAdult',
} do
    flag(name)
end

dofile('autocage-juveniles.lua')
dofile('autoassign-animals.lua')

local function animal(overrides)
    local unit = {
        isAnimal=true,
        isOwnCiv=true,
        isAlive=true,
        isChild=true,
        race=7,
        sex=0,
        relationship_ids={[-1]=-1, [1]=-1},
    }
    for key, value in pairs(overrides or {}) do unit[key] = value end
    return unit
end

assert(is_cage_candidate(animal()))
assert(not is_cage_candidate(animal{isGrazer=true}))
assert(not is_cage_candidate(animal{isAdult=true, isChild=false}))
assert(not is_cage_candidate(animal{relationship_ids={[1]=42}}))
assert(not is_cage_candidate(animal{isMerchant=true}))
assert(is_cage_candidate(animal{isMarkedForSlaughter=true}))

assert(should_release(animal{isAdult=true, isChild=false}))
assert(should_release(animal{isGrazer=true}))
assert(should_release(animal{relationship_ids={[1]=42}}))
assert(should_release(animal{isAlive=false}))
assert(not should_release(animal{isMarkedForSlaughter=true}))
assert(not should_release(animal()))

local either_female = {race=7, sex=-1}
local male_only = {race=7, sex=1}
assert(matches_rule(animal{isAdult=true, isChild=false}, either_female))
assert(not matches_rule(animal{isAdult=true, isChild=false}, male_only))
assert(matches_rule(animal{isAdult=true, isChild=false, sex=1}, male_only))
assert(not matches_rule(animal{isAdult=true, isChild=false, race=8}, either_female))
assert(matches_rule(animal{
    isAdult=true, isChild=false, isMarkedForSlaughter=true}, either_female))

print('selection tests passed')
