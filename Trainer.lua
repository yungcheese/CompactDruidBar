-- Compact Druid Bar - trainer helper
-- At the class trainer: a small panel next to the trainer window that sorts
-- what you can learn into "useful", "optional" and "can wait" for your talent
-- spec, with the gold each group costs. Nothing is ever bought automatically.
-- On level-up: a chat note with what's new at the trainer (remembered from
-- your last visit, so no spell list has to be kept up to date here).

local ADDON, ns = ...

-- Rank 1 IDs; their names come from the game, so this works in every language.
local GROUPS = {
  feral = { 1082, 1822, 1079, 5221, 22568, 5217, 5215, 9005, 6785, 1850, 8998, 5225, 768, 5487, 9634,
    6807, 779, 6795, 99, 5211, 5229, 22842, 16979, 16857, 5209 },
  heal = { 5185, 8936, 774, 740, 20484, 2782, 2893, 8946, 29166, 18562, 17116 },
  balance = { 5176, 8921, 2912, 339, 2637, 16914, 5570, 2908, 770, 16689 },
  general = { 1126, 467, 1066, 783, 18960, 22812, 21849 },
}
-- Per spec: what each group counts as.
local WEIGHT = {
  feral   = { feral = "useful", general = "useful", heal = "optional", balance = "wait" },
  resto   = { heal = "useful", general = "useful", balance = "optional", feral = "wait" },
  balance = { balance = "useful", general = "useful", heal = "optional", feral = "wait" },
}
local LABEL = {
  useful = "|cff40ff40Useful|r", optional = "|cffffd100Optional|r", wait = "|cff999999Can wait|r",
  unknown = "|cffccccccOther|r",
}

local nameGroup
local function GroupOf(name)
  if not nameGroup then
    nameGroup = {}
    for group, ids in pairs(GROUPS) do
      for _, id in ipairs(ids) do
        local n = ns.SpellName and ns.SpellName(id)
        if n then nameGroup[n] = group end
      end
    end
  end
  return nameGroup[name]
end

local function Verdict(name)
  local spec = ns.CurrentSpec and ns:CurrentSpec()
  local group = GroupOf(name)
  if not group then return "unknown" end
  if not spec then return "useful" end -- no talents yet: everything helps while leveling
  return WEIGHT[spec][group] or "unknown"
end

local function Money(c)
  if GetCoinTextureString then return GetCoinTextureString(c or 0) end
  return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

local function SafeCall(fn, ...)
  if not fn then return end
  local ok, a, b, c, d = pcall(fn, ...)
  if ok then return a, b, c, d end
end

------------------------------------------------------------------------
-- Reading the trainer
------------------------------------------------------------------------
-- Returns a list of { name, rank, level, cost, state, verdict }.
local function ReadServices()
  local list = {}
  local n = SafeCall(GetNumTrainerServices) or 0
  for i = 1, n do
    local name, rank, state = SafeCall(GetTrainerServiceInfo, i)
    if name and state ~= "header" then
      list[#list + 1] = {
        name = name, rank = rank or "", state = state,
        level = SafeCall(GetTrainerServiceLevelReq, i) or 0,
        cost = SafeCall(GetTrainerServiceCost, i) or 0,
        verdict = Verdict(name),
      }
    end
  end
  return list
end

-- Remember what the trainer offers, for the level-up note.
local function Remember(list)
  if not ns.charData then return end
  local known = {}
  for _, s in ipairs(list) do
    if s.state ~= "used" and s.level > 0 then
      known[#known + 1] = { name = s.name, rank = s.rank, level = s.level, cost = s.cost }
    end
  end
  ns.charData.trainer = known
end

------------------------------------------------------------------------
-- Panel next to the trainer window
------------------------------------------------------------------------
local panel
local function BuildPanel()
  panel = CreateFrame("Frame", "CompactDruidBarTrainer", UIParent, "BackdropTemplate")
  panel:SetSize(250, 300)
  panel:SetFrameStrata("HIGH")
  panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  panel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
  panel:SetBackdropBorderColor(0.85, 0.68, 0.25, 1)
  panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 10, -10)
  panel.title:SetText("Compact Druid Bar: what to learn")
  panel.sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  panel.sub:SetPoint("TOPLEFT", 10, -28)
  panel.sub:SetJustifyH("LEFT")
  panel.body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  panel.body:SetPoint("TOPLEFT", 10, -50)
  panel.body:SetWidth(230)
  panel.body:SetJustifyH("LEFT")
  panel.body:SetSpacing(2)
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function() panel:Hide() end)
  panel:Hide()
end

