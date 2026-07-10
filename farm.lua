-- farm.lua
-- Воронка должна быть ПОД черепашкой
-- Растение должно быть ПЕРЕД черепашкой
-- Лучше запускать с пустым инвентарём

local function collectDrops()
  -- turtle.dig() часто сам собирает дроп,
  -- но suck() помогает подобрать предметы, если они выпали перед черепашкой
  for i = 1, 5 do
    turtle.suck()
    sleep(0.2)
  end
end

local function findItemSlot()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      return slot
    end
  end
  return nil
end

local function dumpEverythingExceptOne()
  local keepSlot = findItemSlot()

  if not keepSlot then
    print("Нет предметов после ломания.")
    return nil
  end

  -- Скидываем всё из остальных слотов вниз в воронку
  for slot = 1, 16 do
    turtle.select(slot)

    if slot ~= keepSlot then
      local count = turtle.getItemCount(slot)
      if count > 0 then
        turtle.dropDown(count)
      end
    end
  end

  -- В выбранном слоте оставляем только 1 предмет
  turtle.select(keepSlot)
  local count = turtle.getItemCount(keepSlot)

  if count > 1 then
    turtle.dropDown(count - 1)
  end

  return keepSlot
end

-- 1. Ломаем растение перед собой
local ok, err = turtle.dig()

if not ok then
  print("Не смог сломать блок: " .. tostring(err))
  return
end

sleep(0.3)

-- 2. Собираем выпавшие предметы
collectDrops()

-- 3. Всё кроме одного предмета складываем вниз в воронку
local keepSlot = dumpEverythingExceptOne()

if not keepSlot then
  return
end

-- 4. Ставим последний оставшийся предмет перед собой
turtle.select(keepSlot)

local placed, placeErr = turtle.place()

if not placed then
  print("Не смог поставить предмет обратно: " .. tostring(placeErr))
else
  print("Готово: растение пересажено, лишнее отправлено в воронку.")
end
