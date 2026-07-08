-- autosort.lua
-- Fast infinite auto sorter with terminal logs.
-- Side peripherals like bottom/top/left/right/front/back are ignored.
-- Fixed input barrel.
-- 3x3 monitor UI. SAVE button is on middle-left monitor block.

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local INPUT_CHEST = "carved_wood:barrel_1"

local TEMPLATE_FILE = "autosort_template.tbl"
local MATCH_NBT = false

-- true = show detailed logs in PC terminal
local LOG_ENABLED = true

-- true = log every unknown item every time
-- false = log unknown item only once
local LOG_UNKNOWN_EVERY_TIME = false

-- Groups without names.
-- Program will create group_1, group_2, group_3...
local CHEST_GROUPS = {
  {
    -- "carved_wood:chest_9",
    -- "carved_wood:chest_10",
  },

  {
    -- "carved_wood:chest_11",
    -- "carved_wood:chest_12",
  },
}

-- true = chests not listed in CHEST_GROUPS become solo groups automatically.
-- false = unlisted chests are ignored.
local AUTO_ADD_UNGROUPED_CHESTS = true

------------------------------------------------------------
-- SYSTEM
------------------------------------------------------------

local TEMPLATE_VERSION = 12

local serialize = textutils.serialise or textutils.serialize
local unserialize = textutils.unserialise or textutils.unserialize

