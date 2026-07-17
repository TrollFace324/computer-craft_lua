local args = { ... }

local PROGRAM_VERSION = "3.2-ascii-only"
local DATABASE_FILE = "crop_profiles_v3.db"

local LOCK_SIDE = "top"
local DISPENSER_SIDE = "right"
local CHEST_SIDE = "bottom"

local BONE_MEAL = "minecraft:bone_meal"

local PULSE_TIME = 0.12
local AFTER_PULSE_DELAY = 0.40
local PLAYER_CHECK_DELAY = 0.05
local DROP_SETTLE_DELAY = 0.60
local RETRY_DELAY = 1.00

local MAX_LEARNING_PULSES = 256
local MAX_PULL_OPERATIONS = 64

local BUILTIN_CROPS = {
    ["minecraft:wheat"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:wheat_seeds"
    },
    ["minecraft:carrots"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:carrot"
    },
    ["minecraft:potatoes"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:potato"
    },
    ["minecraft:beetroots"] = {
        growthKey = "age",
        maximum = 3,
        seedItem = "minecraft:beetroot_seeds"
    },
    ["minecraft:nether_wart"] = {
        growthKey = "age",
        maximum = 3,
        seedItem = "minecraft:nether_wart"
    }
}

local database = {
    version = 3,
    profiles = {}
}

local lastStatus = nil

local function status(message)
    if message ~= lastStatus then
        print(message)
        lastStatus = message
    end
end

local function setLocked(locked)
    redstone.setOutput(LOCK_SIDE, locked)
end

local function stopDispenser()
    redstone.setOutput(DISPENSER_SIDE, false)
end

local function copyTable(source)
    local result = {}

    for key, value in pairs(source or {}) do
        result[key] = value
    end

    return result
end

local function tablesEqual(first, second)
    first = first or {}
    second = second or {}

    for key, value in pairs(first) do
        if second[key] ~= value then
            return false
        end
    end

    for key, value in pairs(second) do
        if first[key] ~= value then
            return false
        end
    end

    return true
end

local function inspectFront()
    local exists, data = turtle.inspect()

    if not exists then
        return nil
    end

    return {
        name = data.name,
        state = copyTable(data.state)
    }
end

local function describeBlock(block)
    if not block then
        return "air"
    end

    return block.name .. " " .. textutils.serialize(block.state or {})
end

local function describeGrowth(block, profile)
    if not block then
        return "no block"
    end

    if profile and profile.growthKey then
        return profile.growthKey
            .. "="
            .. tostring(block.state[profile.growthKey])
            .. "/"
            .. tostring(profile.maximum)
    end

    if block.state.age ~= nil then
        return "age=" .. tostring(block.state.age)
    end

    return textutils.serialize(block.state)
end

local function loadDatabase()
    if not fs.exists(DATABASE_FILE) then
        return
    end

    local handle = fs.open(DATABASE_FILE, "r")

    if not handle then
        return
    end

    local content = handle.readAll()
    handle.close()

    local loaded = textutils.unserialize(content)

    if type(loaded) == "table"
        and type(loaded.profiles) == "table" then
        database = loaded
    end
end

local function saveDatabase()
    local handle = fs.open(DATABASE_FILE, "w")

    if not handle then
        error("Could not write " .. DATABASE_FILE)
    end

    handle.write(textutils.serialize(database))
    handle.close()
end

local function inventoryAt(side)
    if not peripheral.isPresent(side) then
        return nil
    end

    if not peripheral.hasType(side, "inventory") then
        return nil
    end

    return peripheral.wrap(side)
end

local function waitForEquipment()
    while not inventoryAt(DISPENSER_SIDE) do
        setLocked(true)
        status("No dispenser found on the right")
        sleep(RETRY_DELAY)
    end

    while not inventoryAt(CHEST_SIDE) do
        setLocked(true)
        status("No chest found below the turtle")
        sleep(RETRY_DELAY)
    end
end

local function dispenserHasBoneMeal()
    local dispenser = inventoryAt(DISPENSER_SIDE)

    if not dispenser then
        return false
    end

    for _, item in pairs(dispenser.list()) do
        if item.name == BONE_MEAL and item.count > 0 then
            return true
        end
    end

    return false
end

