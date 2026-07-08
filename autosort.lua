-- autosort.lua
-- Fast infinite auto sorter with unnamed chest groups.
-- Fixed input: carved_wood:barrel_0
-- 3x3 monitor UI. SAVE button is on middle-left monitor block.

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local INPUT_CHEST = "carved_wood:barrel_0"

local TEMPLATE_FILE = "autosort_template.tbl"
local MATCH_NBT = false

-- Groups without names.
-- Program will create: group_1, group_2, group_3...
--
-- If an item exists in any chest of group_1,
-- that item may be placed into any chest of group_1.
--
-- Example:
-- local CHEST_GROUPS = {
--   {
--     "minecraft:chest_1",
--     "minecraft:chest_2",
--   },
--
--   {
--     "minecraft:barrel_3",
--     "minecraft:barrel_4",
--   },
-- }

local CHEST_GROUPS = {
  {
    -- "minecraft:chest_1",
    -- "minecraft:chest_2",
  },

  {
    -- "minecraft:chest_3",
    -- "minecraft:chest_4",
  },
}

-- true = chests not listed in CHEST_GROUPS become solo groups automatically.
-- false = unlisted chests are ignored.
local AUTO_ADD_UNGROUPED_CHESTS = true

------------------------------------------------------------
-- SYSTEM
------------------------------------------------------------

local serialize = textutils.serialise or textutils.serialize
local unserialize = textutils.unserialise or textutils.unserialize

local template = {
  version = 10,
  match_nbt = MATCH_NBT,
  saved_at = "never",
  groups = {},
}

local routes = {}

local lastStatus = "Ready"
local lastMoved = 0
local lastUnknown = 0
local lastFull = 0
local lastSaved = "never"
local cycles = 0

local needRedraw = true

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
  len = len or 30

  if len <= 0 then
    return ""
  end

  if #text <= len then
    return text
  end

  if len <= 3 then
    return string.sub(text, 1, len)
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

local function tableSize(t)
  local n = 0

  for _ in pairs(t or {}) do
    n = n + 1
  end

  return n
end

local function yieldNow()
  os.queueEvent("autosort_yield")
  os.pullEvent("autosort_yield")
end

------------------------------------------------------------
-- FILES
------------------------------------------------------------

local function saveTemplateFile()
  local f = fs.open(TEMPLATE_FILE, "w")

  if not f then
    lastStatus = "Cannot save file"
    needRedraw = true
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

  if type(data) == "table" and type(data.groups) == "table" then
    template = data
    MATCH_NBT = data.match_nbt or false
    lastSaved = data.saved_at or "unknown"
    lastStatus = "Template loaded"
  else
    lastStatus = "Old template ignored"
  end
end

------------------------------------------------------------
-- INVENTORIES AND GROUPS
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

local function getManualGroupedSet()
  local set = {}

  for _, groupList in ipairs(CHEST_GROUPS) do
    for _, chestName in ipairs(groupList) do
      set[chestName] = true
    end
  end

  return set
end

local function getActiveGroups()
  local groups = {}
  local manualSet = getManualGroupedSet()
  local groupIndex = 1

  for _, groupList in ipairs(CHEST_GROUPS) do
    local groupName = "group_" .. tostring(groupIndex)

    groups[groupName] = {
      name = groupName,
      chests = {},
    }

    for _, chestName in ipairs(groupList) do
      if chestName ~= INPUT_CHEST and exists(chestName) and isInventory(chestName) then
        table.insert(groups[groupName].chests, chestName)
      end
    end

    table.sort(groups[groupName].chests)

    groupIndex = groupIndex + 1
  end

  if AUTO_ADD_UNGROUPED_CHESTS then
    for _, chestName in ipairs(getStorageChests()) do
      if not manualSet[chestName] then
        local groupName = "group_" .. tostring(groupIndex)

        groups[groupName] = {
          name = groupName,
          chests = { chestName },
        }

        groupIndex = groupIndex + 1
      end
    end
  end

  return groups
end

local function countActiveGroups()
  return tableSize(getActiveGroups())
end

local function countTemplateGroups()
  return tableSize(template.groups)
end

local function countSamples()
  local n = 0

  for _, groupData in pairs(template.groups or {}) do
    if type(groupData.items) == "table" then
      for _ in pairs(groupData.items) do
        n = n + 1
      end
    end
  end

  return n
end

local function countUniqueItems()
  local seen = {}

  for _, groupData in pairs(template.groups or {}) do
    if type(groupData.items) == "table" then
      for key in pairs(groupData.items) do
        seen[key] = true
      end
    end
  end

  return tableSize(seen)
