-- test_lily_like_place.lua
-- Put the turtle directly above the water.
-- Put the lily pad / plant item into the turtle inventory.
-- The turtle will try to place it downward.

local function findItemSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end

  return nil
end

local slot = findItemSlot()

if not slot then
  print("No item found in turtle inventory.")
  return
end

turtle.select(slot)

local ok, err = turtle.placeDown()

if ok then
  print("SUCCESS: placed item below the turtle.")
else
  print("FAILED: could not place item below.")
  print("Reason: " .. tostring(err))
end
