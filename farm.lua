-- water_farm_top.lua
-- Setup:
-- 1. Turtle is ABOVE the plant.
-- 2. Plant is directly below the turtle.
-- 3. Water is below the plant.
-- 4. Crop max age is 3.
-- 5. Output chest/hopper is in front of the turtle.
-- 6. Hopper lock redstone is on the turtle's right side.

local HOPPER_LOCK_SIDE = "right"
local AGE_STATE = "age"
local HARVEST_AGE = 3

-- Set this if the turtle replants the wrong item.
-- Example:
-- local REPLANT_ITEM = "farmersdelight:rice"
local REPLANT_ITEM = nil

local RUN_FOREVER = true
local CHECK_INTERVAL = 30

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

local function isMatureDown()
  local ok, data = turtle.inspectDown()

  if not ok then
    print("No block below.")
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

local function collectDrops()
  -- Try to collect floating drops below the turtle.
  for i = 1, 8 do
    turtle.suckDown()
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

  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end

  return nil
end

local function dumpLeftoversForward()
  print("Dumping leftover items forward.")

  for slot = 1, 16 do
    turtle.select(slot)

    local count = turtle.getItemCount(slot)
    if count > 0 then
      local ok, err = turtle.drop(count)

      if not ok then
        print("Could not drop items from slot " .. slot .. ": " .. tostring(err))
      end
    end
  end
end

local function runCycle()
  if not isMatureDown() then
    return
  end

  lockHopper()

  print("Harvesting mature block below.")

  local dug, digErr = turtle.digDown()
  if not dug then
    print("Could not dig block below: " .. tostring(digErr))
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

  print("Replanting below using slot " .. replantSlot .. ".")

  local placed, placeErr = turtle.placeDown()

  if not placed then
    print("Could not replant below: " .. tostring(placeErr))
    print("Drops were kept inside the turtle.")
    unlockHopper()
    return
  end

  print("Replanted successfully.")

  unlockHopper()

  dumpLeftoversForward()

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