end

------------------------------------------------------------
-- TEMPLATE
------------------------------------------------------------

local function scanGroup(group)
  local items = {}

  for _, chestName in ipairs(group.chests) do
    local chest = peripheral.wrap(chestName)

    if chest then
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
    end
  end

  return items
end

local function rebuildRoutes()
  local newRoutes = {}
  local groupNames = {}

  for groupName in pairs(template.groups or {}) do
    table.insert(groupNames, groupName)
  end

  table.sort(groupNames)

  for _, groupName in ipairs(groupNames) do
    local groupData = template.groups[groupName]

    if type(groupData.items) == "table" and type(groupData.chests) == "table" then
      local availableChests = {}

      for _, chestName in ipairs(groupData.chests) do
        if chestName ~= INPUT_CHEST and exists(chestName) then
          table.insert(availableChests, chestName)
        end
      end

      -- One item can be in several templates/groups.
      -- Then all chests from all those groups become possible targets.
      for key in pairs(groupData.items) do
        newRoutes[key] = newRoutes[key] or {}

        for _, chestName in ipairs(availableChests) do
          addUnique(newRoutes[key], chestName)
        end
      end
    end
  end

  routes = newRoutes
end

local function saveTemplate()
  if not exists(INPUT_CHEST) then
    lastStatus = "Input not found"
    needRedraw = true
    return
  end

  local activeGroups = getActiveGroups()
  local newGroups = {}
  local sampleCount = 0
  local usedGroups = 0

  for groupName, group in pairs(activeGroups) do
    local items = scanGroup(group)
    local hasItems = false

    for _ in pairs(items) do
      hasItems = true
      sampleCount = sampleCount + 1
    end

    if hasItems then
      newGroups[groupName] = {
        saved_at = getTimeString(),
        chests = group.chests,
        items = items,
      }

      usedGroups = usedGroups + 1
    end
  end

  template = {
    version = 10,
    match_nbt = MATCH_NBT,
    saved_at = getTimeString(),
    groups = newGroups,
  }

  lastSaved = template.saved_at

  if saveTemplateFile() then
    rebuildRoutes()
    lastStatus = "Saved: " .. sampleCount .. " samples"
  end

  needRedraw = true
end

------------------------------------------------------------
-- SORTING
------------------------------------------------------------

local function tryPushToTargets(input, slot, item, targets)
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

local function sortOnePass()
  if not exists(INPUT_CHEST) then
    lastStatus = "Input not found"
    return
  end

  if countSamples() == 0 then
    lastStatus = "Press SAVE first"
    return
  end

  local input = peripheral.wrap(INPUT_CHEST)
  if not input then
    lastStatus = "Input wrap failed"
    return
  end

  local movedTotal = 0
  local unknownTotal = 0
  local fullTotal = 0

  for slot, item in pairs(input.list()) do
    local key = itemKey(item)
    local targets = routes[key]

    if targets and #targets > 0 then
      local moved, remaining = tryPushToTargets(input, slot, item, targets)

      movedTotal = movedTotal + moved

      -- If all target chests are full, item is skipped and stays in input.
      if remaining > 0 then
        fullTotal = fullTotal + remaining
      end
    else
      -- No template for this item. Skip it.
      -- It stays in input chest.
      unknownTotal = unknownTotal + item.count
    end
  end

  lastMoved = movedTotal
  lastUnknown = unknownTotal
  lastFull = fullTotal
  cycles = cycles + 1

  lastStatus = "M:" .. movedTotal .. " U:" .. unknownTotal .. " F:" .. fullTotal
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

