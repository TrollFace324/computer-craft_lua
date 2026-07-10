-- water_farm.lua
-- Setup:
-- 1. Plant is in front of the turtle.
-- 2. Hopper is below the turtle.
-- 3. Redstone line for locking the hopper is on the turtle's right side.
-- 4. Use a Farming Turtle if this is a hoe-harvestable crop.

-- Change these if needed:
local HOPPER_LOCK_SIDE = "right"
local AGE_STATE = "age"
local HARVEST_AGE = 7

-- Set this if the turtle replants the wrong item.
-- Examples:
-- local REPLANT_ITEM = "minecraft:wheat_seeds"
-- local REPLANT_ITEM = "minecraft:kelp"
-- local REPLANT_ITEM = "farmersdelight:rice"
local REPLANT_ITEM = nil

-- Set to true if you want it to keep checking forever.
local RUN_FOREVER = true
local CHECK_INTERVAL = 30

-- If your tool is specifically on one side, set "left" or "right".
-- Usually nil is fine.
local TOOL_SIDE = nil

local function lockHopper()
  redstone.setOutput(HOPPER_LOCK_SIDE, true)
  print("Hopper locked.")
  sleep(0.1)
end

local function unlockHopper()
  redstone.setOutput(HOPPER_LOCK_SIDE, false)
  print("Hopper unlocked.")
  sleep(0.1)
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

local function isMature()
  local ok, data = turtle.inspect()

  if not ok then
    print("No block in front.")
    return false
  end

  local age = getAge(data)

  if age == nil then
    print("No age state found; skipping harvest.")
    print("Block: " .. tostring(data.name))
    print("State: " .. textutils.serialize(data.state))
    return false
  end

  if age < HARVEST_AGE then
    print("Block is not mature yet: age " .. age .. "/" .. HARVEST_AGE .. ".")
    return false
  end

  print("Block is mature: age " .. age .. "/" .. HARVEST_AGE .. ".")
  return true
end

local function digFront()
  if TOOL_SIDE == nil then
    return turtle.dig()
  else
    return turtle.dig(TOOL_SIDE)
  end
end

local function collectDrops()
  -- turtle.dig() often collects drops automatically,
  -- but this helps with items floating in front of the turtle.
  for i = 1, 8 do
    turtle.suck()
    sleep(0.2)
  end
end

local function findReplantSlot()
  if REPLANT_ITEM ~= nil then
    for slot = 1, 16 do
      local item = turtle.getItemDetail(slot)
      if item and item.name == REPLANT_ITEM then
        return slot
      end
    end

    return nil
  end

  -- Fallback: use the first non-empty slot.
  -- This is fine for plants that drop themselves.
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end

  return nil
end

local function dumpLeftoversDown()
  print("Dumping leftover items down.")

  for slot = 1, 16 do
    turtle.select(slot)

    local count = turtle.getItemCount(slot)
    if count > 0 then
      local ok, err = turtle.dropDown(count)

      if not ok then
        print("Could not drop items from slot " .. slot .. ": " .. tostring(err))
      end
    end
  end
end

local function runCycle()
  if not isMature() then
    return
  end

  lockHopper()

  print("Harvesting mature block.")

  local dug, digErr = digFront()
  if not dug then
    print("Could not dig block: " .. tostring(digErr))
    unlockHopper()
    return
  end

  sleep(0.5)
  collectDrops()

  local replantSlot = findReplantSlot()

  if not replantSlot then
    print("No replant item found; keeping drops inside turtle.")
    unlockHopper()
    return
  end

  turtle.select(replantSlot)

  print("Replanting item from slot " .. replantSlot .. ".")

  local placed, placeErr = turtle.place()

  if not placed then
    print("Could not replant: " .. tostring(placeErr))
    print("Drops were kept inside the turtle.")
    unlockHopper()
    return
  end

  print("Replanted successfully.")

  -- Now it is safe to unlock the hopper.
  unlockHopper()

  -- After replanting, dump all remaining drops into the hopper below.
  dumpLeftoversDown()

  print("Cycle complete.")
end

unlockHopper()

if RUN_FOREVER then
  while true do
    local ok, err = pcall(runCycle)

    if not ok then
      print("Program error: " .. tostring(err))
      unlockHopper()
    end

    print("Sleeping for " .. CHECK_INTERVAL .. " seconds.")
    sleep(CHECK_INTERVAL)
  end
else
  runCycle()
end