local template = {
  version = TEMPLATE_VERSION,
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
local logTerm = term.current()

local loggedUnknown = {}
local loggedFull = {}

------------------------------------------------------------
-- LOGGING
------------------------------------------------------------

local function log(msg)
  if not LOG_ENABLED then
    return
  end

  local oldTerm = term.current()

  pcall(function()
    term.redirect(logTerm)

    local w, h = term.getSize()
    local x, y = term.getCursorPos()

    if y >= h then
      term.scroll(1)
      term.setCursorPos(1, h)
    end

    print("[SORT] " .. tostring(msg))
  end)

  pcall(function()
    term.redirect(oldTerm)
  end)
end

local function logSep()
  log("--------------------------------")
end

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

local function isSideName(name)
  return name == "top"
    or name == "bottom"
    or name == "left"
    or name == "right"
    or name == "front"
    or name == "back"
end

local function exists(name)
  return name and peripheral.wrap(name) ~= nil
end

local function isInventory(name)
  if isSideName(name) then
    return false
  end

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

------------------------------------------------------------
-- FILES
------------------------------------------------------------

local function saveTemplateFile()
  local f = fs.open(TEMPLATE_FILE, "w")

  if not f then
    lastStatus = "Cannot save file"
    needRedraw = true
    log("ERROR: cannot save template file")
    return false
  end

  f.write(serialize(template))
  f.close()

  log("Template file saved: " .. TEMPLATE_FILE)
  return true
end

local function loadTemplateFile()
  if not fs.exists(TEMPLATE_FILE) then
    log("No template file yet")
    return
  end

  local f = fs.open(TEMPLATE_FILE, "r")

  if not f then
    log("ERROR: cannot open template file")
    return
  end

  local raw = f.readAll()
  f.close()

  local data = unserialize(raw)

  if type(data) == "table"
    and data.version == TEMPLATE_VERSION
    and type(data.groups) == "table"
  then
    template = data
    MATCH_NBT = data.match_nbt or false
    lastSaved = data.saved_at or "unknown"
    lastStatus = "Template loaded"
    log("Template loaded")
  else
    lastStatus = "Old template ignored"
    log("Old/broken template ignored. Delete " .. TEMPLATE_FILE .. " and SAVE again if needed.")
  end
end

------------------------------------------------------------
-- INVENTORIES AND GROUPS
------------------------------------------------------------

local function getAllInventories()
  local result = {}

  for _, name in ipairs(peripheral.getNames()) do
    if name ~= monitorName
      and name ~= INPUT_CHEST
      and not isSideName(name)
      and isInventory(name)
    then
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
      if not isSideName(chestName) then
        set[chestName] = true
      end
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
      if chestName ~= INPUT_CHEST
        and not isSideName(chestName)
        and exists(chestName)
        and isInventory(chestName)
      then
        table.insert(groups[groupName].chests, chestName)
      else
        if chestName ~= nil and chestName ~= "" then
          log("Group skip invalid chest: " .. tostring(chestName))
        end
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
  local groups = getActiveGroups()
  local n = 0

  for _, group in pairs(groups) do
    if #group.chests > 0 then
      n = n + 1
    end
  end

  return n
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
      local chestItemCount = 0

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
        chestItemCount = chestItemCount + item.count
      end

      log("Scan chest " .. chestName .. " items=" .. chestItemCount)
    else
      log("Scan failed, chest missing: " .. tostring(chestName))
    end
  end

  return items
end

local function rebuildRoutes()
  local newRoutes = {}
  local activeGroups = getActiveGroups()
  local routeCount = 0

  for groupName, groupData in pairs(template.groups or {}) do
    local activeGroup = activeGroups[groupName]
    local targetChests = {}

    if activeGroup and type(activeGroup.chests) == "table" then
      for _, chestName in ipairs(activeGroup.chests) do
        if chestName ~= INPUT_CHEST
          and not isSideName(chestName)
          and exists(chestName)
          and isInventory(chestName)
        then
          table.insert(targetChests, chestName)
        end
      end
    elseif type(groupData.chests) == "table" then
      for _, chestName in ipairs(groupData.chests) do
        if chestName ~= INPUT_CHEST
          and not isSideName(chestName)
          and exists(chestName)
          and isInventory(chestName)
        then
          table.insert(targetChests, chestName)
        end
      end
    end

    log("Route group " .. groupName .. " targets=" .. tostring(#targetChests))

    if type(groupData.items) == "table" then
      for key in pairs(groupData.items) do
        newRoutes[key] = newRoutes[key] or {}

        for _, chestName in ipairs(targetChests) do
          addUnique(newRoutes[key], chestName)
        end

        routeCount = routeCount + 1
      end
    end
  end

  routes = newRoutes
  log("Routes rebuilt. Items with routes=" .. tostring(routeCount))
end

local function saveTemplate()
  logSep()
  log("SAVE pressed")

  if not exists(INPUT_CHEST) then
    lastStatus = "Input not found"
    needRedraw = true
    log("ERROR: input not found: " .. INPUT_CHEST)
    return
  end

  local activeGroups = getActiveGroups()
  local newGroups = {}
  local sampleCount = 0
  local usedGroups = 0

  for groupName, group in pairs(activeGroups) do
    if #group.chests > 0 then
      log("Saving " .. groupName .. " chests=" .. tostring(#group.chests))

      for _, chestName in ipairs(group.chests) do
        log("  chest: " .. chestName)
      end

      local items = scanGroup(group)
      local hasItems = false
      local itemTypes = 0

      for key, data in pairs(items) do
        hasItems = true
        sampleCount = sampleCount + 1
        itemTypes = itemTypes + 1
        log("  sample: " .. key .. " x" .. tostring(data.count))
      end

      if hasItems then
        newGroups[groupName] = {
          saved_at = getTimeString(),
          chests = group.chests,
          items = items,
        }

        usedGroups = usedGroups + 1
        log("  saved group item types=" .. tostring(itemTypes))
      else
        log("  group empty, not saved")
      end
    end
  end

  template = {
    version = TEMPLATE_VERSION,
    match_nbt = MATCH_NBT,
    saved_at = getTimeString(),
    groups = newGroups,
  }

  lastSaved = template.saved_at

  if saveTemplateFile() then
    rebuildRoutes()
    lastStatus = "Saved: " .. sampleCount .. " samples"
    log("SAVE done. groups=" .. usedGroups .. " samples=" .. sampleCount)
  end

  loggedUnknown = {}
  loggedFull = {}

  needRedraw = true
end

------------------------------------------------------------
-- SORTING
------------------------------------------------------------

local function tryPushToTargets(input, slot, item, targets)
  local remaining = item.count
  local moved = 0

  log("Try move " .. item.name .. " x" .. item.count .. " from slot " .. tostring(slot) .. " targets=" .. tostring(#targets))

  for _, targetName in ipairs(targets) do
    if remaining <= 0 then
      break
    end

    if targetName ~= INPUT_CHEST
      and not isSideName(targetName)
      and exists(targetName)
    then
      local ok, amount = pcall(function()
        return input.pushItems(targetName, slot, remaining)
      end)

      if ok then
        log("  push -> " .. targetName .. " moved=" .. tostring(amount))

        if type(amount) == "number" and amount > 0 then
          moved = moved + amount
          remaining = remaining - amount
        end
      else
        log("  push ERROR -> " .. targetName .. " : " .. tostring(amount))
      end
    else
      log("  skip invalid target: " .. tostring(targetName))
    end
  end

  if moved == 0 then
    log("  nothing moved for " .. item.name)
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
  local sawAnyInput = false

  for slot, item in pairs(input.list()) do
    sawAnyInput = true

    local key = itemKey(item)
    local targets = routes[key]

    if targets and #targets > 0 then
      local moved, remaining = tryPushToTargets(input, slot, item, targets)

      movedTotal = movedTotal + moved

      if remaining > 0 then
        fullTotal = fullTotal + remaining

        if not loggedFull[key] then
          loggedFull[key] = true
          log("FULL/SKIP: " .. key .. " remaining=" .. tostring(remaining))
        end
      end
    else
      unknownTotal = unknownTotal + item.count

      if LOG_UNKNOWN_EVERY_TIME or not loggedUnknown[key] then
        loggedUnknown[key] = true
        log("UNKNOWN/SKIP: " .. key .. " x" .. tostring(item.count) .. " not found in template")
      end
    end
  end

  lastMoved = movedTotal
  lastUnknown = unknownTotal
  lastFull = fullTotal
  cycles = cycles + 1

  lastStatus = "M:" .. movedTotal .. " U:" .. unknownTotal .. " F:" .. fullTotal

  if movedTotal > 0 or unknownTotal > 0 or fullTotal > 0 or cycles % 20 == 0 then
    needRedraw = true
  end

  if cycles % 100 == 0 then
    if sawAnyInput then
      log("Cycle " .. cycles .. " result: " .. lastStatus)
    else
      log("Cycle " .. cycles .. ": input empty")
    end
  end
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

  writeAt(2, 1, "SORTER", colors.yellow, colors.black)
  writeAt(2, 2, "FAST LOOP", colors.lime, colors.black)
  writeAt(2, 3, "S=SAVE", colors.gray, colors.black)

  writeAt(x2, 1, "INPUT", colors.yellow, colors.black)
  writeAt(x2, 2, shortText(INPUT_CHEST, colW - 2), colors.white, colors.black)
  writeAt(x2, 3, "FND:" .. tostring(exists(INPUT_CHEST)), colors.white, colors.black)

  writeAt(x3, 1, "NET", colors.yellow, colors.black)
  writeAt(x3, 2, "ST:" .. tostring(#getStorageChests()), colors.white, colors.black)
  writeAt(x3, 3, "GR:" .. tostring(countActiveGroups()), colors.white, colors.black)

  drawButton()

  writeAt(x2, rowH + 2, "TEMPLATE", colors.yellow, colors.black)
  writeAt(x2, rowH + 3, "TG:" .. tostring(countTemplateGroups()), colors.lightGray, colors.black)
  writeAt(x2, rowH + 4, "S:" .. tostring(countSamples()), colors.lightGray, colors.black)
  writeAt(x2, rowH + 5, "U:" .. tostring(countUniqueItems()), colors.lightGray, colors.black)

  writeAt(x3, rowH + 2, "SORT", colors.yellow, colors.black)
  writeAt(x3, rowH + 3, "MV:" .. tostring(lastMoved), colors.white, colors.black)
  writeAt(x3, rowH + 4, "UN:" .. tostring(lastUnknown), colors.white, colors.black)
  writeAt(x3, rowH + 5, "FL:" .. tostring(lastFull), colors.white, colors.black)

  writeAt(2, rowH * 2 + 2, "STATUS", colors.yellow, colors.black)
  writeAt(2, rowH * 2 + 3, shortText(lastStatus, colW - 1), colors.white, colors.black)
  writeAt(2, rowH * 2 + 4, "C:" .. tostring(cycles), colors.gray, colors.black)

  writeAt(x2, rowH * 2 + 2, "LAST SAVE", colors.yellow, colors.black)
  writeAt(x2, rowH * 2 + 3, shortText(lastSaved, colW - 2), colors.lightGray, colors.black)

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

local function handleEvent(event, a, b, c)
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
    elseif a == keys.q then
      clear()
      error("Exit", 0)
    end

  elseif event == "monitor_resize" or event == "term_resize" then
    needRedraw = true
  end
end

------------------------------------------------------------
-- START
------------------------------------------------------------

term.clear()
term.setCursorPos(1, 1)

logSep()
log("Program start")
log("Input: " .. INPUT_CHEST)
log("Monitor: " .. tostring(monitorName))
log("Detected storage chests:")

for _, chestName in ipairs(getStorageChests()) do
  log("  " .. chestName)
end

loadTemplateFile()
rebuildRoutes()
draw()

while true do
  sortOnePass()

  if needRedraw then
    draw()
  end

  os.queueEvent("autosort_tick")
  local event, a, b, c = os.pullEvent()
  handleEvent(event, a, b, c)
end