local button = {
  x = 1,
  y = 7,
  w = 9,
  h = 6,
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

local function updateButtonPosition()
  local sw, sh = screen.getSize()

  local colW = math.floor(sw / 3)
  local rowH = math.floor(sh / 3)

  -- Middle-left monitor block:
  -- [MONITOR][MONITOR][MONITOR]
  -- [SAVE   ][MONITOR][MONITOR]
  -- [MONITOR][MONITOR][MONITOR]

  button.x = 1
  button.y = rowH + 1
  button.w = colW
  button.h = rowH

  if button.w < 6 then
    button.w = 6
  end

  if button.h < 3 then
    button.h = 3
  end
end

local function drawButton()
  updateButtonPosition()

  for yy = 0, button.h - 1 do
    writeAt(button.x, button.y + yy, string.rep(" ", button.w), colors.white, colors.blue)
  end

  local textX = button.x + math.floor((button.w - #button.label) / 2)
  local textY = button.y + math.floor(button.h / 2)

  if textX < button.x then
    textX = button.x
  end

  writeAt(textX, textY, button.label, colors.white, colors.blue)
end

local function draw()
  clear()

  local sw, sh = screen.getSize()
  local colW = math.floor(sw / 3)
  local rowH = math.floor(sh / 3)

  -- Grid lines
  for y = 1, sh do
    if colW + 1 <= sw then
      writeAt(colW + 1, y, "|", colors.gray, colors.black)
    end

    if colW * 2 + 1 <= sw then
      writeAt(colW * 2 + 1, y, "|", colors.gray, colors.black)
    end
  end

  for x = 1, sw do
    if rowH + 1 <= sh then
      writeAt(x, rowH + 1, "-", colors.gray, colors.black)
    end

    if rowH * 2 + 1 <= sh then
      writeAt(x, rowH * 2 + 1, "-", colors.gray, colors.black)
    end
  end

  local x2 = colW + 3
  local x3 = colW * 2 + 3

  -- Top-left
  writeAt(2, 1, "SORTER", colors.yellow, colors.black)
  writeAt(2, 2, "FAST LOOP", colors.lime, colors.black)
  writeAt(2, 3, "S=SAVE", colors.gray, colors.black)

  -- Top-middle
  writeAt(x2, 1, "INPUT", colors.yellow, colors.black)
  writeAt(x2, 2, shortText(INPUT_CHEST, colW - 2), colors.white, colors.black)
  writeAt(x2, 3, "FND:" .. tostring(exists(INPUT_CHEST)), colors.white, colors.black)

  -- Top-right
  writeAt(x3, 1, "NET", colors.yellow, colors.black)
  writeAt(x3, 2, "ST:" .. tostring(#getStorageChests()), colors.white, colors.black)
  writeAt(x3, 3, "GR:" .. tostring(countActiveGroups()), colors.white, colors.black)

  -- Middle-left
  drawButton()

  -- Middle
  writeAt(x2, rowH + 2, "TEMPLATE", colors.yellow, colors.black)
  writeAt(x2, rowH + 3, "TG:" .. tostring(countTemplateGroups()), colors.lightGray, colors.black)
  writeAt(x2, rowH + 4, "S:" .. tostring(countSamples()), colors.lightGray, colors.black)
  writeAt(x2, rowH + 5, "U:" .. tostring(countUniqueItems()), colors.lightGray, colors.black)

  -- Middle-right
  writeAt(x3, rowH + 2, "SORT", colors.yellow, colors.black)
  writeAt(x3, rowH + 3, "MV:" .. tostring(lastMoved), colors.white, colors.black)
  writeAt(x3, rowH + 4, "UN:" .. tostring(lastUnknown), colors.white, colors.black)
  writeAt(x3, rowH + 5, "FL:" .. tostring(lastFull), colors.white, colors.black)

  -- Bottom-left
  writeAt(2, rowH * 2 + 2, "STATUS", colors.yellow, colors.black)
  writeAt(2, rowH * 2 + 3, shortText(lastStatus, colW - 1), colors.white, colors.black)
  writeAt(2, rowH * 2 + 4, "C:" .. tostring(cycles), colors.gray, colors.black)

  -- Bottom-middle
  writeAt(x2, rowH * 2 + 2, "LAST SAVE", colors.yellow, colors.black)
  writeAt(x2, rowH * 2 + 3, shortText(lastSaved, colW - 2), colors.lightGray, colors.black)

  -- Bottom-right
  writeAt(x3, rowH * 2 + 2, "FILE", colors.yellow, colors.black)
  writeAt(x3, rowH * 2 + 3, shortText(TEMPLATE_FILE, colW - 2), colors.lightGray, colors.black)

  needRedraw = false
end

local function inButton(x, y)
  updateButtonPosition()

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
-- LOOPS
------------------------------------------------------------

local function sortLoop()
  while true do
    sortOnePass()

    -- No sleep, no timer.
    -- This only yields so ComputerCraft does not kill the program
    -- and monitor/key events can still be processed.
    yieldNow()
  end
end

local function uiLoop()
  while true do
    if needRedraw then
      draw()
    end

    local event, a, b, c = os.pullEvent()

    if event == "monitor_touch" then
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
      needRedraw = true
    end
  end
end

------------------------------------------------------------
-- START
------------------------------------------------------------

loadTemplateFile()
rebuildRoutes()
draw()

parallel.waitForAny(sortLoop, uiLoop)
