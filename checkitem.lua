local INPUT_CHEST = "carved_wood:barrel_1"
local TEMPLATE_FILE = "autosort_template.tbl"

local unserialize = textutils.unserialise or textutils.unserialize

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
  print("Input not found")
  return
end

local firstSlot = nil
local firstItem = nil

for slot, item in pairs(input.list()) do
  firstSlot = slot
  firstItem = item
  break
end

if not firstItem then
  print("Input is empty")
  return
end

local key = firstItem.name
local template = loadTemplate()

print("Input slot: " .. firstSlot)
print("Input item: " .. key)
print("Count: " .. firstItem.count)
print("----")

local found = false

for groupName, groupData in pairs(template.groups or {}) do
  if groupData.items and groupData.items[key] then
    found = true
    print("FOUND in " .. groupName)

    for _, chestName in ipairs(groupData.chests or {}) do
      print("Target: " .. chestName)
    end
  end
end

if not found then
  print("NOT FOUND IN TEMPLATE")
end