local function waitForBoneMeal()
    while not dispenserHasBoneMeal() do
        setLocked(true)
        status("Add bone meal to the dispenser on the right")
        sleep(RETRY_DELAY)
    end
end

local function pulseBoneMeal()
    stopDispenser()
    sleep(0.05)

    redstone.setOutput(DISPENSER_SIDE, true)
    sleep(PULSE_TIME)

    stopDispenser()
    sleep(AFTER_PULSE_DELAY)
end

local function findProfileByName(blockName)
    for index, profile in ipairs(database.profiles) do
        if profile.blockName == blockName then
            return profile, index
        end
    end

    return nil, nil
end

local function addBuiltinProfile(block)
    local definition = BUILTIN_CROPS[block.name]

    if not definition then
        return nil
    end

    local profile = {
        blockName = block.name,
        growthKey = definition.growthKey,
        maximum = definition.maximum,
        matureState = nil,
        seedItem = definition.seedItem,
        builtin = true
    }

    database.profiles[#database.profiles + 1] = profile
    saveDatabase()

    status(
        "Known crop: "
        .. block.name
        .. ", maximum "
        .. profile.growthKey
        .. "="
        .. tostring(profile.maximum)
    )

    return profile
end

local function sameGrowth(before, after, growthKey)
    if not before or not after then
        return false
    end

    if before.name ~= after.name then
        return false
    end

    if growthKey then
        return before.state[growthKey] == after.state[growthKey]
    end

    return tablesEqual(before.state, after.state)
end

local function detectGrowthKey(block)
    if block.state.age ~= nil then
        return "age"
    end

    local preferredNames = {
        "stage",
        "growth",
        "maturity",
        "level"
    }

    for _, key in ipairs(preferredNames) do
        if block.state[key] ~= nil then
            return key
        end
    end

    return nil
end

local function learnUnknownPlant(initial)
    setLocked(true)

    local growthKey = detectGrowthKey(initial)
    local current = initial

    status(
        "Learning unknown crop "
        .. initial.name
        .. ": "
        .. describeGrowth(initial, nil)
    )

    for pulseNumber = 1, MAX_LEARNING_PULSES do
        waitForBoneMeal()

        local before = current

        pulseBoneMeal()

        local after = inspectFront()

        if not after then
            error("The crop disappeared during learning")
        end

        if after.name ~= initial.name then
            error(
                "The block changed during learning: "
                .. initial.name
                .. " -> "
                .. after.name
            )
        end

        if not sameGrowth(before, after, growthKey) then
            current = after

            status(
                "Learning: "
                .. describeGrowth(before, nil)
                .. " -> "
                .. describeGrowth(after, nil)
            )
        else
            local profile = {
                blockName = initial.name,
                growthKey = growthKey,
                maximum = growthKey and after.state[growthKey] or nil,
                matureState = growthKey and nil or copyTable(after.state),
                seedItem = nil,
                builtin = false
            }

            database.profiles[#database.profiles + 1] = profile
            saveDatabase()

            if growthKey then
                status(
                    "Maximum stored: "
                    .. growthKey
                    .. "="
                    .. tostring(profile.maximum)
                )
            else
                status(
                    "Maximum state stored: "
                    .. textutils.serialize(profile.matureState)
                )
            end

            return profile
        end
    end

    error(
        "Could not finish learning after "
        .. tostring(MAX_LEARNING_PULSES)
        .. " pulses"
    )
end

local function getOrCreateProfile(block)
    local profile = findProfileByName(block.name)

    if profile then
        return profile
    end

    profile = addBuiltinProfile(block)

    if profile then
        return profile
    end

    return learnUnknownPlant(block)
end

local function isMature(block, profile)
    if not block or block.name ~= profile.blockName then
        return false
    end

    if profile.growthKey then
        local current = block.state[profile.growthKey]
        local maximum = profile.maximum

        if current == nil or maximum == nil then
            return false
        end

        if type(current) == "number"
            and type(maximum) == "number" then
            return current >= maximum
        end

        return current == maximum
    end

    return tablesEqual(block.state, profile.matureState)
end

local function growKnownPlant(profile)
    setLocked(true)

    while true do
        local before = inspectFront()

        if not before then
            return "missing"
        end

        if before.name ~= profile.blockName then
            return "different"
        end

        if isMature(before, profile) then
            status(
                "Growth complete: "
                .. describeGrowth(before, profile)
            )
            return "mature"
        end

        waitForBoneMeal()

        status(
            "Growing "
            .. before.name
            .. ": "
            .. describeGrowth(before, profile)
        )

        pulseBoneMeal()

        local after = inspectFront()

        if not after then
            return "missing"
        end

        if after.name ~= profile.blockName then
            return "different"
        end

        if isMature(after, profile) then
            status(
                "Growth complete: "
                .. describeGrowth(after, profile)
            )
            return "mature"
        end
    end
end

local function dumpInventoryDown()
    local allDropped = true

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)

            if not turtle.dropDown() then
                allDropped = false
            end
        end
    end

    turtle.select(1)
    return allDropped
end

local function findEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end

    return nil
end

local function pullFromChest()
    if not dumpInventoryDown() then
        return false, "The chest below is full"
    end

    local pulls = 0

    for _ = 1, MAX_PULL_OPERATIONS do
        local slot = findEmptySlot()

        if not slot then
            break
        end

        turtle.select(slot)

        if not turtle.suckDown() then
            break
        end

        pulls = pulls + 1
    end

    turtle.select(1)
    return true, pulls
end

local function itemPath(itemName)
    local colon = string.find(itemName, ":", 1, true)

    if colon then
        return string.sub(itemName, colon + 1)
    end

    return itemName
end

local function plantingScore(itemName, profile)
    if profile.seedItem then
        if itemName == profile.seedItem then
            return 100000
        end

        return -1
    end

    local lower = string.lower(itemName)
    local score = 0

    if string.find(lower, "seed", 1, true) then
        score = score + 10000
    end

    local cropWords = {
        "wheat",
        "carrot",
        "potato",
        "beetroot",
        "wart",
        "berry",
        "leek",
        "grain",
        "herb",
        "mint",
        "nut",
        "root",
        "vivichoke",
        "sapling"
    }

    for _, word in ipairs(cropWords) do
        if string.find(lower, word, 1, true) then
            score = score + 3000
        end
    end

    local blockPath = string.lower(itemPath(profile.blockName))
    blockPath = string.gsub(blockPath, "_crop$", "")
    blockPath = string.gsub(blockPath, "_plant$", "")
    blockPath = string.gsub(blockPath, "_bush$", "")
    blockPath = string.gsub(blockPath, "s$", "")

    if #blockPath >= 4
        and string.find(lower, blockPath, 1, true) then
        score = score + 6000
    end

    return score
end

local function sortedPlantingCandidates(profile)
    local result = {}

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)

        if detail then
            local score = plantingScore(detail.name, profile)

            if score > 0 then
                result[#result + 1] = {
                    slot = slot,
                    name = detail.name,
                    score = score
                }
            end
        end
    end

    table.sort(result, function(first, second)
        if first.score == second.score then
            return first.slot < second.slot
        end

        return first.score > second.score
    end)

    return result
