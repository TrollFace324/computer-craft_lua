-- Adaptive one-block crop controller for CC:Tweaked
-- Layout while the turtle faces the plant:
--   front = plant
--   right = dispenser aimed at the plant
--   back  = output chest
--   top   = redstone-controlled piston/lock
--
-- Put bone meal in the dispenser and at least one pair of shears
-- in the turtle inventory. Keep the remaining turtle slots empty.
--
-- Commands:
--   farm          start
--   farm list     show learned profiles
--   farm forget   forget the profile of the plant in front
--   farm reset    delete all learned profiles

local args = { ... }

local DB_FILE = "plant_profiles.db"

local LOCK_SIDE = "top"
local DISPENSER_SIDE = "right"

local BONE_MEAL = "minecraft:bone_meal"
local SHEARS = "minecraft:shears"

local REDSTONE_ON_TIME = 0.12
local DISPENSER_SETTLE_TIME = 0.35
local PLAYER_POLL_TIME = 0.05
local CHEST_SETTLE_TIME = 0.40

-- A single use of bone meal can occasionally fail on an immature crop.
-- The crop is considered stable only after this many consecutive
-- attempts without any block-state change.
local STABLE_ATTEMPTS = 12
local MAX_TRAIN_PULSES = 160
local MAX_INVENTORY_PULLS = 16

local db = {
    version = 1,
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

local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

local function inspectFront()
    local ok, data = turtle.inspect()

    if not ok then
        return nil
    end

    local state = {}
    for key, value in pairs(data.state or {}) do
        state[key] = value
    end

    return {
        name = data.name,
        state = state
    }
end

local function cloneBlock(block)
    if not block then
        return nil
    end

    local state = {}
    for key, value in pairs(block.state or {}) do
        state[key] = value
    end

    return {
        name = block.name,
        state = state
    }
end

local function sameTable(first, second)
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

local function sameBlock(first, second)
    if first == nil or second == nil then
        return first == second
    end

    return first.name == second.name
        and sameTable(first.state, second.state)
end

local function loadDatabase()
    if not fs.exists(DB_FILE) then
        return
    end

    local handle = fs.open(DB_FILE, "r")
    if not handle then
        return
    end

    local content = handle.readAll()
    handle.close()

    local loaded = textutils.unserialize(content)
    if type(loaded) == "table"
        and type(loaded.profiles) == "table" then
        db = loaded
    end
end

local function saveDatabase()
    local handle = fs.open(DB_FILE, "w")
    if not handle then
        error("Cannot write " .. DB_FILE)
    end

    handle.write(textutils.serialize(db))
    handle.close()
end

local function countKeys(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function profileMatchesBlock(profile, block)
    if not block then
        return false
    end

    if not profile.aliases
        or not profile.aliases[block.name] then
        return false
    end

    for key, value in pairs(profile.identity or {}) do
        if block.state[key] ~= value then
            return false
        end
    end

    return true
end

local function findProfile(block)
    local bestProfile = nil
    local bestIndex = nil
    local bestSpecificity = -1

    for index, profile in ipairs(db.profiles) do
        if profileMatchesBlock(profile, block) then
            local specificity = countKeys(profile.identity)
            if specificity > bestSpecificity then
                bestSpecificity = specificity
                bestProfile = profile
                bestIndex = index
            end
        end
    end

    return bestProfile, bestIndex
end

local function isMature(block, profile)
    if not profileMatchesBlock(profile, block) then
        return false
    end

    if profile.requireMatureName
        and block.name ~= profile.matureName then
        return false
    end

    local hasGrowthKey = false

    for key in pairs(profile.growthKeys or {}) do
        hasGrowthKey = true

        local current = block.state[key]
        local target = profile.matureState[key]

        if type(current) == "number"
            and type(target) == "number" then
            if current < target then
                return false
            end
        elseif current ~= target then
            return false
        end
    end

    if not hasGrowthKey then
        return sameTable(block.state, profile.matureState)
    end

    return true
end

local function findItem(itemName)
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == itemName then
            return slot
        end
    end

    return nil
end

local function findEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end

    return nil
end

local function inventoryContainsOtherThanShears()
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name ~= SHEARS then
            return true
        end
    end

    return false
end

local function dumpToChestExceptShears()
    turnAround()

    local allDropped = true

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)

        if detail and detail.name ~= SHEARS then
            turtle.select(slot)

            if not turtle.drop() then
                allDropped = false
            end
        end
    end

    turnAround()
    return allDropped
end

local function collectFrontDrops()
    for _ = 1, 8 do
        local empty = findEmptySlot()
        if not empty then
            return
        end

        turtle.select(empty)

        if not turtle.suck() then
            return
        end

        sleep(0.05)
    end
end

local function rightInventory()
    if not peripheral.isPresent(DISPENSER_SIDE) then
        return nil
    end

    if not peripheral.hasType(DISPENSER_SIDE, "inventory") then
        return nil
    end

    return peripheral.wrap(DISPENSER_SIDE)
end

local function dispenserHasBoneMeal()
    local inventory = rightInventory()

    -- Some servers disable generic inventory peripherals.
    -- In that case, allow the pulse and rely on observed state changes.
    if not inventory then
        return nil
    end

    for _, item in pairs(inventory.list()) do
        if item.name == BONE_MEAL and item.count > 0 then
            return true
        end
    end

    return false
end

local function pulseDispenser()
    redstone.setOutput(DISPENSER_SIDE, false)
    sleep(0.05)

    redstone.setOutput(DISPENSER_SIDE, true)
    sleep(REDSTONE_ON_TIME)

    redstone.setOutput(DISPENSER_SIDE, false)
    sleep(DISPENSER_SETTLE_TIME)
end

local function pullOneStackFromFrontInventory()
    local empty = findEmptySlot()
    if not empty then
        return false, "Turtle inventory is full"
    end

    turtle.select(empty)

    local ok, reason = turtle.suck()
    if not ok then
        return false, reason
    end

    return true
end

local function pullAllFromFrontInventory(limit)
    for _ = 1, limit do
        local ok = pullOneStackFromFrontInventory()
        if not ok then
            return true
        end
    end

    return true
end

local function restoreNonShearsToFrontInventory()
    local success = true

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)

        if detail and detail.name ~= SHEARS then
            turtle.select(slot)

            if not turtle.drop() then
                success = false
            end
        end
    end

    return success
