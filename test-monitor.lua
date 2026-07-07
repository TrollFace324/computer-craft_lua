while true do
  local e, side, x, y = os.pullEvent("monitor_touch")
  print(side, x, y)
end
