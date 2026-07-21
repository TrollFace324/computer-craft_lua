local POWER_SIDE = "back"
local TARGET_AGE = 3
local CHECK_DELAY = 0.05
local DROP_WAIT = 0.05
local QUIET_PICKUP_PASSES = 5
local MAX_PICKUP_PASSES = 80
local PROFILE_FILE = "age3_replant.db"

local profile = {
    blockName = nil,
    plantingItem = nil
}

local lastStatus = nil

local function status(message)
    if message ~= lastStatus then
        print(message)
        lastStatus = message
    end
end

local function loadProfile()
    if not fs.exists(PROFILE_FILE) then
        return
    end

    local handle = fs.open(PROFILE_FILE, "r")

    if not handle then
        return
    end

    local data = textutils.unserialize(handle.readAll())
    handle.close()

    if type(data) == "table" then
        profile.blockName = data.blockName
        profile.plantingItem = data.plantingItem
    end
end

local function saveProfile()
    local handle = fs.open(PROFILE_FILE, "w")

    if not handle then
        error("Could not write " .. PROFILE_FILE)
    end

    handle.write(textutils.serialize(profile))
    handle.close()
end

local function inspectFront()
    local exists, block = turtle.inspect()

    if not exists then
        return nil
    end

    return block
end

local function isPowered()
    return redstone.getInput(POWER_SIDE)
end

local function dropAllInventoryUp()
    local allDropped = true

    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then
            turtle.select(slot)

            if not turtle.dropUp() then
                allDropped = false
            end
        end
    end

    turtle.select(1)
    return allDropped
end

local function waitWhilePoweredOff()
    while not isPowered() do
        if dropAllInventoryUp() then
            status("Idle: inventory unloaded into the chest above")
        else
            status(
                "Idle: chest above is full or missing; "
                .. "unloading will be retried"
            )
        end

        sleep(CHECK_DELAY)
    end

    status("Back redstone restored")
end

local function requirePower()
    if isPowered() then
        return true
    end

    waitWhilePoweredOff()
    return false
end

local function findItemSlot(itemName)
    if not itemName then
        return nil
    end

    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)

        if item and item.name == itemName then
            return slot
        end
    end

    return nil
end

local function collectFrontDrops()
    local quietPasses = 0
    local totalPasses = 0

    while quietPasses < QUIET_PICKUP_PASSES
        and totalPasses < MAX_PICKUP_PASSES do

        if not isPowered() then
            turtle.select(1)
            return false
        end

        totalPasses = totalPasses + 1
        turtle.select(1)

        if turtle.suck() then
            quietPasses = 0
        else
            quietPasses = quietPasses + 1
            sleep(DROP_WAIT)
        end
    end

    turtle.select(1)
    return true
end

local function blockPath(blockName)
    local colon = string.find(blockName, ":", 1, true)

    if colon then
        return string.sub(blockName, colon + 1)
    end

    return blockName
end

local function candidateScore(itemName, expectedBlock)
    if profile.plantingItem and itemName == profile.plantingItem then
        return 100000
    end

    local item = string.lower(itemName)
    local path = string.lower(blockPath(expectedBlock))
    local score = 0

    path = string.gsub(path, "_crop$", "")
    path = string.gsub(path, "_plant$", "")
    path = string.gsub(path, "_bush$", "")
    path = string.gsub(path, "_block$", "")

    if #path >= 4 and string.find(item, path, 1, true) then
        score = score + 10000
    end

    local words = {
        "seed",
        "berry",
        "sapling",
        "grain",
        "herb",
        "root",
        "nut",
        "leek"
    }

    for _, word in ipairs(words) do
        if string.find(item, word, 1, true) then
            score = score + 1000
        end
    end

    return score
end