end

-- Temporarily replaces the dispenser's contents with shears,
-- fires it once, then restores its original contents.
local function harvestWithDispenserShears(profile)
    setLocked(true)

    if not dumpToChestExceptShears() then
        return false, "Back chest is full"
    end

    local shearsSlot = findItem(SHEARS)
    if not shearsSlot then
        return false, "Put shears in the turtle inventory"
    end

    local before = inspectFront()
    if not before then
        return false, "No plant in front"
    end

    -- Face the dispenser.
    turtle.turnRight()

    -- Pull its current contents, normally bone meal.
    pullAllFromFrontInventory(MAX_INVENTORY_PULLS)

    shearsSlot = findItem(SHEARS)
    if not shearsSlot then
        restoreNonShearsToFrontInventory()
        turtle.turnLeft()
        return false, "Shears were not found after emptying dispenser"
    end

    turtle.select(shearsSlot)
    if not turtle.drop(1) then
        restoreNonShearsToFrontInventory()
        turtle.turnLeft()
        return false, "Could not put shears into dispenser"
    end

    -- Face the plant again and fire the dispenser.
    turtle.turnLeft()
    pulseDispenser()

    local after = inspectFront()

    -- Retrieve the shears and restore bone meal.
    turtle.turnRight()
    pullAllFromFrontInventory(MAX_INVENTORY_PULLS)
    local restored = restoreNonShearsToFrontInventory()
    turtle.turnLeft()

    if not restored then
        return false, "Could not restore dispenser contents"
    end

    local changed = after ~= nil
        and profile.aliases[after.name]
        and not sameBlock(before, after)

    if changed then
        collectFrontDrops()
        dumpToChestExceptShears()
    end

    return changed, nil
end

local function unionChangedStateKeys(history)
    local changed = {}

    for index = 2, #history do
        local previous = history[index - 1].state or {}
        local current = history[index].state or {}
        local seen = {}

        for key in pairs(previous) do
            seen[key] = true
        end

        for key in pairs(current) do
            seen[key] = true
        end

        for key in pairs(seen) do
            if previous[key] ~= current[key] then
                changed[key] = true
            end
        end
    end

    return changed
