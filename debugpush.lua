local INPUT_CHEST = "carved_wood:barrel_0"
local TEMPLATE_FILE = "autosort_template.tbl"

local unserialize = textutils.unserialise or textutils.unserialize

local function itemKey(item)
  return item.name
end

local function loadTemplate()
  if not fs.exists(TEMPLATE_FILE) then
    print("No template file")
    return nil
  end

  local f = fs.open(TEMPLATE_FILE, "r")
  local raw = f.readAll()
  f.close()

  return unserialize(raw)
end

local input = peripheral.wrap(INPUT_CHEST)

if not input then
  print("Input not found: " .. INPUT_CHEST)
  return
end

local template = loadTemplate()

if not template then
  return
end

print("Input: " .. INPUT_CHEST)

local inputItems = input.list()
local firstSlot = nil
local firstItem = nil

for slot, item in pairs(inputItems) do
  firstSlot = slot
  firstItem = item
  break
end

if not firstItem then
  print("Input chest is empty")
  return
end

local key = itemKey(firstItem)

print("Slot: " .. firstSlot)
print("Item: " .. firstItem.name)
print("Count: " .. firstItem.count)
print("Key: " .. key)
print("----")

local targets = {}

for groupName, groupData in pairs(template.groups or {}) do
  if groupData.items and groupData.items[key] then
    print("Found in template: " .. groupName)

    for _, chestName in ipairs(groupData.chests or {}) do
      table.insert(targets, chestName)
      print("Target: " .. chestName)
    end
  end
end

print("----")
print("Targets: " .. #targets)

if #targets == 0 then
  print("No targets for this item")
  return
end

for _, chestName in ipairs(targets) do
  local p = peripheral.wrap(chestName)

  print("Testing: " .. chestName)
  print("Exists: " .. tostring(p ~= nil))

  if p and p.list then
    local used = 0
    local total = 0

    if p.size then
      total = p.size()
    end

    for _ in pairs(p.list()) do
      used = used + 1
    end

    print("Slots: " .. used .. "/" .. total)
  end

  local ok, moved = pcall(function()
    return input.pushItems(chestName, firstSlot, firstItem.count)
  end)

  print("push ok: " .. tostring(ok))
  print("moved: " .. tostring(moved))
  print("----")
end