end

local function tryPlant(profile)
    local candidates = sortedPlantingCandidates(profile)

    if #candidates == 0 then
        return false, "No planting item was found in the chest"
    end

    for _, candidate in ipairs(candidates) do
        turtle.select(candidate.slot)

        turtle.place()
        sleep(0.20)

        local planted = inspectFront()

        if planted then
            if planted.name == profile.blockName then
                if profile.seedItem ~= candidate.name then
                    profile.seedItem = candidate.name
                    saveDatabase()
                end

                turtle.select(1)
                return true
            end

            turtle.select(1)

            return false,
                "A different block was planted: "
                .. planted.name
        end
    end

    turtle.select(1)
    return false, "Could not plant any of the candidate items"
end

local function replant(profile)
    setLocked(true)

    while true do
        local front = inspectFront()

        if front then
            if front.name == profile.blockName then
                return true
            end

            status("A different block is in front: " .. front.name)
            return false
        end

        status("Waiting for planting items in the chest below")

        local pulled, result = pullFromChest()

        if not pulled then
            status(tostring(result))
            sleep(RETRY_DELAY)
        elseif result == 0 then
            sleep(RETRY_DELAY)
        else
            local planted, reason = tryPlant(profile)

            if not dumpInventoryDown() then
                status("The chest below is full")
                sleep(RETRY_DELAY)
            elseif planted then
                status("Crop planted")
                return true
            else
                status(reason)
                sleep(RETRY_DELAY)
            end
        end
    end