-- What happened at the last trainer visit, for /cdbdebug.
ns.trainerDebug = { events = {} }
local function Update()
  local dbg = ns.trainerDebug
  dbg.ran = (dbg.ran or 0) + 1
  dbg.api = (GetNumTrainerServices and "yes" or "no") .. "/" .. (GetTrainerServiceInfo and "yes" or "no")
  dbg.tradeskill = IsTradeskillTrainer and tostring(SafeCall(IsTradeskillTrainer)) or "n/a"
  dbg.n = SafeCall(GetNumTrainerServices)
  local a, b, c = SafeCall(GetTrainerServiceInfo, 1)
  dbg.first = tostring(a) .. " | " .. tostring(b) .. " | " .. tostring(c)
  dbg.frame = ClassTrainerFrame and (ClassTrainerFrame:IsShown() and "shown" or "hidden") or "missing"
  if not (ns.db and ns.db.trainerHelper) then dbg.stop = "option off"; if panel then panel:Hide() end return end
  local _, class = UnitClass("player")
  if class ~= "DRUID" then return end
  if IsTradeskillTrainer and SafeCall(IsTradeskillTrainer) then dbg.stop = "profession trainer"; if panel then panel:Hide() end return end
  local list = ReadServices()
  Remember(list)
  local groups, totals = { useful = {}, optional = {}, wait = {}, unknown = {} }, { useful = 0, optional = 0, wait = 0, unknown = 0 }
  local count = 0
  local myLevel = UnitLevel("player") or 0
  for _, s in ipairs(list) do
    -- Some clients use other state names: anything learnable at your level counts too.
    local learnable = s.state == "available"
      or (s.state ~= "used" and s.state ~= "unavailable" and s.level <= myLevel)
    if learnable then
      local g = groups[s.verdict] or groups.unknown
      g[#g + 1] = s
      totals[s.verdict] = (totals[s.verdict] or 0) + s.cost
      count = count + 1
    end
  end
  dbg.available = count
  if count == 0 then dbg.stop = "nothing learnable found"; if panel then panel:Hide() end return end
  dbg.stop = "panel shown"
  if not panel then BuildPanel() end

  local spec = ns.CurrentSpec and ns:CurrentSpec()
  panel.sub:SetText(spec and ("Based on your " .. spec .. " talents. Nothing is bought for you.")
    or "No talents yet: everything helps while leveling.")
  local lines = {}
  local all = 0
  for _, key in ipairs({ "useful", "optional", "wait", "unknown" }) do
    local g = groups[key]
    if #g > 0 then
      lines[#lines + 1] = ("%s  %s"):format(LABEL[key], Money(totals[key]))
      for _, s in ipairs(g) do
        lines[#lines + 1] = ("   %s |cff999999%s|r"):format(s.name, s.rank)
      end
      lines[#lines + 1] = " "
      all = all + totals[key]
    end
  end
  lines[#lines + 1] = "Everything: " .. Money(all)
  panel.body:SetText(table.concat(lines, "\n"))
  panel:SetHeight(panel.body:GetStringHeight() + 64)

  panel:ClearAllPoints()
  local trainer = ClassTrainerFrame
  if trainer and trainer:IsShown() then
    panel:SetPoint("TOPLEFT", trainer, "TOPRIGHT", -30, -12)
  else
    panel:SetPoint("LEFT", UIParent, "CENTER", 200, 0)
  end
  panel:Show()
end

------------------------------------------------------------------------
-- Level-up note
------------------------------------------------------------------------
local function OnLevelUp(level)
  if not (ns.db and ns.db.levelUpReminder and ns.charData and ns.charData.trainer) then return end
  local useful, other, cost = {}, 0, 0
  for _, s in ipairs(ns.charData.trainer) do
    if s.level == level then
      if Verdict(s.name) == "useful" then
        useful[#useful + 1] = s.name .. (s.rank ~= "" and (" (" .. s.rank .. ")") or "")
        cost = cost + (s.cost or 0)
      else
        other = other + 1
      end
    end
  end
  if #useful == 0 and other == 0 then return end
  local msg = "|cff4fe8ffCompact Druid Bar|r: new at your trainer: "
  if #useful > 0 then
    msg = msg .. table.concat(useful, ", ") .. " (" .. Money(cost) .. ")"
    if other > 0 then msg = msg .. (" + %d other"):format(other) end
  else
    msg = msg .. ("%d spell(s) that can wait"):format(other)
  end
  print(msg)
end

------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_LEVEL_UP" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  local ev = ns.trainerDebug.events
  ev[event] = (ev[event] or 0) + 1
  if event == "TRAINER_CLOSED" then
    if panel then panel:Hide() end
  elseif event == "PLAYER_LEVEL_UP" then
    OnLevelUp(tonumber(arg1))
  else
    -- The trainer list fills in a moment after the window opens.
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Update) else Update() end
  end
end)
