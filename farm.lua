local args = { ... }

local PROGRAM_VERSION = "4.8.1-empty-left-fix"
local DATABASE_FILE = "crop_profiles_v4_1.db"

local PLACEMENT_ACCESS_SIDE = "left"
local MANUAL_HARVEST_SIDE = "top"
local DISPENSER_SIDE = "right"

local GAME_TICK = 0.05

local BONE_MEAL_SIGNAL_TIME = 0.50
local BONE_MEAL_RESET_TIME = 0.15

local PLAYER_CHECK_DELAY = GAME_TICK
local RETRY_DELAY = GAME_TICK

local MANUAL_HARVEST_PULSE_INTERVAL = 1.50
local MANUAL_HARVEST_PULSE_TIME = 0.10

local MAX_LEARNING_PULSES = 256
local MIN_EMPTY_SLOTS_BEFORE_HARVEST = 3

local BUILTIN_CROPS = {
    ["minecraft:wheat"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:wheat_seeds",
        manualHarvest = true
    },
    ["minecraft:carrots"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:carrot",
        manualHarvest = true
    },
    ["minecraft:potatoes"] = {
        growthKey = "age",
        maximum = 7,
        seedItem = "minecraft:potato",
        manualHarvest = true
    },
    ["minecraft:beetroots"] = {
        growthKey = "age",
        maximum = 3,
        seedItem = "minecraft:beetroot_seeds",
        manualHarvest = true
    },
    ["minecraft:nether_wart"] = {
        growthKey = "age",
        maximum = 3,
        seedItem = "minecraft:nether_wart",
        manualHarvest = true
    }
}

local database = {
    version = 4,
    profiles = {}
}

local lastStatus = nil

local function status(message)
    if message ~= lastStatus then
        print(message)
        lastStatus = message
    end
end

local manualHarvestPulsesEnabled = false

local function setPlacementAccess(open)
    redstone.setOutput(PLACEMENT_ACCESS_SIDE, open)
end

local function setManualHarvestPulses(enabled)
    enabled = enabled == true

    if manualHarvestPulsesEnabled == enabled then
        return
    end

    manualHarvestPulsesEnabled = enabled

    if not enabled then
        redstone.setOutput(MANUAL_HARVEST_SIDE, false)
    end

    os.queueEvent("manual_harvest_pulse_state")
end

local function manualHarvestPulseLoop()
    redstone.setOutput(MANUAL_HARVEST_SIDE, false)

    while true do
        while not manualHarvestPulsesEnabled do
            os.pullEvent("manual_harvest_pulse_state")
        end

        if manualHarvestPulsesEnabled then
            redstone.setOutput(MANUAL_HARVEST_SIDE, true)
            sleep(MANUAL_HARVEST_PULSE_TIME)
            redstone.setOutput(MANUAL_HARVEST_SIDE, false)
        end

        if manualHarvestPulsesEnabled then
            local waitTime =
                MANUAL_HARVEST_PULSE_INTERVAL
                - MANUAL_HARVEST_PULSE_TIME

            local timer = os.startTimer(math.max(waitTime, 0))

            while manualHarvestPulsesEnabled do
                local event, id = os.pullEvent()

                if event == "timer" and id == timer then
                    break
                end

                if event == "manual_harvest_pulse_state"
                    and not manualHarvestPulsesEnabled then
                    break
                end
            end
        end
    end
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

local function pulseBoneMeal()
    redstone.setOutput(DISPENSER_SIDE, true)
    sleep(BONE_MEAL_SIGNAL_TIME)

    stopDispenser()
    sleep(BONE_MEAL_RESET_TIME)
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
        manualHarvest = definition.manualHarvest == true,
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
    setPlacementAccess(false)

    local growthKey = detectGrowthKey(initial)
    local current = initial

    status(
        "Learning unknown crop "
        .. initial.name
        .. ": "
        .. describeGrowth(initial, nil)
    )

    for pulseNumber = 1, MAX_LEARNING_PULSES do
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
                manualHarvest = true,
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
        if profile.manualHarvest == nil then
            profile.manualHarvest = true
            saveDatabase()
        end

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

local collectAvailableFrontDrops

local function growKnownPlant(profile)
    setPlacementAccess(false)

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

local function findEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end

    return nil
end

local function countEmptySlots()
    local count = 0

    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end

    return count
end

local function findExactItemSlot(itemName)
    if not itemName then
        return nil
    end

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)

        if detail and detail.name == itemName then
            return slot
        end
    end

    return nil
end

local function sameItem(first, second)
    if not first or not second then
        return false
    end

    return first.name == second.name
        and first.nbt == second.nbt
end

local function compactInventory()
    for sourceSlot = 16, 2, -1 do
        local source = turtle.getItemDetail(sourceSlot)

        if source then
            for targetSlot = 1, sourceSlot - 1 do
                local target = turtle.getItemDetail(targetSlot)

                if sameItem(source, target)
                    and turtle.getItemSpace(targetSlot) > 0 then

                    turtle.select(sourceSlot)
                    turtle.transferTo(targetSlot)

                    source = turtle.getItemDetail(sourceSlot)

                    if not source then
                        break
                    end
                end
            end
        end
    end

    turtle.select(1)
end

local function suckFrontOnce()
    turtle.select(1)
    return turtle.suck()
end

collectAvailableFrontDrops = function(maxAttempts)
    maxAttempts = maxAttempts or 4

    for _ = 1, maxAttempts do
        if not suckFrontOnce() then
            break
        end
    end

    turtle.select(1)
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

