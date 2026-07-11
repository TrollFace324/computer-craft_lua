-- fast_cobblemon_mint_safe.lua
-- Fast Cobblemon mint farm.
-- NEVER pulls items from the chest.
-- No turtle.suck(), no turtle.suckDown(), no turtle.suckUp().
--
-- Setup:
-- Output chest/hopper is in front of the turtle.
-- Mint crop is directly below the turtle.

local AGE_STATE = "age"
local HARVEST_AGE = 7

local REPLANT_RESERVE = 8
local PRINT_EVENTS = false

-- If digDown() does not work, try "left" or "right".
local TOOL_SIDE = nil

local MINTS = {
  ["cobblemon:red_mint"] = {
    "cobblemon:red_mint_seed",
    "cobblemon:red_mint",
  },

  ["cobblemon:blue_mint"] = {
    "cobblemon:blue_mint_seed",
    "cobblemon:blue_mint",
  },

  ["cobblemon:cyan_mint"] = {
    "cobblemon:cyan_mint_seed",
    "cobblemon:cyan_mint",
  },

  ["cobblemon:pink_mint"] = {
    "cobblemon:pink_mint_seed",
    "cobblemon:pink_mint",
  },

  ["cobblemon:green_mint"] = {
    "cobblemon:green_mint_seed",
    "cobblemon:green_mint",
  },

  ["cobblemon:white_mint"] = {
    "cobblemon:white_mint_seed",
    "cobblemon:white_mint",
  },
}

local function log(text)
  if PRINT_EVENTS then
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

local function digDownFast()
  if TOOL_SIDE == nil then
    return turtle.digDown()
  else
    return turtle.digDown(TOOL_SIDE)
  end
end

local function isReplantItem(itemName)
  for _, items in pairs(MINTS) do
    for _, replantName in ipairs(items) do
      if itemName == replantName then
        return true
      end
    end
  end

  return false
end

local function findReplantSlot(cropName)
  local possibleItems = MINTS[cropName]

  if not possibleItems then
    return nil
  end

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      for _, replantName in ipairs(possibleItems) do
        if item.name == replantName then
          return slot
        end
      end
    end
  end

  return nil
end

local function dumpExtrasForward()
  -- Drops everything forward into the output chest,
  -- but keeps a small reserve of plantable items.
  local kept = {}

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      turtle.select(slot)

      if isReplantItem(item.name) then
        local alreadyKept = kept[item.name] or 0
        local canKeep = math.max(0, REPLANT_RESERVE - alreadyKept)

        if item.count > canKeep then
          local toDrop = item.count - canKeep
          turtle.drop(toDrop)
          kept[item.name] = REPLANT_RESERVE
        else
          kept[item.name] = alreadyKept + item.count
        end
      else
        turtle.drop(item.count)
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
  local replantOptions = MINTS[cropName]

  if not replantOptions then
    return
  end

  local age = getAge(data)

  if age ~= HARVEST_AGE then
    return
  end

  log("Harvesting: " .. cropName)

  local dug, digErr = digDownFast()

  if not dug then
    print("Could not harvest: " .. tostring(digErr))
    return
  end

  -- No suck commands here.
  -- The turtle only uses items received directly from digDown().

  local replantSlot = findReplantSlot(cropName)

  if not replantSlot then
    print("No replant item found for: " .. cropName)
    print("Expected one of:")

    for _, name in ipairs(replantOptions) do
      print("- " .. name)
    end

    return
  end

  turtle.select(replantSlot)

  local planted, plantErr = turtle.placeDown()

  if not planted then
    print("Could not replant: " .. tostring(plantErr))
    return
  end

  dumpExtrasForward()

  log("Cycle complete.")
end

while true do
  local ok, err = pcall(harvestIfReady)

  if not ok then
    print("Program error: " .. tostring(err))
  end

  -- Very fast loop, but still yields to ComputerCraft.
  sleep(0)
end
