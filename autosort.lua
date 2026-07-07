-- autosort.lua
-- Auto sorter for CC:Tweaked / ComputerCraft
-- Fixed input barrel: carved_wood:barrel_0
-- All other connected inventories are used as storage chests automatically.

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local INPUT_CHEST = "carved_wood:barrel_0"

local SORT_EVERY = 5

local TEMPLATE_FILE = "autosort_template.tbl"

-- false = match only item name
-- true = match item name + NBT hash
local MATCH_NBT = false

------------------------------------------------------------
-- SYSTEM
------------------------------------------------------------

local serialize = textutils.serialise or textutils.serialize
local unserialize = textutils.unserialise or textutils.unserialize

local template = {
  version = 4,
  match_nbt = MATCH_NBT,
  saved_at = "never",
  chests = {},
}

local autoSort = true
local lastStatus = "Ready"
local lastMoved = 0
local lastUnknown = 0
local lastFull = 0

local monitor = peripheral.find("monitor")
local monitorName = nil

if monitor then
  monitorName = peripheral.getName(monitor)
  pcall(function()
    monitor.setTextScale(0.5)
  end)
end

local screen = monitor or term.current()

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function getTimeString()
  local ok, result = pcall(function()
    return os.date("%Y-%m-%d %H:%M:%S")
  end)

  if ok and result then
    return result
  end

  return tostring(os.time())
end

local function exists(name)
  return name and peripheral.wrap(name) ~= nil
end

local function isInventory(name)
  local p = peripheral.wrap(name)

  return type(p) == "table"
    and type(p.list) == "function"
    and type(p.pushItems) == "function"
    and type(p.size) == "function"
end

local function itemKey(item)
  if MATCH_NBT and item.nbt then
    return item.name .. "|" .. item.nbt
  end

  return item.name
end

local function addUnique(list, value)
  for _, v in ipairs(list) do
    if v == value then
      return
    end
  end

  table.insert(list, value)
end

local function shortName(name, maxLen)
  maxLen = maxLen or 40

  if not name then
    return "none"
  end

  if #name <= maxLen then
    return name
  end

  return string.sub(name, 1, maxLen - 3) .. "..."
end

------------------------------------------------------------
-- FILES
------------------------------------------------------------

local function saveTemplateFile()
  local f = fs.open(TEMPLATE_FILE, "w")

  if not f then
    lastStatus = "Cannot save template file"
    return false
  end

  f.write(serialize(template))
  f.close()

  return true
end

local function loadTemplateFile()
  if not fs.exists(TEMPLATE_FILE) then
    return
  end

  local f = fs.open(TEMPLATE_FILE, "r")

  if not f then
    return
  end

  local raw = f.readAll()
  f.close()

  local data = unserialize(raw)

  if type(data) == "table" and type(data.chests) == "table" then
    template = data
    MATCH_NBT = data.match_nbt or false
    lastStatus = "Template loaded"
  else
    lastStatus = "Template file broken"
  end
end

------------------------------------------------------------
-- INVENTORIES
------------------------------------------------------------

local function getAllInventories()
  local result = {}

  for _, name in ipairs(peripheral.getNames()) do
    if name ~= monitorName and isInventory(name) then
      table.insert(result, name)
    end
  end

  table.sort(result)
  return result
end

local function getStorageChests()
  local result = {}

  for _, name in ipairs(getAllInventories()) do
    if name ~= INPUT_CHEST then
      table.insert(result, name)
    end
  end

  return result
end

local function countStorageChests()
  return #getStorageChests()
end

local function countTemplateChests()
  local n = 0

  for _ in pairs(template.chests or {}) do
    n = n + 1
  end

  return n
end

local function countSamples()
  local n = 0

  for _, chestData in pairs(template.chests or {}) do
    if type(chestData.items) == "table" then
      for _ in pairs(chestData.items) do
        n = n + 1
      end
    end
  end

  return n
end

local function countUniqueItems()
  local seen = {}

  for _, chestData in pairs(template.chests or {}) do
    if type(chestData.items) == "table" then
      for key in pairs(chestData.items) do
        seen[key] = true
      end
    end
  end

  local n = 0

  for _ in pairs(seen) do
    n = n + 1
  end

  return n
