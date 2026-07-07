-- autosort.lua
-- Compact auto sorter for one Advanced Monitor
-- Only one button: SAVE

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local INPUT_CHEST = "carved_wood:barrel_0"
local TEMPLATE_FILE = "autosort_template.tbl"
local SORT_EVERY = 5
local MATCH_NBT = false

------------------------------------------------------------
-- SYSTEM
------------------------------------------------------------

local serialize = textutils.serialise or textutils.serialize
local unserialize = textutils.unserialise or textutils.unserialize

local template = {
  version = 5,
  match_nbt = MATCH_NBT,
  saved_at = "never",
  chests = {},
}

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

local function shortText(text, len)
  text = tostring(text or "")
  len = len or 20

  if #text <= len then
    return text
  end

  return string.sub(text, 1, len - 3) .. "..."
end

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

------------------------------------------------------------
-- FILES
------------------------------------------------------------

local function saveTemplateFile()
  local f = fs.open(TEMPLATE_FILE, "w")

  if not f then
    lastStatus = "Cannot save file"
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
    lastStatus = "Template broken"
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
    lastStatus = "Input not found"
    return
  end

  local storageChests = getStorageChests()
  local newChests = {}
  local samples = 0

  for _, chestName in ipairs(storageChests) do
    local items = scanChest(chestName)
    local hasItems = false

    for _ in pairs(items) do
      hasItems = true
      samples = samples + 1
    end

    if hasItems then
      newChests[chestName] = {
        saved_at = getTimeString(),
        items = items,
      }
    end
  end

  template = {
    version = 5,
    match_nbt = MATCH_NBT,
    saved_at = getTimeString(),
    chests = newChests,
  }

  if saveTemplateFile() then
    lastStatus = "Saved: " .. samples .. " samples"
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
    lastStatus = "Input not found"
    return
  end

  if countSamples() == 0 then
    lastStatus = "Press SAVE first"
    return
  end

  local input = peripheral.wrap(INPUT_CHEST)
  local routes = buildRoutes()

  local movedTotal = 0
  local unknownTotal = 0
  local fullTotal = 0

  for slot, item in pairs(input.list()) do
    local key = itemKey(item)
    local targets = routes[key]

    if targets and #targets > 0 then
      local moved, remaining = pushToTargets(input, slot, item, targets)

      movedTotal = movedTotal + moved

      if remaining > 0 then
        fullTotal = fullTotal + remaining
      end
    else
      unknownTotal = unknownTotal + item.count
    end
  end

  lastMoved = movedTotal
  lastUnknown = unknownTotal
  lastFull = fullTotal

  lastStatus = "M:" .. movedTotal .. " U:" .. unknownTotal .. " F:" .. fullTotal
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

local button = {
  x = 1,
  y = 2,
  w = 10,
  h = 3,
  label = "SAVE",
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

local function drawButton()
  local sw, sh = screen.getSize()

  button.x = 1
  button.y = 2
  button.w = sw
  button.h = 3

  for yy = 0, button.h - 1 do
    writeAt(button.x, button.y + yy, string.rep(" ", button.w), colors.white, colors.blue)
  end

  local textX = button.x + math.floor((button.w - #button.label) / 2)
  local textY = button.y + 1

  if textX < 1 then
    textX = 1
  end

  writeAt(textX, textY, button.label, colors.white, colors.blue)
end

local function draw()
  clear()

  local sw, sh = screen.getSize()

  writeAt(1, 1, shortText("SORTER", sw), colors.yellow, colors.black)

  drawButton()

  writeAt(1, 6, shortText("IN:" .. INPUT_CHEST, sw), colors.white, colors.black)
  writeAt(1, 7, shortText("FND:" .. tostring(exists(INPUT_CHEST)) .. " ST:" .. #getStorageChests(), sw), colors.white, colors.black)
  writeAt(1, 8, shortText("T:" .. countTemplateChests() .. " S:" .. countSamples() .. " U:" .. countUniqueItems(), sw), colors.lightGray, colors.black)
  writeAt(1, 9, shortText("MV:" .. lastMoved .. " UN:" .. lastUnknown .. " FL:" .. lastFull, sw), colors.lightGray, colors.black)
  writeAt(1, 10, shortText(lastStatus, sw), colors.white, colors.black)

  if sh >= 11 then
    writeAt(1, 11, shortText("Key S also saves", sw), colors.gray, colors.black)
  end
end

local function inButton(x, y)
  return x >= button.x
    and x < button.x + button.w
    and y >= button.y
    and y < button.y + button.h
end

local function handleClick(x, y)
  if inButton(x, y) then
    saveTemplate()
    draw()
  end
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
    sortOnce()
    draw()
    timer = os.startTimer(SORT_EVERY)

  elseif event == "monitor_touch" then
    local x = b
    local y = c
    handleClick(x, y)

  elseif event == "mouse_click" and not monitor then
    local x = b
    local y = c
    handleClick(x, y)

  elseif event == "key" then
    if a == keys.s then
      saveTemplate()
      draw()
    end

  elseif event == "monitor_resize" or event == "term_resize" then
    draw()
  end
end
