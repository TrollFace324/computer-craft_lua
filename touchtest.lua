local mon = peripheral.find("monitor")

print("Monitor found: " .. tostring(mon ~= nil))

for _, name in ipairs(peripheral.getNames()) do
  print(name .. " = " .. tostring(peripheral.getType(name)))
end

if mon then
  mon.clear()
  mon.setCursorPos(1, 1)
  mon.write("RIGHT CLICK ME")
end

print("Waiting for events...")

while true do
  local event = { os.pullEvent() }
  print(textutils.serialize(event))
end
