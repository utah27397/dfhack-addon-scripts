dfhack_flags = {module = true}

df = {}

dfhack = {
    units = {},
    onStateChange = {},
}

package.preload['repeat-util'] = function()
    return {cancel = function() end, repeating = {}}
end

package.preload['utils'] = function()
    return {assign = function() end}
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

assert(should_release(animal{isAdult = true, isChild = false}))
assert(should_release(animal{isGrazer = true}))
assert(should_release(animal{isPet = true}))
assert(should_release(animal{isAlive = false}))
assert(not should_release(animal()))

print('selection tests passed')
