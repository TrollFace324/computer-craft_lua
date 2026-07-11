-- fast_mint_row.lua
-- Fast Cobblemon mint harvester.
--
-- Setup:
-- Turtle starts above the first crop.
-- Crops are below the turtle.
-- Next crop is forward.
--
-- Example:
-- [Turtle] -> moves forward over each crop
-- [Mint  ]
-- [Soil  ]

local ROW_LENGTH = 16          -- сколько растений в ряду
local HARVEST_AGE = 7
local AGE_STATE = "age"

local RUN_FOREVER = true
local RETURN_TO_START = true   -- возвращаться в начало ряда после прохода
local PRINT_EVENTS = false     -- false = быстрее

local TOOL_SIDE = nil          -- если digDown не работает, попробуй "left" или "right"

local REPLANT_BY_CROP = {
  ["cobblemon:red_mint"] = "cobblemon:red_mint_seed",
  ["cobblemon:blue_mint"] = "cobblemon:blue_mint_seed",
  ["cobblemon:cyan_mint"] = "cobblemon:cyan_mint_seed",
  ["cobblemon:pink_mint"] = "cobblemon:pink_mint_seed",
  ["cobblemon:green_mint"] = "cobblemon:green_mint_seed",
  ["cobblemon:white_mint"] = "cobblemon:white_mint_seed",
}

local function log(text)
  if PRINT_EVENTS then
    print(text)
  end
end

local function getAge(data)
  if not data or not data.state then return nil end

  local value = data.state[AGE_STATE]
  if type(value) == "string" then value = tonumber(value) end
  if type(value) == "number" then return value end

  return nil
end

local function digDownFast()
  if TOOL_SIDE == nil then
    return turtle.digDown()
  else
    return turtle.digDown(TOOL_SIDE)
  end
end

local function findSeedSlot(seedName)
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name == seedName then
      return slot
    end
  end

  return nil
end

local function isKnownSeed(itemName)
  for _, seedName in pairs(REPLANT_BY_CROP) do
    if itemName == seedName then
      return true
    end
  end

  return false
end

local function quickSuck()
  -- Без длинных циклов. Обычно digDown сам забирает часть дропа.
  turtle.suckDown()
  turtle.suck()
end

local function dumpNonSeeds()
  -- Сбрасывает урожай вперёд, семена оставляет.
  -- Если сундук/воронка не перед черепашкой, поменяй turtle.drop() на dropDown/dropUp.
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item and not isKnownSeed(item.name) then
      turtle.select(slot)
      turtle.drop()
    end
  end
end

local function harvestIfReady()
  local ok, data = turtle.inspectDown()

  if not ok then
    return false
  end

  local seedName = REPLANT_BY_CROP[data.name]

  if not seedName then
    return false
  end

  local age = getAge(data)

  if age ~= HARVEST_AGE then
    return false
  end

  log("Harvesting " .. data.name)

  local dug = digDownFast()
  if not dug then
    return false
  end

  quickSuck()

  local seedSlot = findSeedSlot(seedName)

  if not seedSlot then
    print("No seed found for " .. data.name)
    print("Expected: " .. seedName)
    return false
  end

  turtle.select(seedSlot)

  local planted, err = turtle.placeDown()

  if not planted then
    print("Could not replant " .. data.name .. ": " .. tostring(err))
    return false
  end

  dumpNonSeeds()

  return true
end

local function moveForwardSafe()
  while not turtle.forward() do
    -- Если впереди мешает предмет/моб/блок, пробуем немного подождать.
    -- Это короткая пауза, чтобы программа не упала.
    sleep(0.05)
  end
end

local function moveBackSafe()
  while not turtle.back() do
    sleep(0.05)
  end
end

local function scanRow()
  for i = 1, ROW_LENGTH do
    harvestIfReady()

    if i < ROW_LENGTH then
      moveForwardSafe()
    end

    -- Минимальная уступка системе, чтобы ComputerCraft не ругался
    -- на too long without yielding.
    if i % 8 == 0 then
      sleep(0)
    end
  end

  if RETURN_TO_START then
    for i = 1, ROW_LENGTH - 1 do
      moveBackSafe()

      if i % 8 == 0 then
        sleep(0)
      end
    end
  end
end

while true do
  scanRow()

  if not RUN_FOREVER then
    break
  end

  -- Без долгой задержки: сразу новый проход.
  sleep(0)
end
