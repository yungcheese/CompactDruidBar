-- Compact Druid Bar - profiles
-- Saved layout sets, chosen per character, with optional automatic switching
-- (raid / party / talent spec) and import/export as a text string.
--
-- CompactDruidBarDB layout:
--   profiles = { [name] = settings }
--   chars    = { ["Name-Realm"] = { profile = name, rules = { raid, party, feral, balance, resto }, shiftCost = {} } }
--   global   = { minimap = { hide, minimapPos } }

local ADDON, ns = ...

local DEFAULT_PROFILE = "Default"
ns.DEFAULT_PROFILE = DEFAULT_PROFILE
ns.RULES = {
  { key = "raid", label = "In a raid" },
  { key = "party", label = "In a party" },
  { key = "feral", label = "Feral talents" },
  { key = "balance", label = "Balance talents" },
  { key = "resto", label = "Restoration talents" },
}

local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[DeepCopy(k)] = DeepCopy(x) end
  return t
end
ns.DeepCopy = DeepCopy

local function CharKey()
  local name, realm
  if UnitFullName then name, realm = UnitFullName("player") end
  name = name or (UnitName and UnitName("player")) or "?"
  realm = realm or (GetRealmName and GetRealmName()) or "?"
  return name .. "-" .. realm:gsub("%s", "")
end

------------------------------------------------------------------------
-- Setup and migration
------------------------------------------------------------------------
function ns:InitProfiles()
  local sv = CompactDruidBarDB or {}
  if not sv.profiles then
    -- Upgrade from a single settings table: it becomes the "Default" profile.
    local old = sv
    sv = { profiles = { [DEFAULT_PROFILE] = old }, chars = {}, global = {} }
    if old.minimap then sv.global.minimap = old.minimap; old.minimap = nil end
    if old.shiftCost then
      sv.chars[CharKey()] = { shiftCost = old.shiftCost }
      old.shiftCost = nil
    end
  end
  sv.profiles = sv.profiles or {}
  sv.chars = sv.chars or {}
  sv.global = sv.global or {}
  sv.global.minimap = sv.global.minimap or {}
  if sv.global.minimap.hide == nil then sv.global.minimap.hide = true end
  sv.global.minimap.minimapPos = sv.global.minimap.minimapPos or 220
  sv.profiles[DEFAULT_PROFILE] = sv.profiles[DEFAULT_PROFILE] or {}
  CompactDruidBarDB = sv

  local key = CharKey()
  sv.chars[key] = sv.chars[key] or {}
  local char = sv.chars[key]
  char.profile = char.profile or DEFAULT_PROFILE
  char.rules = char.rules or {}
  char.shiftCost = char.shiftCost or {}
  self.sv, self.global, self.charData = sv, sv.global, char

  self:ActivateProfile(self:WantedProfile(), true)
end

-- Old settings that need converting, applied to every profile when it loads.
local function UpgradeProfile(p)
  if p.iconSize and not p.iconSizes then
    local s = p.iconSize
    p.iconSizes = { debuffs = s, cooldowns = s, buffs = s }
  end
  if type(p.ccSoundKey) == "string" and p.ccSoundKey:sub(1, 4) == "kit:"
    and p.ccSoundKey ~= "kit:ALARM_CLOCK_WARNING_3" then
    p.ccSoundKey = ns.DEFAULT_SOUND
  end
  p.minimap, p.shiftCost = nil, nil -- moved to global / per character
end

------------------------------------------------------------------------
-- Which profile should be active right now
------------------------------------------------------------------------
-- Talent tree with the most points: "balance", "feral" or "resto" (nil when unclear).
function ns:CurrentSpec()
  if not GetTalentTabInfo then return end
  local names, best, bestPts, tie = { "balance", "feral", "resto" }, nil, 0, false
  for i = 1, 3 do
    local ok, r = pcall(function() return { GetTalentTabInfo(i) } end)
    if ok and r then
      -- Classic returns (name, icon, points, ...); newer clients (id, name, desc, icon, points, ...).
      local pts = type(r[1]) == "number" and r[5] or r[3]
      if type(pts) == "number" then
        if pts > bestPts then best, bestPts, tie = names[i], pts, false
        elseif pts == bestPts and pts > 0 then tie = true end
      end
    end
  end
  if tie or bestPts == 0 then return end
  return best