end

------------------------------------------------------------
-- TEMPLATE
------------------------------------------------------------

local function scanChest(chestName)
  local chest = peripheral.wrap(chestName)
  local items = {}

  if not chest then
    return items
  end

  for _, item in pairs(chest.list()) do
    local key = itemKey(item)

    if not items[key] then
      items[key] = {
        name = item.name,
        nbt = item.nbt,
        count = 0,
      }
    end

    items[key].count = items[key].count + item.count
  end

  return items
end

local function saveTemplate()
  if not exists(INPUT_CHEST) then
    lastStatus = "Input barrel not found"
    return
  end

  local storageChests = getStorageChests()
  local newChests = {}
  local chestCount = 0
  local sampleCount = 0

  for _, chestName in ipairs(storageChests) do
    local items = scanChest(chestName)
    local hasItems = false

    for _ in pairs(items) do
      hasItems = true
      sampleCount = sampleCount + 1
    end

    if hasItems then
      newChests[chestName] = {
        saved_at = getTimeString(),
        items = items,
      }

      chestCount = chestCount + 1
    end
  end

  template = {
    version = 4,
    match_nbt = MATCH_NBT,
    saved_at = getTimeString(),
    chests = newChests,
  }

  if saveTemplateFile() then
    lastStatus = "Template saved: " .. sampleCount .. " samples"
  end
end

local function buildRoutes()
  local routes = {}
  local chestNames = {}

  for chestName in pairs(template.chests or {}) do
    table.insert(chestNames, chestName)
  end

  table.sort(chestNames)

  for _, chestName in ipairs(chestNames) do
    local chestData = template.chests[chestName]

    if chestName ~= INPUT_CHEST and exists(chestName) then
      if type(chestData.items) == "table" then
        for key in pairs(chestData.items) do
          routes[key] = routes[key] or {}
          addUnique(routes[key], chestName)
        end
      end
    end
  end

  return routes
end

------------------------------------------------------------
-- SORTING
------------------------------------------------------------

local function pushToTargets(input, slot, item, targets)
  local remaining = item.count
  local moved = 0

  for _, targetName in ipairs(targets) do
    if remaining <= 0 then
      break
    end

    if targetName ~= INPUT_CHEST and exists(targetName) then
      local ok, amount = pcall(function()
        return input.pushItems(targetName, slot, remaining)
      end)

      if ok and type(amount) == "number" and amount > 0 then
        moved = moved + amount
        remaining = remaining - amount
      end
    end
  end

  return moved, remaining
end

local function sortOnce()
  if not exists(INPUT_CHEST) then
    lastStatus = "Input barrel not found"
    return
  end

  if countSamples() == 0 then
    lastStatus = "No template. Press SAVE TEMPLATE"
    return
  end

  local input = peripheral.wrap(INPUT_CHEST)
  local routes = buildRoutes()

  local movedTotal = 0
  local unknownTotal = 0
  local fullTotal = 0

  local items = input.list()

  for slot, item in pairs(items) do
    local key = itemKey(item)
    local targets = routes[key]

    if targets and #targets > 0 then
      local moved, remaining = pushToTargets(input, slot, item, targets)

      movedTotal = movedTotal + moved

      if remaining > 0 then
        fullTotal = fullTotal + remaining
      end
    else
      -- Item is not in template.
      -- It stays in the input barrel.
      unknownTotal = unknownTotal + item.count
    end
  end

  lastMoved = movedTotal
  lastUnknown = unknownTotal
  lastFull = fullTotal

  lastStatus = "Sorted: +" .. movedTotal
    .. " | unknown: " .. unknownTotal
    .. " | full: " .. fullTotal
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

local buttons = {
  save = { x = 2,  y = 3, w = 22, h = 3, label = "SAVE TEMPLATE" },
  auto = { x = 26, y = 3, w = 18, h = 3, label = "AUTO: ON" },
  exit = { x = 2,  y = 7, w = 22, h = 3, label = "EXIT" },
}

