-- cobblemon_mint_farm.lua
-- Universal Cobblemon mint farm for one block below the turtle.
--
-- Setup:
-- [ Turtle ]
-- [ Mint crop ]
-- [ Farmland / valid soil ]
--
-- Output chest or hopper should be in front of the turtle.

local AGE_STATE = "age"
local DEFAULT_HARVEST_AGE = 7

local RUN_FOREVER = true
local CHECK_INTERVAL = 30

-- If digDown() does not work, try "left" or "right".
local TOOL_SIDE = nil

-- Crop block -> seed item
local REPLANT_BY_CROP = {
  ["cobblemon:red_mint"] = "cobblemon:red_mint_seeds",
  ["cobblemon:blue_mint"] = "cobblemon:blue_mint_seeds",
  ["cobblemon:cyan_mint"] = "cobblemon:cyan_mint_seeds",
  ["cobblemon:pink_mint"] = "cobblemon:pink_mint_seeds",
  ["cobblemon:green_mint"] = "cobblemon:green_mint_seeds",
  ["cobblemon:white_mint"] = "cobblemon:white_mint_seeds",
}

local CROP_MAX_AGES = {
  ["cobblemon:red_mint"] = 7,
  ["cobblemon:blue_mint"] = 7,
  ["cobblemon:cyan_mint"] = 7,
  ["cobblemon:pink_mint"] = 7,
  ["cobblemon:green_mint"] = 7,
  ["cobblemon:white_mint"] = 7,
}

local function getMaxAge(blockName)
  return CROP_MAX_AGES[blockName] or DEFAULT_HARVEST_AGE
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

local function isKnownReplantItem(itemName)
  for _, seedName in pairs(REPLANT_BY_CROP) do
    if itemName == seedName then
      return true
    end
  end

  return false
end

local function inspectCropBelow()
  local ok, data = turtle.inspectDown()

  if not ok then
    print("No block below.")
    return nil
  end

  if not REPLANT_BY_CROP[data.name] then
    print("Block below is not a known Cobblemon mint crop.")
    print("Found: " .. tostring(data.name))
    return nil
  end

  local age = getAge(data)

  if age == nil then
    print("No age state found.")
    print("Block: " .. tostring(data.name))
    print("State: " .. textutils.serialize(data.state))
    return nil
  end

  local maxAge = getMaxAge(data.name)

  if age < maxAge then
    print("Crop is not mature yet: " .. data.name .. " age " .. age .. "/" .. maxAge .. ".")
    return nil
  end

  print("Crop is mature: " .. data.name .. " age " .. age .. "/" .. maxAge .. ".")
  return data.name
end

local function digDown()
  if TOOL_SIDE == nil then
    return turtle.digDown()
  else
    return turtle.digDown(TOOL_SIDE)
  end
end

local function suckDrops()
  for i = 1, 8 do
    turtle.suckDown()
    turtle.suck()
    sleep(0.15)
  end
end

local function findSeedSlotForCrop(cropName)
  local neededSeed = REPLANT_BY_CROP[cropName]

  if not neededSeed then
    return nil
  end

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and item.name == neededSeed then
      return slot
    end
  end

  return nil
end

local function dumpNonSeedsForward()
  print("Dumping non-seed items forward.")

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and not isKnownReplantItem(item.name) then
      turtle.select(slot)
      turtle.drop()
    end
  end
end

local function runCycle()
  local cropName = inspectCropBelow()

  if not cropName then
    return
  end

  print("Harvesting: " .. cropName)

  local dug, digErr = digDown()

  if not dug then
    print("Could not harvest crop: " .. tostring(digErr))
    return
  end

  sleep(0.4)
  suckDrops()

  local seedSlot = findSeedSlotForCrop(cropName)

  if not seedSlot then
    print("No matching seed found for: " .. cropName)
    print("Expected seed: " .. tostring(REPLANT_BY_CROP[cropName]))
    return
  end

  turtle.select(seedSlot)

  local item = turtle.getItemDetail(seedSlot)
  print("Replanting with: " .. item.name)

  local planted, plantErr = turtle.placeDown()

  if not planted then
    print("Could not replant: " .. tostring(plantErr))
    return
  end

  print("Replanted successfully.")

  dumpNonSeedsForward()

  print("Cycle complete.")
end

if RUN_FOREVER then
  while true do
    local ok, err = pcall(runCycle)

    if not ok then
      print("Program error: " .. tostring(err))
    end

    print("Sleeping for " .. CHECK_INTERVAL .. " seconds.")
    sleep(CHECK_INTERVAL)
  end
else
  runCycle()
end