end

-- Returns the profile name and why it was chosen.
function ns:WantedProfile()
  local char, profiles = self.charData, self.sv.profiles
  local function valid(n) return n and profiles[n] and n end
  local rules = char.rules
  if IsInRaid and IsInRaid() and valid(rules.raid) then return rules.raid, "raid" end
  if IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) and valid(rules.party) then return rules.party, "party" end
  local spec = self:CurrentSpec()
  if spec and valid(rules[spec]) then return rules[spec], spec end
  return valid(char.profile) or DEFAULT_PROFILE, "character"
end

function ns:ActivateProfile(name, initial)
  local profiles = self.sv.profiles
  if not profiles[name] then name = DEFAULT_PROFILE end
  profiles[name] = profiles[name] or {}
  UpgradeProfile(profiles[name])
  self.db = ns.CopyDefaults(ns.DEFAULTS, profiles[name])
  local changed = self.activeProfile ~= name
  self.activeProfile = name
  if initial then return end
  if changed then
    self:Refresh()
    self:UpdateAlpha(true)
    if self.RefreshOptions then self.RefreshOptions() end
  end
end

-- Re-evaluate the automatic rules (group change, talent change, ...).
function ns:CheckProfileRules()
  if not self.sv then return end
  local name = self:WantedProfile()
  if name ~= self.activeProfile then
    self:ActivateProfile(name)
    print(("|cff4fe8ffCompact Druid Bar|r: profile \"%s\" active."):format(name))
  end
end