end

local function waitForPlayerHarvest(profile)
    setLocked(false)

    status(
        "Mature: "
        .. profile.blockName
        .. ". Piston unlocked; break the crop"
    )

    while true do
        sleep(PLAYER_CHECK_DELAY)

        local current = inspectFront()

        if not current
            or current.name ~= profile.blockName
            or not isMature(current, profile) then

            setLocked(true)
            sleep(DROP_SETTLE_DELAY)
            return
        end
    end
end

local function runProfile(profile)
    while true do
        local block = inspectFront()

        if not block then
            if not replant(profile) then
                return
            end
        elseif block.name ~= profile.blockName then
            return
        elseif isMature(block, profile) then
            waitForPlayerHarvest(profile)
        else
            local result = growKnownPlant(profile)

            if result == "different" then
                return
            elseif result == "missing" then
                if not replant(profile) then
                    return
                end
            elseif result == "mature" then
                waitForPlayerHarvest(profile)
            end
        end

        sleep(0.05)
    end
end

local function printProfiles()
    if #database.profiles == 0 then
        print("No learned crops")
        return
    end

    for index, profile in ipairs(database.profiles) do
        print(tostring(index) .. ". " .. profile.blockName)

        if profile.growthKey then
            print(
                "   maximum: "
                .. profile.growthKey
                .. "="
                .. tostring(profile.maximum)
            )
        else
            print(
                "   maximum: "
                .. textutils.serialize(profile.matureState)
            )
        end

        print("   planting item: " .. tostring(profile.seedItem))
        print("   built-in profile: " .. tostring(profile.builtin))
    end
end

local function commandInspect()
    local block = inspectFront()
    print(describeBlock(block))
end

local function commandForget()
    local block = inspectFront()

    if not block then
        print("No crop in front")
        return
    end

    local _, index = findProfileByName(block.name)

    if not index then
        print("No profile found for this crop")
        return
    end

    table.remove(database.profiles, index)
    saveDatabase()

    print("Profile removed: " .. block.name)
end

local function commandReset()
    if fs.exists(DATABASE_FILE) then
        fs.delete(DATABASE_FILE)
    end

    database = {
        version = 3,
        profiles = {}
    }

    print("Profile database deleted")
end

local function commandSeed()
    local block = inspectFront()

    if not block then
        print("No crop in front")
        return
    end

    local profile = findProfileByName(block.name)

    if not profile then
        print("Run the farm first to create a crop profile")
        return
    end

    local selectedSlot = turtle.getSelectedSlot()
    local detail = turtle.getItemDetail(selectedSlot)

    if not detail then
        print("Select a slot containing the planting item")
        return
    end

    profile.seedItem = detail.name
    saveDatabase()

    print("Planting item: " .. detail.name)
end

local function runCommand()
    if args[1] == "list" then
        printProfiles()
        return true
    elseif args[1] == "inspect" then
        commandInspect()
        return true
    elseif args[1] == "forget" then
        commandForget()
        return true
    elseif args[1] == "reset" then
        commandReset()
        return true
    elseif args[1] == "seed" then
        commandSeed()
        return true
    end

    return false
end

local function main()
    loadDatabase()

    if runCommand() then
        return
    end

    stopDispenser()
    setLocked(true)

    print("CropFarm " .. PROGRAM_VERSION)
    print("Shears are not required")
    print("The turtle does not rotate")
    print("Press Ctrl+T to stop")

    waitForEquipment()

    while true do
        local block = inspectFront()

        if not block then
            setLocked(false)
            status("Place a crop in front of the turtle")

            repeat
                sleep(0.20)
                block = inspectFront()
            until block

            setLocked(true)
        end

        local profile = getOrCreateProfile(block)
        runProfile(profile)
    end
end

local function onError(message)
    stopDispenser()
    setLocked(true)

    printError(tostring(message))
    printError(debug.traceback())
end

local ok, errorMessage = xpcall(main, onError)

if not ok then
    stopDispenser()
    setLocked(true)
end
