-- try_place_all.lua
-- Tries to place the selected item in every direction.
-- Turtle orientation is restored after each turn.

local function findItemSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end

  return nil
end

local function tryPlace(label, placeFunc)
  print("Trying to place: " .. label)

  local ok, err = placeFunc()

  if ok then
    print("SUCCESS: placed block " .. label .. ".")
    return true
  else
    print("Failed " .. label .. ": " .. tostring(err))
    return false
  end
end

local slot = findItemSlot()

if not slot then
  print("No items found in turtle inventory.")
  return
end

turtle.select(slot)
print("Using item from slot " .. slot .. ".")

-- 1. Front
if tryPlace("in front", turtle.place) then return end

-- 2. Up
if tryPlace("above", turtle.placeUp) then return end

-- 3. Down
if tryPlace("below", turtle.placeDown) then return end

-- 4. Left
turtle.turnLeft()
if tryPlace("to the left", turtle.place) then
  turtle.turnRight()
  return
end
turtle.turnRight()

-- 5. Right
turtle.turnRight()
if tryPlace("to the right", turtle.place) then
  turtle.turnLeft()
  return
end
turtle.turnLeft()

-- 6. Back
turtle.turnLeft()
turtle.turnLeft()
if tryPlace("behind", turtle.place) then
  turtle.turnLeft()
  turtle.turnLeft()
  return
end
turtle.turnLeft()
turtle.turnLeft()

print("FAILED: could not place the block in any direction.")