------------------------------------------------------------------------
-- Managing profiles
------------------------------------------------------------------------
function ns:ProfileNames()
  local list = {}
  for n in pairs(self.sv.profiles) do list[#list + 1] = n end
  table.sort(list, function(a, b)
    if a == DEFAULT_PROFILE then return true elseif b == DEFAULT_PROFILE then return false end
    return a:lower() < b:lower()
  end)
  return list
end

local function CleanName(name)
  name = name and strtrim(name) or ""
  if name == "" then return nil, "Enter a name first." end
  if #name > 40 then return nil, "Name is too long." end
  return name
end

-- This character's own profile (used when no automatic rule applies).
function ns:SetCharacterProfile(name)
  if not self.sv.profiles[name] then return end
  self.charData.profile = name
  self:ActivateProfile(self:WantedProfile())
end

function ns:SetRule(rule, name)
  self.charData.rules[rule] = (name and self.sv.profiles[name]) and name or nil
  self:ActivateProfile(self:WantedProfile())
end

-- New profile: fresh defaults, or a copy of the active one.
function ns:CreateProfile(name, copyCurrent)
  local n, err = CleanName(name)
  if not n then return false, err end
  if self.sv.profiles[n] then return false, "A profile with this name already exists." end
  self.sv.profiles[n] = copyCurrent and DeepCopy(self.db) or {}
  self:SetCharacterProfile(n)
  return true, ("Profile \"%s\" created and selected."):format(n)
end

function ns:RenameProfile(old, name)
  local n, err = CleanName(name)
  if not n then return false, err end
  if old == DEFAULT_PROFILE then return false, "The Default profile can't be renamed." end
  if self.sv.profiles[n] then return false, "A profile with this name already exists." end
  self.sv.profiles[n], self.sv.profiles[old] = self.sv.profiles[old], nil
  for _, c in pairs(self.sv.chars) do
    if c.profile == old then c.profile = n end
    for r, v in pairs(c.rules or {}) do if v == old then c.rules[r] = n end end
  end
  if self.activeProfile == old then self.activeProfile = n end
  return true, ("Renamed to \"%s\"."):format(n)
end

function ns:DeleteProfile(name)
  if name == DEFAULT_PROFILE then return false, "The Default profile can't be deleted." end
  if not self.sv.profiles[name] then return false, "Profile not found." end
  self.sv.profiles[name] = nil
  for _, c in pairs(self.sv.chars) do
    if c.profile == name then c.profile = DEFAULT_PROFILE end
    for r, v in pairs(c.rules or {}) do if v == name then c.rules[r] = nil end end
  end
  self:ActivateProfile(self:WantedProfile())
  return true, ("Profile \"%s\" deleted."):format(name)
end

-- Back to default settings for the active profile.
function ns:ResetProfile()
  local p = self.sv.profiles[self.activeProfile]
  wipe(p)
  self.db = ns.CopyDefaults(ns.DEFAULTS, p)
  self:Refresh()
  self:UpdateAlpha(true)
end

------------------------------------------------------------------------
-- Import / export
-- A small serializer of our own (strings, numbers, booleans and tables only);
-- imported text is parsed, never executed.
------------------------------------------------------------------------
local function Serialize(v, out)
  local t = type(v)
  if t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "number" then out[#out + 1] = "N" .. string.format("%.10g", v) .. ";"
  elseif t == "string" then out[#out + 1] = "S" .. #v .. ":" .. v
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, x in pairs(v) do
      local kt, xt = type(k), type(x)
      if (kt == "string" or kt == "number") and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
        Serialize(k, out)
        Serialize(x, out)
      end
    end
    out[#out + 1] = "}"
  end
  return out
end

local function Deserialize(s)
  local pos = 1
  local function read(depth)
    if depth > 12 then error("too deep") end
    local c = s:sub(pos, pos)
    pos = pos + 1
    if c == "T" then return true
    elseif c == "F" then return false
    elseif c == "N" then
      local e = s:find(";", pos, true)
      if not e then error("bad number") end
      local n = tonumber(s:sub(pos, e - 1))
      if not n then error("bad number") end
      pos = e + 1
      return n
    elseif c == "S" then
      local e = s:find(":", pos, true)
      if not e then error("bad string") end
      local len = tonumber(s:sub(pos, e - 1))
      if not len or len < 0 then error("bad string") end
      local str = s:sub(e + 1, e + len)
      if #str ~= len then error("bad string") end
      pos = e + 1 + len
      return str
    elseif c == "{" then
      local t = {}
      while true do
        if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
        if pos > #s then error("unfinished table") end
        local k = read(depth + 1)
        local v = read(depth + 1)
        if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
        t[k] = v
      end
    end
    error("unexpected data")
  end
  local ok, v = pcall(read, 1)
  if not ok or type(v) ~= "table" or pos <= #s then return nil end
  return v
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Encode64(data)
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:sub(i, i)] = i - 1 end
local function Decode64(s)
  s = s:gsub("[^%w%+/=]", "")
  if #s % 4 ~= 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local q = { s:byte(i, i + 3) }
    local v, pad = 0, 0
    for j = 1, 4 do
      local ch = string.char(q[j])
      local d = B64_INDEX[ch]
      if ch == "=" then d, pad = 0, pad + 1 elseif not d then return nil end
      v = v * 64 + d
    end
    local a, b, c = math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256
    out[#out + 1] = string.char(a)
    if pad < 2 then out[#out + 1] = string.char(b) end
    if pad < 1 then out[#out + 1] = string.char(c) end
  end
  return table.concat(out)
end

local PREFIX = "CDB1:"
function ns:ExportProfile()
  return PREFIX .. Encode64(table.concat(Serialize(self.db, {})))
end

function ns:ImportProfile(text, name)
  local n, err = CleanName(name)
  if not n then return false, err end
  if self.sv.profiles[n] then return false, "A profile with this name already exists." end
  text = text and strtrim(text) or ""
  if text:sub(1, #PREFIX) ~= PREFIX then return false, "This is not a Compact Druid Bar profile string." end
  local raw = Decode64(text:sub(#PREFIX + 1))
  local data = raw and Deserialize(raw)
  if not data then return false, "The profile string is damaged or incomplete." end
  self.sv.profiles[n] = data
  self:SetCharacterProfile(n)
  return true, ("Imported as \"%s\" and selected."):format(n)
end

------------------------------------------------------------------------
-- Automatic switching
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "CHARACTER_POINTS_CHANGED",
  "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function()
  -- Talent info can lag a moment behind the event.
  if C_Timer and C_Timer.After then C_Timer.After(0.5, function() ns:CheckProfileRules() end)
  else ns:CheckProfileRules() end
end)
