-- try_place_static.lua
-- The turtle does not move and does not turn.
-- It only tries place(), placeUp(), and placeDown().

local function findItemSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end

  return nil
end

local function tryPlace(label, func)
  print("Trying: " .. label)

  local ok, err = func()

  if ok then
    print("SUCCESS: placed " .. label .. ".")
    return true
  end

  print("Failed " .. label .. ": " .. tostring(err))
  return false
end

local slot = findItemSlot()

if not slot then
  print("No items found in turtle inventory.")
  return
end

turtle.select(slot)
print("Using item from slot " .. slot .. ".")

if tryPlace("in front", turtle.place) then
  return
end

if tryPlace("above", turtle.placeUp) then
  return
end

if tryPlace("below", turtle.placeDown) then
  return
end

print("FAILED: could not place the item using front/up/down.")
