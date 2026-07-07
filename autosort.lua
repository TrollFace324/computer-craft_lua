-- autosort.lua
-- Auto sorter for CC:Tweaked / ComputerCraft
-- Auto-detects all network inventories.
-- Each chest has its own saved template.

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

-- Leave nil to select input chest from the monitor UI.
-- Example: local FIXED_INPUT_CHEST = "minecraft:barrel_0"
local FIXED_INPUT_CHEST = nil

-- Optional unknown-items chest.
-- If nil, unknown items stay in the input chest.
local FIXED_UNSORTED_CHEST = nil

local SORT_EVERY = 5

local TEMPLATE_FILE = "autosort_templates.tbl"
local CONFIG_FILE = "autosort_config.tbl"

-- false = match only item name
-- true = match item name + NBT hash
local MATCH_NBT = false

------------------------------------------------------------
-- SYSTEM
------------------------------------------------------------

local serialize = textutils.serialise or textutils.serialize
local unserialize = textutils.unserialise or textutils.unserialize

local config = {
  inputChest = nil,
  unsortedChest = nil,
}

local template = {
  version = 3,
  match_nbt = MATCH_NBT,
  saved_at = "never",
  chests = {},
}

local autoSort = true
local lastStatus = "Ready"
local lastMoved = 0
local lastUnknown = 0
local lastFull = 0
local selectedIndex = 1

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
-- BASIC HELPERS
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
  maxLen = maxLen or 34

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

local function saveConfig()
  local f = fs.open(CONFIG_FILE, "w")
  if not f then
    lastStatus = "Cannot save config"
    return false
  end

  f.write(serialize(config))
  f.close()
  return true
end

local function loadConfig()
  if not fs.exists(CONFIG_FILE) then
    return
  end

  local f = fs.open(CONFIG_FILE, "r")
  if not f then
    return
  end

  local raw = f.readAll()
  f.close()

  local data = unserialize(raw)

  if type(data) == "table" then
    config = data
  end
end

local function saveTemplate()
  local f = fs.open(TEMPLATE_FILE, "w")
  if not f then
    lastStatus = "Cannot save templates"
    return false
  end

  f.write(serialize(template))
  f.close()
  return true
end

local function loadTemplate()
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
    lastStatus = "Templates loaded"
  else
    lastStatus = "Template file broken"
  end
end

------------------------------------------------------------
-- INVENTORY DISCOVERY
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

local function getSelectedChest()
  local inventories = getAllInventories()

  if #inventories == 0 then
    selectedIndex = 1
    return nil
  end

  if selectedIndex < 1 then
    selectedIndex = 1
  end

  if selectedIndex > #inventories then
    selectedIndex = #inventories
  end

  return inventories[selectedIndex]
end

local function getStorageChests()
  local result = {}
  local inventories = getAllInventories()

  for _, name in ipairs(inventories) do
    if name ~= config.inputChest and name ~= config.unsortedChest then
      table.insert(result, name)
    end
  end

  return result
end

local function countChestTemplates()
  local n = 0

  for _ in pairs(template.chests or {}) do
    n = n + 1
  end

  return n
end

local function countItemTemplates()
  local n = 0

  for _, chestTemplate in pairs(template.chests or {}) do
    if type(chestTemplate.items) == "table" then
      for _ in pairs(chestTemplate.items) do
        n = n + 1
      end
    end
  end

  return n
end

local function countUniqueRoutes()
  local seen = {}

  for _, chestTemplate in pairs(template.chests or {}) do
    if type(chestTemplate.items) == "table" then
      for key in pairs(chestTemplate.items) do
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
-- TEMPLATE LOGIC
------------------------------------------------------------

local function scanChestItems(chestName)
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