end

local function inferGrowthKeys(history)
    local changed = unionChangedStateKeys(history)
    local preferred = {}

    for key in pairs(changed) do
        local lower = string.lower(key)

        if string.find(lower, "age", 1, true)
            or string.find(lower, "stage", 1, true)
            or string.find(lower, "growth", 1, true)
            or string.find(lower, "matur", 1, true) then
            preferred[key] = true
        end
    end

    if next(preferred) then
        return preferred
    end

    local numericIncreasing = {}

    for key in pairs(changed) do
        local previousValue = nil
        local valid = true
        local increased = false

        for _, block in ipairs(history) do
            local value = block.state[key]

            if value ~= nil then
                if type(value) ~= "number" then
                    valid = false
                    break
                end

                if previousValue ~= nil then
                    if value < previousValue then
                        valid = false
                        break
                    elseif value > previousValue then
                        increased = true
                    end
                end

                previousValue = value
            end
        end

        if valid and increased then
            numericIncreasing[key] = true
        end
    end

    if next(numericIncreasing) then
        return numericIncreasing
    end

    if next(changed) then
        return changed
    end

    -- The crop may already have been mature when learning started.
    -- Prefer common growth-like property names from the final state.
    local finalState = history[#history].state or {}

    for key in pairs(finalState) do
        local lower = string.lower(key)

        if string.find(lower, "age", 1, true)
            or string.find(lower, "stage", 1, true)
            or string.find(lower, "growth", 1, true)
            or string.find(lower, "matur", 1, true) then
            preferred[key] = true
        end
    end

    if next(preferred) then
        return preferred
    end

    -- Last-resort fallback: compare all state fields.
    for key in pairs(finalState) do
        preferred[key] = true
    end

    return preferred
end

local function buildIdentity(initial, mature, growthKeys)
    local identity = {}
    local seen = {}

    for key in pairs(initial.state or {}) do
        seen[key] = true
    end

    for key in pairs(mature.state or {}) do
        seen[key] = true
    end

    for key in pairs(seen) do
        if not growthKeys[key]
            and initial.state[key] == mature.state[key] then
            identity[key] = mature.state[key]
        end
    end

    return identity
end

local function learnPlant(initial)
    setLocked(true)

    status("Learning " .. initial.name)

    local history = { cloneBlock(initial) }
    local aliases = {
        [initial.name] = true
    }

    local current = cloneBlock(initial)
    local stable = 0
    local pulses = 0
    local nameChanged = false

    while stable < STABLE_ATTEMPTS
        and pulses < MAX_TRAIN_PULSES do

        local hasBoneMeal = dispenserHasBoneMeal()

        if hasBoneMeal == false then
            status("Add bone meal to the right dispenser")
            sleep(2)
        else
            pulseDispenser()
            pulses = pulses + 1

            local after = inspectFront()

            if not after then
                error("Plant disappeared while learning")
            end

            aliases[after.name] = true

            if after.name ~= initial.name then
                nameChanged = true
            end

            if sameBlock(current, after) then
                stable = stable + 1
                status(
                    "Learning: stable attempt "
                    .. stable
                    .. "/"
                    .. STABLE_ATTEMPTS
                )
            else
                history[#history + 1] = cloneBlock(after)
                current = cloneBlock(after)
                stable = 0

                status(
                    "Learning: new state detected ("
                    .. #history
                    .. " states)"
                )
            end
        end
    end

    if stable < STABLE_ATTEMPTS then
        error("Learning limit reached before a stable state was found")
    end

    local growthKeys = inferGrowthKeys(history)
    local mature = cloneBlock(current)

    local profile = {
        id = "profile_" .. tostring(#db.profiles + 1),
        aliases = aliases,
        identity = buildIdentity(initial, mature, growthKeys),
        growthKeys = growthKeys,
        matureName = mature.name,
        matureState = mature.state,
        requireMatureName = nameChanged,
        mode = nil,
        seedItem = nil
    }

    db.profiles[#db.profiles + 1] = profile
    saveDatabase()

    status("Testing whether dispenser shears can harvest it")

    while not findItem(SHEARS) do
        status("Put shears in the turtle inventory")
        sleep(2)
    end

    local selfHarvest = harvestWithDispenserShears(profile)

    if selfHarvest then
        profile.mode = "self"
        status("Mode learned: automatic shears harvest")
    else
        profile.mode = "player"
        status("Mode learned: player breaks the mature plant")
    end

    saveDatabase()
    return profile
end

local function growUntilMature(profile)
    setLocked(true)

    local unchanged = 0

    while true do
        local before = inspectFront()

        if not before then
            return false, "missing"
        end

        if not profileMatchesBlock(profile, before) then
            return false, "different"
        end

        if isMature(before, profile) then
            return true
        end

        local hasBoneMeal = dispenserHasBoneMeal()

        if hasBoneMeal == false then
            status("Add bone meal to the right dispenser")
            sleep(2)
        else
            status("Growing " .. before.name)
            pulseDispenser()

            local after = inspectFront()

            if not after then
                return false, "missing"
            end

            if sameBlock(before, after) then
                unchanged = unchanged + 1

                if unchanged >= STABLE_ATTEMPTS then
                    status(
                        "Plant is not at learned maximum, "
                        .. "but bone meal changes nothing"
                    )
                    sleep(2)
                    unchanged = 0
                end
            else
                unchanged = 0
            end
        end
    end
end

local function waitForPlayerHarvest(profile)
    setLocked(false)
    status("Mature: piston unlocked, hold left mouse button")

    while true do
        sleep(PLAYER_POLL_TIME)

        local current = inspectFront()

        if not current or not isMature(current, profile) then
            -- Lock before any replanting, so a held mouse button
            -- cannot immediately destroy the new immature plant.
            setLocked(true)
            sleep(CHEST_SETTLE_TIME)
            return current
        end
    end
end

local function candidateScore(itemName, profile)
    if profile.seedItem and itemName == profile.seedItem then
        return 100000
    end

    local lower = string.lower(itemName)
    local score = 0

    if string.find(lower, "seed", 1, true) then
        score = score + 900
    end

    if string.find(lower, "berry", 1, true) then
        score = score + 800
    end

    if string.find(lower, "apricorn", 1, true) then
        score = score + 750
    end

    local keywords = {
        "leek",
        "grain",
        "herb",
        "mint",
        "nut",
        "root",
        "vivichoke",
        "carrot",
        "potato",
        "beetroot",
        "wheat"
    }

    for _, keyword in ipairs(keywords) do
        if string.find(lower, keyword, 1, true) then
            score = score + 500
        end
    end

    for alias in pairs(profile.aliases or {}) do
        local namespaceEnd = string.find(alias, ":", 1, true)
        local path = alias

        if namespaceEnd then
            path = string.sub(alias, namespaceEnd + 1)
        end

        path = string.gsub(path, "_crop$", "")
        path = string.gsub(path, "_plant$", "")
        path = string.gsub(path, "_bush$", "")
        path = string.gsub(path, "_block$", "")

        if #path >= 4
            and string.find(lower, string.lower(path), 1, true) then
            score = score + 1200
        end
    end

    return score
end

local function chestHasCandidate(profile)
    if not peripheral.isPresent("back")
        or not peripheral.hasType("back", "inventory") then
        return true
    end

    local chest = peripheral.wrap("back")

    for _, item in pairs(chest.list()) do
        if profile.seedItem then
            if item.name == profile.seedItem then
                return true
            end
        elseif candidateScore(item.name, profile) > 0 then
            return true
        end
    end

    return false
end

local function pullChestContents()
    if not dumpToChestExceptShears() then
        return false, "Back chest is full"
    end

    turnAround()

    for _ = 1, MAX_INVENTORY_PULLS do
        local empty = findEmptySlot()
        if not empty then
            break
        end

        turtle.select(empty)

        if not turtle.suck() then
            break
        end
    end

    turnAround()
    return true
end

local function sortedPlantingSlots(profile)
    local candidates = {}

    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)

        if detail and detail.name ~= SHEARS then
            local score = candidateScore(detail.name, profile)

            if profile.seedItem then
                if detail.name == profile.seedItem then
                    candidates[#candidates + 1] = {
                        slot = slot,
                        name = detail.name,
                        score = score
                    }
                end
            elseif score > 0 then
                candidates[#candidates + 1] = {
                    slot = slot,
                    name = detail.name,
                    score = score
                }
            end
        end
    end

    table.sort(candidates, function(first, second)
        return first.score > second.score
    end)

    return candidates
end

local function tryPlantFromInventory(profile)
    local candidates = sortedPlantingSlots(profile)

    for _, candidate in ipairs(candidates) do
        turtle.select(candidate.slot)

        local placed = turtle.place()
        sleep(0.15)

        local block = inspectFront()

        if block then
            if profileMatchesBlock(profile, block) then
                if profile.seedItem ~= candidate.name then
                    profile.seedItem = candidate.name
                    saveDatabase()
                end

                return true
            end

            return false,
                "Unexpected block placed: "
                .. block.name
                .. ". Remove it manually."
        end

        -- Some items report successful use without placing a block.
        -- Continue trying the next likely seed/fruit.
        if placed then
            sleep(0.05)
        end
    end

    return false, "No suitable seed or fruit found"
end

local function replantFromChest(profile)
    setLocked(true)

    while true do
        if not chestHasCandidate(profile) then
            status("Waiting for a seed or plantable fruit in back chest")
            sleep(1)
        else
            local pulled, pullReason = pullChestContents()

            if not pulled then
                status(pullReason)
                sleep(1)
            else
                local planted, reason = tryPlantFromInventory(profile)
                dumpToChestExceptShears()

                if planted then
                    status("Replanted with " .. tostring(profile.seedItem))
                    return true
                end

                status(reason)
                sleep(1)
            end
        end
    end
end

local function runProfile(profile)
    while true do
        local block = inspectFront()

        if not block then
            replantFromChest(profile)
        elseif not profileMatchesBlock(profile, block) then
            return
        elseif not isMature(block, profile) then
            local grown, reason = growUntilMature(profile)

            if not grown then
                if reason == "different" then
                    return
                elseif reason == "missing" then
                    replantFromChest(profile)
                end
            end
        elseif profile.mode == "self" then
            setLocked(true)
            status("Mature: automatic dispenser-shears harvest")

            local harvested, reason = harvestWithDispenserShears(profile)

            if not harvested then
                status(
                    "Automatic harvest failed: "
                    .. tostring(reason or "state did not change")
                )
                sleep(2)
            else
                sleep(0.15)
            end
        else
            local after = waitForPlayerHarvest(profile)

            if not after then
                replantFromChest(profile)
            end
            -- If a lower part remains (for example, a two-block crop),
            -- the next loop grows that remaining plant again.
        end

        sleep(0.05)
    end
end

local function printProfiles()
    if #db.profiles == 0 then
        print("No learned profiles")
        return
    end

    for index, profile in ipairs(db.profiles) do
        local names = {}

        for name in pairs(profile.aliases or {}) do
            names[#names + 1] = name
        end

        table.sort(names)

        print(
            tostring(index)
            .. ". "
            .. table.concat(names, ", ")
        )
        print("   mode: " .. tostring(profile.mode))
        print("   seed: " .. tostring(profile.seedItem))
        print(
            "   mature: "
            .. tostring(profile.matureName)
            .. " "
            .. textutils.serialize(profile.matureState)
        )
    end
end

loadDatabase()

if args[1] == "reset" then
    if fs.exists(DB_FILE) then
        fs.delete(DB_FILE)
    end

    print("All learned plant profiles deleted")
    return
elseif args[1] == "list" then
    printProfiles()
    return
elseif args[1] == "forget" then
    local block = inspectFront()

    if not block then
        print("No plant in front")
        return
    end

    local _, index = findProfile(block)

    if not index then
        print("This plant has no learned profile")
        return
    end

    table.remove(db.profiles, index)
    saveDatabase()
    print("Plant profile deleted")
    return
end

setLocked(true)
redstone.setOutput(DISPENSER_SIDE, false)

print("Adaptive crop controller started")
print("Press Ctrl+T to stop")
print("Keep shears in the turtle and bone meal in the right dispenser")

while true do
    local block = inspectFront()

    if not block then
        setLocked(false)
        status("No plant in front; waiting for one to be placed")

        repeat
            sleep(0.20)
            block = inspectFront()
        until block

        setLocked(true)
    end

    local profile = findProfile(block)

    if not profile then
        profile = learnPlant(block)
    end

    runProfile(profile)
end