local function getCandidateSlots(expectedBlock)
    local candidates = {}

    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)

        if item then
            local score = candidateScore(item.name, expectedBlock)

            if score > 0 then
                candidates[#candidates + 1] = {
                    slot = slot,
                    name = item.name,
                    score = score
                }
            end
        end
    end

    table.sort(candidates, function(first, second)
        if first.score == second.score then
            return first.slot < second.slot
        end

        return first.score > second.score
    end)

    return candidates
end

local function tryPlaceSlot(slot, itemName, expectedBlock)
    if not isPowered() then
        return false, "power_off"
    end

    turtle.select(slot)

    local placed = turtle.place()

    if not placed then
        return false
    end

    sleep(CHECK_DELAY)

    local block = inspectFront()

    if block and block.name == expectedBlock then
        profile.blockName = expectedBlock
        profile.plantingItem = itemName
        saveProfile()
        turtle.select(1)
        return true
    end

    if block then
        turtle.dig()
        sleep(DROP_WAIT)
        collectFrontDrops()
    end

    turtle.select(1)
    return false
end

local function replant(expectedBlock)
    while true do
        if not isPowered() then
            return false, "power_off"
        end

        local front = inspectFront()

        if front and front.name == expectedBlock then
            return true
        end

        if front then
            status("Another block is in front: " .. front.name)
            sleep(CHECK_DELAY)
        else
            local exactSlot = findItemSlot(profile.plantingItem)

            if exactSlot then
                local placed, reason = tryPlaceSlot(
                    exactSlot,
                    profile.plantingItem,
                    expectedBlock
                )

                if placed then
                    return true
                end

                if reason == "power_off" then
                    return false, reason
                end
            else
                local candidates = getCandidateSlots(expectedBlock)

                for _, candidate in ipairs(candidates) do
                    local placed, reason = tryPlaceSlot(
                        candidate.slot,
                        candidate.name,
                        expectedBlock
                    )

                    if placed then
                        return true
                    end

                    if reason == "power_off" then
                        return false, reason
                    end
                end
            end

            collectFrontDrops()
            status("Waiting for the planting item")
            sleep(CHECK_DELAY)
        end
    end
end

local function harvestAndReplant(block)
    if not isPowered() then
        return false, "power_off"
    end

    local expectedBlock = block.name

    if profile.blockName ~= expectedBlock then
        profile.blockName = expectedBlock
        profile.plantingItem = nil
        saveProfile()
    end

    turtle.select(1)

    local dug, reason = turtle.dig()

    if not dug then
        status("Could not break crop: " .. tostring(reason))
        return
    end

    sleep(DROP_WAIT)

    if not collectFrontDrops() then
        return false, "power_off"
    end

    if not isPowered() then
        return false, "power_off"
    end

    status("Replanting " .. expectedBlock)

    local replanted, replantReason = replant(expectedBlock)

    if not replanted then
        return false, replantReason
    end

    status("Crop replanted")
    return true
end

local function main()
    loadProfile()

    print("Age-3 crop replanter")
    print("Back redstone ON: working")
    print("Back redstone OFF: unload all inventory upward and idle")
    print("Output inventory: chest directly above")
    print("Target age: " .. tostring(TARGET_AGE))
    print("Press Ctrl+T to stop")

    while true do
        if not isPowered() then
            waitWhilePoweredOff()
        else
            local block = inspectFront()

            if not block then
                status("Working: no crop in front")
                sleep(CHECK_DELAY)
            else
                local age = block.state and block.state.age

                if age == TARGET_AGE then
                    status(
                        "Target age detected: "
                        .. block.name
                        .. ", age="
                        .. tostring(age)
                    )

                    local completed, reason =
                        harvestAndReplant(block)

                    if not completed and reason == "power_off" then
                        waitWhilePoweredOff()
                    end
                else
                    status(
                        "Working: waiting for age "
                        .. tostring(TARGET_AGE)
                        .. ", current="
                        .. tostring(age)
                    )

                    sleep(CHECK_DELAY)
                end
            end
        end
    end
end

local function onError(message)
    printError(tostring(message))
    printError(debug.traceback())
end

xpcall(main, onError)