local function placeFromSlot(profile, slot, itemName)
    turtle.select(slot)

    local placed, reason = turtle.place()

    if not placed then
        turtle.select(1)
        return false, reason or ("Could not plant " .. itemName)
    end

    local planted = inspectFront()

    if not planted then
        turtle.select(1)
        return false, "Placement succeeded but no crop was detected"
    end

    if planted.name ~= profile.blockName then
        turtle.select(1)

        return false,
            "A different block was planted: "
            .. planted.name
    end

    if profile.seedItem ~= itemName then
        profile.seedItem = itemName
        saveDatabase()
    end

    turtle.select(1)
    return true
end

local function tryPlant(profile)
    if profile.seedItem then
        local exactSlot = findExactItemSlot(profile.seedItem)

        if not exactSlot then
            return false,
                "Missing planting item for "
                .. profile.blockName
                .. ": "
                .. profile.seedItem
        end

        return placeFromSlot(profile, exactSlot, profile.seedItem)
    end

    local candidates = sortedPlantingCandidates(profile)

    if #candidates == 0 then
        return false, "No planting item was found in the turtle inventory"
    end

    for _, candidate in ipairs(candidates) do
        local planted, reason =
            placeFromSlot(profile, candidate.slot, candidate.name)

        if planted then
            return true
        end

        if inspectFront() then
            return false, reason
        end
    end

    turtle.select(1)
    return false, "Could not plant any of the candidate items"
end

local function replant(profile)
    setManualHarvestPulses(false)

    while true do
        local front = inspectFront()

        if front then
            setPlacementAccess(false)

            if front.name == profile.blockName then
                setManualHarvestPulses(profile.manualHarvest)
                return true
            end

            status("A different block is in front: " .. front.name)
            return false
        end

        -- Keep the left output powered for the entire time that the
        -- planting position is empty.
        setPlacementAccess(true)

        local planted, reason = tryPlant(profile)

        if planted then
            setPlacementAccess(false)
            setManualHarvestPulses(profile.manualHarvest)
            status("Crop planted")
            return true
        end

        local picked = suckFrontOnce()

        if picked then
            local plantedAfterPickup = tryPlant(profile)

            if plantedAfterPickup then
                setPlacementAccess(false)
                setManualHarvestPulses(profile.manualHarvest)
                status("Crop planted")
                return true
            end
        else
            local manuallyPlaced = inspectFront()

            if manuallyPlaced then
                setPlacementAccess(false)

                if manuallyPlaced.name == profile.blockName then
                    setManualHarvestPulses(profile.manualHarvest)
                    status("Crop detected")
                    return true
                end

                status(
                    "A different block is in front: "
                    .. manuallyPlaced.name
                )
                return false
            end

            if countEmptySlots() == 0 then
                status(
                    "Crop position is empty; left access is ON. "
                    .. "Inventory is full and the planting item is missing"
                )
            else
                status(
                    "Crop position is empty; left access is ON. "
                    .. tostring(reason)
                )
            end

            sleep(GAME_TICK)
        end
    end
end

local function waitForPlayerHarvest(profile)
    setPlacementAccess(false)
    setManualHarvestPulses(profile.manualHarvest)

    collectAvailableFrontDrops(8)
    compactInventory()

    while countEmptySlots() < MIN_EMPTY_SLOTS_BEFORE_HARVEST do
        status(
            "Free at least "
            .. tostring(MIN_EMPTY_SLOTS_BEFORE_HARVEST)
            .. " turtle inventory slots before harvesting"
        )
        sleep(RETRY_DELAY)
    end

    status(
        "Mature: "
        .. profile.blockName
        .. ". Waiting for the player to break it"
    )

    while true do
        sleep(PLAYER_CHECK_DELAY)

        local current = inspectFront()

        if not current
            or current.name ~= profile.blockName
            or not isMature(current, profile) then

            setManualHarvestPulses(false)
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

        sleep(0)
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
        print("   player harvest: " .. tostring(profile.manualHarvest))
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
        version = 4,
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

local function farmLoop()
    while true do
        local block = inspectFront()

        if not block then
            setManualHarvestPulses(false)

            repeat
                -- Reassert the left output every game tick while empty.
                setPlacementAccess(true)
                status("No crop detected; left placement access is ON")
                sleep(GAME_TICK)
                block = inspectFront()
            until block

            setPlacementAccess(false)
        end

        local profile = getOrCreateProfile(block)

        setPlacementAccess(false)
        setManualHarvestPulses(profile.manualHarvest)

        runProfile(profile)
    end
end

local function main()
    loadDatabase()

    if runCommand() then
        return
    end

    stopDispenser()
    setManualHarvestPulses(false)
    redstone.setOutput(MANUAL_HARVEST_SIDE, false)

    if inspectFront() then
        setPlacementAccess(false)
    else
        setPlacementAccess(true)
    end

    print("CropFarm " .. PROGRAM_VERSION)
    print("Right bone-meal signal: 0.50s on, 0.15s off")
    print("Left is continuously ON whenever the crop position is empty")
    print("Left turns off when a crop appears")
    print("Top pulses every 1.50s for player-harvest crops")
    print("Top pulse width: 0.10s")
    print("No chest is used")
    print("The turtle does not rotate")
    print("Press Ctrl+T to stop")

    parallel.waitForAny(
        farmLoop,
        manualHarvestPulseLoop
    )
end

local function onError(message)
    stopDispenser()
    setPlacementAccess(false)
    setManualHarvestPulses(false)
    redstone.setOutput(MANUAL_HARVEST_SIDE, false)

    printError(tostring(message))
    printError(debug.traceback())
end

local ok, errorMessage = xpcall(main, onError)

if not ok then
    stopDispenser()
    setPlacementAccess(false)
    setManualHarvestPulses(false)
    redstone.setOutput(MANUAL_HARVEST_SIDE, false)
end
