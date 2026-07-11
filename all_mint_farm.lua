-- mint_farm_quiet.lua
-- Quiet Cobblemon mint farm.
-- Never pulls items from the front chest.
-- Uses only turtle.suckDown() for collecting drops.

local AGE_STATE = "age"
local HARVEST_AGE = 7
local CHECK_DELAY = 0

local REPLANT_RESERVE = 1
local PRINT_SUCCESS = false

-- If digDown() does not work, try "left" or "right".
local TOOL_SIDE = nil

local MINT_SEEDS = {
  ["cobblemon:red_mint"] = "cobblemon:red_mint_seed",
  ["cobblemon:blue_mint"] = "cobblemon:blue_mint_seed",
  ["cobblemon:cyan_mint"] = "cobblemon:cyan_mint_seed",
  ["cobblemon:pink_mint"] = "cobblemon:pink_mint_seed",
  ["cobblemon:green_mint"] = "cobblemon:green_mint_seed",
  ["cobblemon:white_mint"] = "cobblemon:white_mint_seed",
}

-- Learned item that actually worked for replanting.
local learnedReplantItem = {}

local reported = {}

local function reportOnce(key, text)
  if not reported[key] then
    print(text)
    reported[key] = true
  end
end

local function log(text)
  if PRINT_SUCCESS then
    print(text)
  end
end

local function getAge(data)
  if not data or not data.state then
    return nil
  end

  local value = data.state[AGE_STATE]

  if type(value) == "string" then
    value = tonumber(value)
  end

  if type(value) == "number" then
    return value
  end

  return nil
end

local function isMintCrop(name)
  return MINT_SEEDS[name] ~= nil
end

local function isKnownMintSeed(name)
  for _, seed in pairs(MINT_SEEDS) do
    if name == seed then
      return true
    end
  end

  return false
end

local function isMintRelatedItem(name)
  return type(name) == "string"
    and string.find(name, "cobblemon:", 1, true) == 1
    and string.find(name, "mint", 1, true) ~= nil
end

local function digDownFast()
  if TOOL_SIDE == nil then
    return turtle.digDown()
  else
    return turtle.digDown(TOOL_SIDE)
  end
end

local function collectDropsFromBelow()
  -- Safe: does NOT pull from the front chest.
  for i = 1, 6 do
    turtle.suckDown()
    sleep(0.03)
  end
end

local function findSlotByItem(itemName)
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name == itemName then
      return slot
    end
  end

  return nil
end

local function printInventoryOnce()
  reportOnce("inventory_dump", "Current turtle inventory:")

  if reported["inventory_dump_lines"] then
    return
  end

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      print(slot .. ": " .. item.name .. " x" .. item.count)
    end
  end

  reported["inventory_dump_lines"] = true
end

local function tryPlaceFromSlot(slot)
  turtle.select(slot)
  local ok, err = turtle.placeDown()
  return ok, err
end

local function replantCrop(cropName)
  -- 1. Try learned item first.
  local learned = learnedReplantItem[cropName]

  if learned then
    local slot = findSlotByItem(learned)

    if slot then
      local ok, err = tryPlaceFromSlot(slot)

      if ok then
        return true, learned
      end
    end
  end

  -- 2. Try expected seed.
  local expectedSeed = MINT_SEEDS[cropName]

  if expectedSeed then
    local slot = findSlotByItem(expectedSeed)

    if slot then
      local ok, err = tryPlaceFromSlot(slot)

      if ok then
        learnedReplantItem[cropName] = expectedSeed
        return true, expectedSeed
      end
    end
  end

  -- 3. Try the crop item itself, in case this mod/version replants using the crop item.
  local cropItemSlot = findSlotByItem(cropName)

  if cropItemSlot then
    local ok, err = tryPlaceFromSlot(cropItemSlot)

    if ok then
      learnedReplantItem[cropName] = cropName
      return true, cropName
    end
  end

  -- 4. Last fallback: try any Cobblemon mint-related item.
  -- This avoids needing exact IDs.
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and isMintRelatedItem(item.name) then
      local ok, err = tryPlaceFromSlot(slot)

      if ok then
        learnedReplantItem[cropName] = item.name
        return true, item.name
      end
    end
  end

  return false, nil
end

local function shouldKeepForReplant(itemName)
  if isKnownMintSeed(itemName) then
    return true
  end

  for _, learned in pairs(learnedReplantItem) do
    if itemName == learned then
      return true
    end
  end

  return false
end

local function dumpExtrasForward()
  local kept = {}

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      turtle.select(slot)

      if shouldKeepForReplant(item.name) then
        local alreadyKept = kept[item.name] or 0
        local canKeep = math.max(0, REPLANT_RESERVE - alreadyKept)

        if item.count > canKeep then
          local toDrop = item.count - canKeep

          if toDrop > 0 then
            local ok, err = turtle.drop(toDrop)

            if not ok then
              reportOnce("drop_failed", "Could not drop items into the front chest: " .. tostring(err))
            end
          end

          kept[item.name] = REPLANT_RESERVE
        else
          kept[item.name] = alreadyKept + item.count
        end
      else
        local ok, err = turtle.drop(item.count)

        if not ok then
          reportOnce("drop_failed", "Could not drop items into the front chest: " .. tostring(err))
        end
      end
    end
  end
end

local function harvestIfReady()
  local ok, data = turtle.inspectDown()

  if not ok then
    return
  end

  local cropName = data.name

  if not isMintCrop(cropName) then
    reportOnce("unknown_crop_" .. tostring(cropName), "Unknown crop below: " .. tostring(cropName))
    return
  end

  local age = getAge(data)

  if age == nil then
    reportOnce("no_age_" .. cropName, "No age state found for: " .. cropName)
    return
  end

  if age < HARVEST_AGE then
    return
  end

  local dug, digErr = digDownFast()

  if not dug then
    reportOnce("dig_failed_" .. cropName, "Could not harvest " .. cropName .. ": " .. tostring(digErr))
    return
  end

  sleep(0.1)
  collectDropsFromBelow()

  local planted, usedItem = replantCrop(cropName)

  if not planted then
    reportOnce(
      "replant_failed_" .. cropName,
      "Could not replant " .. cropName .. ". Expected seed: " .. tostring(MINT_SEEDS[cropName])
    )

    printInventoryOnce()
    return
  end

  log("Replanted with: " .. usedItem)

  dumpExtrasForward()
end

print("Mint farm started.")

while true do
  local ok, err = pcall(harvestIfReady)

  if not ok then
    reportOnce("program_error", "Program error: " .. tostring(err))
  end

  sleep(CHECK_DELAY)
end