local function saveSamples(clearFirst)
  if not config.inputChest then
    lastStatus = "Set input chest first"
    return
  end

  if clearFirst then
    template.chests = {}
  end

  local storageChests = getStorageChests()
  local added = 0
  local chestCount = 0

  for _, chestName in ipairs(storageChests) do
    local scanned = scanChestItems(chestName)
    local hasItems = false

    for _ in pairs(scanned) do
      hasItems = true
      break
    end

    if hasItems or template.chests[chestName] then
      template.chests[chestName] = template.chests[chestName] or {
        items = {},
        saved_at = "never",
      }

      template.chests[chestName].items = template.chests[chestName].items or {}

      for key, data in pairs(scanned) do
        if not template.chests[chestName].items[key] then
          added = added + 1
        end

        template.chests[chestName].items[key] = data
      end

      template.chests[chestName].saved_at = getTimeString()
      chestCount = chestCount + 1
    end
  end

  template.version = 3
  template.match_nbt = MATCH_NBT
  template.saved_at = getTimeString()

  if saveTemplate() then
    if clearFirst then
      lastStatus = "Rebuilt: " .. countItemTemplates() .. " samples"
    else
      lastStatus = "Saved samples: +" .. added
    end
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
    local chestTemplate = template.chests[chestName]

    if chestName ~= config.inputChest and exists(chestName) then
      if type(chestTemplate.items) == "table" then
        for key in pairs(chestTemplate.items) do
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

    if targetName ~= config.inputChest and exists(targetName) then
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
  if not config.inputChest then
    lastStatus = "No input chest selected"
    return
  end

  if not exists(config.inputChest) then
    lastStatus = "Input chest not found"
    return
  end

  if countItemTemplates() == 0 then
    lastStatus = "No templates. Save samples first"
    return
  end

  local routes = buildRoutes()
  local input = peripheral.wrap(config.inputChest)

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
      unknownTotal = unknownTotal + item.count

      if config.unsortedChest and exists(config.unsortedChest) then
        local ok, amount = pcall(function()
          return input.pushItems(config.unsortedChest, slot, item.count)
        end)

        if ok and type(amount) == "number" then
          movedTotal = movedTotal + amount
          unknownTotal = unknownTotal - amount
        end
      end
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
  save =   { x = 2,  y = 3,  w = 20, h = 3, label = "SAVE SAMPLES" },
  rebuild ={ x = 24, y = 3,  w = 20, h = 3, label = "REBUILD ALL" },

  sort =   { x = 2,  y = 7,  w = 20, h = 3, label = "SORT NOW" },
  auto =   { x = 24, y = 7,  w = 20, h = 3, label = "AUTO: ON" },

  next =   { x = 2,  y = 11, w = 20, h = 3, label = "NEXT CHEST" },
  use =    { x = 24, y = 11, w = 20, h = 3, label = "USE AS INPUT" },

  exit =   { x = 2,  y = 15, w = 20, h = 3, label = "EXIT" },
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

  local inventories = getAllInventories()
  local selected = getSelectedChest()

  writeAt(2, 1, "AUTO SORTER V3", colors.yellow, colors.black)

  buttons.auto.label = autoSort and "AUTO: ON" or "AUTO: OFF"

  drawButton(buttons.save, buttons.save.label, colors.blue)
  drawButton(buttons.rebuild, buttons.rebuild.label, colors.orange)

  drawButton(buttons.sort, buttons.sort.label, colors.green)
  drawButton(buttons.auto, buttons.auto.label, autoSort and colors.lime or colors.gray)

  drawButton(buttons.next, buttons.next.label, colors.purple)
  drawButton(buttons.use, buttons.use.label, colors.cyan)

  drawButton(buttons.exit, buttons.exit.label, colors.red)

  local y = 19

  writeAt(2, y,     "Detected chests: " .. tostring(#inventories), colors.white, colors.black)
  writeAt(2, y + 1, "Selected: " .. shortName(selected, 34), colors.white, colors.black)
  writeAt(2, y + 2, "Input: " .. shortName(config.inputChest, 34), colors.white, colors.black)

  writeAt(2, y + 4, "Chest templates: " .. tostring(countChestTemplates()), colors.lightGray, colors.black)
  writeAt(2, y + 5, "Item samples: " .. tostring(countItemTemplates()), colors.lightGray, colors.black)
  writeAt(2, y + 6, "Unique items: " .. tostring(countUniqueRoutes()), colors.lightGray, colors.black)

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
    saveSamples(false)

  elseif inButton(buttons.rebuild, x, y) then
    saveSamples(true)

  elseif inButton(buttons.sort, x, y) then
    sortOnce()

  elseif inButton(buttons.auto, x, y) then
    autoSort = not autoSort
    lastStatus = autoSort and "Auto sort enabled" or "Auto sort disabled"

  elseif inButton(buttons.next, x, y) then
    local inventories = getAllInventories()

    if #inventories == 0 then
      selectedIndex = 1
      lastStatus = "No chests detected"
    else
      selectedIndex = selectedIndex + 1

      if selectedIndex > #inventories then
        selectedIndex = 1
      end

      lastStatus = "Selected next chest"
    end

  elseif inButton(buttons.use, x, y) then
    local selected = getSelectedChest()

    if selected then
      config.inputChest = selected
      saveConfig()
      lastStatus = "Input chest saved"
    else
      lastStatus = "No chest selected"
    end

  elseif inButton(buttons.exit, x, y) then
    clear()
    error("Exit", 0)
  end

  draw()
end

------------------------------------------------------------
-- START
------------------------------------------------------------

loadConfig()
loadTemplate()

if FIXED_INPUT_CHEST then
  config.inputChest = FIXED_INPUT_CHEST
end

if FIXED_UNSORTED_CHEST then
  config.unsortedChest = FIXED_UNSORTED_CHEST
end

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
