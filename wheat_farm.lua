-- auto_crop_farm.lua
-- Universal crop farm for one block below the turtle.
--
-- Setup:
-- [ Turtle ]
-- [ Crop   ]
-- [ Farmland ]
--
-- Output chest or hopper should be in front of the turtle.

local AGE_STATE = "age"
local DEFAULT_HARVEST_AGE = 7

local RUN_FOREVER = true
local CHECK_INTERVAL = 30

-- Items that can be used for replanting.
-- Add modded seeds here if needed.
local REPLANT_ITEMS = {
  "minecraft:wheat_seeds",
  "minecraft:carrot",
  "minecraft:potato",
  "minecraft:beetroot_seeds",
  "minecraft:nether_wart",
}

-- Some crops have max age 3 instead of 7.
local CROP_MAX_AGES = {
  ["minecraft:beetroots"] = 3,
  ["minecraft:nether_wart"] = 3,
}

-- If digDown() does not work, try "left" or "right".
local TOOL_SIDE = nil

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

local function isReplantItem(itemName)
  for _, name in ipairs(REPLANT_ITEMS) do
    if itemName == name then
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

  local age = getAge(data)

  if age == nil then
    print("Block below has no age state.")
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

local function findReplantSlot()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and isReplantItem(item.name) then
      return slot
    end
  end

  return nil
end

local function dumpNonReplantItemsForward()
  print("Dumping non-replant items forward.")

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and not isReplantItem(item.name) then
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

  local replantSlot = findReplantSlot()

  if not replantSlot then
    print("No replant item found. Cannot replant.")
    return
  end

  turtle.select(replantSlot)

  local item = turtle.getItemDetail(replantSlot)
  print("Trying to replant with: " .. item.name)

  local planted, plantErr = turtle.placeDown()

  if not planted then
    print("Could not replant: " .. tostring(plantErr))
    return
  end

  print("Replanted successfully.")

  dumpNonReplantItemsForward()

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
