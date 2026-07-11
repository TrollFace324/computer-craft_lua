-- wheat_farm.lua
-- Turtle setup:
-- [ Turtle ]
-- [ Wheat  ]
-- [ Farmland ]
--
-- Output chest or hopper should be in front of the turtle.
-- Put wheat seeds in the turtle inventory before starting.

local AGE_STATE = "age"
local HARVEST_AGE = 7
local SEED_ITEM = "minecraft:wheat_seeds"

local RUN_FOREVER = true
local CHECK_INTERVAL = 30

-- If digDown() does not work, try "left" or "right".
local TOOL_SIDE = nil

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

local function isMatureWheatBelow()
  local ok, data = turtle.inspectDown()

  if not ok then
    print("No block below.")
    return false
  end

  if data.name ~= "minecraft:wheat" then
    print("Block below is not wheat: " .. tostring(data.name))
    return false
  end

  local age = getAge(data)

  if age == nil then
    print("No age state found.")
    print("State: " .. textutils.serialize(data.state))
    return false
  end

  if age < HARVEST_AGE then
    print("Wheat is not mature yet: age " .. age .. "/" .. HARVEST_AGE .. ".")
    return false
  end

  print("Wheat is mature: age " .. age .. "/" .. HARVEST_AGE .. ".")
  return true
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

local function findSeedSlot()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name == SEED_ITEM then
      return slot
    end
  end

  return nil
end

local function dumpNonSeedsForward()
  print("Dumping wheat and extra items forward.")

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and item.name ~= SEED_ITEM then
      turtle.select(slot)
      turtle.drop()
    end
  end
end

local function runCycle()
  if not isMatureWheatBelow() then
    return
  end

  print("Harvesting wheat.")

  local dug, digErr = digDown()

  if not dug then
    print("Could not harvest wheat: " .. tostring(digErr))
    return
  end

  sleep(0.4)

  suckDrops()

  local seedSlot = findSeedSlot()

  if not seedSlot then
    print("No wheat seeds found. Cannot replant.")
    return
  end

  turtle.select(seedSlot)

  print("Replanting wheat seeds.")

  local planted, plantErr = turtle.placeDown()

  if not planted then
    print("Could not replant wheat: " .. tostring(plantErr))
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