local function setBg(color)
  if screen.setBackgroundColor then
    pcall(function()
      screen.setBackgroundColor(color)
    end)
  end
end

local function setFg(color)
  if screen.setTextColor then
    pcall(function()
      screen.setTextColor(color)
    end)
  end
end

local function writeAt(x, y, text, fg, bg)
  if fg then setFg(fg) end
  if bg then setBg(bg) end

  screen.setCursorPos(x, y)
  screen.write(text)
end

local function clear()
  setBg(colors.black)
  setFg(colors.white)
  screen.clear()
  screen.setCursorPos(1, 1)
end

local function drawButton(btn, label, bg)
  for yy = 0, btn.h - 1 do
    writeAt(btn.x, btn.y + yy, string.rep(" ", btn.w), colors.white, bg)
  end

  local textX = btn.x + math.floor((btn.w - #label) / 2)
  local textY = btn.y + math.floor(btn.h / 2)

  if textX < btn.x then
    textX = btn.x
  end

  writeAt(textX, textY, label, colors.white, bg)
end

local function draw()
  clear()

  buttons.auto.label = autoSort and "AUTO: ON" or "AUTO: OFF"

  writeAt(2, 1, "AUTO SORTER V4", colors.yellow, colors.black)

  drawButton(buttons.save, buttons.save.label, colors.blue)
  drawButton(buttons.auto, buttons.auto.label, autoSort and colors.lime or colors.gray)
  drawButton(buttons.exit, buttons.exit.label, colors.red)

  local y = 12

  writeAt(2, y,     "Input: " .. shortName(INPUT_CHEST, 40), colors.white, colors.black)
  writeAt(2, y + 1, "Input found: " .. tostring(exists(INPUT_CHEST)), colors.white, colors.black)
  writeAt(2, y + 2, "Storage chests: " .. tostring(countStorageChests()), colors.white, colors.black)

  writeAt(2, y + 4, "Template chests: " .. tostring(countTemplateChests()), colors.lightGray, colors.black)
  writeAt(2, y + 5, "Item samples: " .. tostring(countSamples()), colors.lightGray, colors.black)
  writeAt(2, y + 6, "Unique items: " .. tostring(countUniqueItems()), colors.lightGray, colors.black)

  writeAt(2, y + 8, "Status:", colors.yellow, colors.black)
  writeAt(2, y + 9, shortName(tostring(lastStatus), 44), colors.white, colors.black)

  writeAt(2, y + 11, "Moved: " .. lastMoved .. " Unknown: " .. lastUnknown, colors.lightGray, colors.black)
  writeAt(2, y + 12, "Full: " .. lastFull, colors.lightGray, colors.black)

  if not monitor then
    writeAt(2, y + 14, "Use mouse click or Ctrl+T", colors.gray, colors.black)
  end
end

local function inButton(btn, x, y)
  return x >= btn.x
    and x < btn.x + btn.w
    and y >= btn.y
    and y < btn.y + btn.h
end

local function handleClick(x, y)
  if inButton(buttons.save, x, y) then
    saveTemplate()

  elseif inButton(buttons.auto, x, y) then
    autoSort = not autoSort
    lastStatus = autoSort and "Auto sort enabled" or "Auto sort disabled"

  elseif inButton(buttons.exit, x, y) then
    clear()
    error("Exit", 0)
  end

  draw()
end

------------------------------------------------------------
-- START
------------------------------------------------------------

loadTemplateFile()
draw()

local timer = os.startTimer(SORT_EVERY)

while true do
  local event, a, b, c = os.pullEvent()

  if event == "timer" and a == timer then
    if autoSort then
      sortOnce()
      draw()
    end

    timer = os.startTimer(SORT_EVERY)

  elseif event == "monitor_touch" then
    local side = a
    local x = b
    local y = c

    if not monitorName or side == monitorName then
      handleClick(x, y)
    end

  elseif event == "mouse_click" and not monitor then
    local x = b
    local y = c
    handleClick(x, y)

  elseif event == "monitor_resize" or event == "term_resize" then
    draw()
  end
end
