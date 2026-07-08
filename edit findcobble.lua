for _, name in ipairs(peripheral.getNames()) do
  local p = peripheral.wrap(name)

  if type(p) == "table" and p.list then
    for slot, item in pairs(p.list()) do
      if item.name == "minecraft:cobblestone" then
        print(name .. " slot " .. slot .. " x" .. item.count)
      end
    end
  end
end
