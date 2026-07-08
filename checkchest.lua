local name = "carved_wood:chest_9"
local p = peripheral.wrap(name)

print("Chest: " .. name)
print("Found: " .. tostring(p ~= nil))

if not p then
  return
end

print("Has list: " .. tostring(type(p.list) == "function"))
print("Has pushItems: " .. tostring(type(p.pushItems) == "function"))

if p.size then
  print("Size: " .. tostring(p.size()))
end

print("Items:")

local total = 0

for slot, item in pairs(p.list()) do
  total = total + item.count
  print(slot .. ": " .. item.name .. " x" .. item.count)
end

print("Total: " .. total)
