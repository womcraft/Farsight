-- Farsight: "keep open". Pinned windows are not closed by ESC, the game menu, NPC windows or combat.
-- How ESC works in WoW Forever: the ESC key runs a queue that closes open windows and bags, and only
-- shows the game menu if nothing was closed. The menu itself also closes the bags. Touching Blizzard's
-- ESC code from an addon taints it, so instead:
--   1) an invisible keyboard frame sees ESC first and hides the pinned windows itself, so WoW behaves as
--      if they were not open (other windows close, otherwise the game menu opens), and
--   2) a watcher reopens the pinned windows as soon as WoW allows it.
-- A window stops being "wanted" only when you close it yourself (its key binding or its X button).
local ADDON, NS = ...

local function pinned(key) return NS.db and NS.db.enabled and not NS.passive and NS.db.pins[key] end
local unmanaged = {}    -- [key] = { frame, name, win, attrs, special }: windows taken out of the game's panel manager
local function menuShown() return GameMenuFrame and GameMenuFrame:IsShown() end

local AREAS = { "left", "center", "right", "doublewide", "fullscreen" }
-- Is a Blizzard panel open that is not one of ours? (reopening a pinned panel would push it away)
local function otherPanelOpen(ignore)
	if not GetUIPanel then return false end
	for _, a in ipairs(AREAS) do
		local fr = GetUIPanel(a)
		if fr and fr ~= ignore then return true end
	end
	return false
end

-- ================================================================ bags
local bags = { wanted = false, ids = {}, user = false, pending = false, internal = false, errShown = false }

local function anyBagShown()
	for _, cf in ipairs(NS.BagFrames()) do if cf:IsShown() then return true end end
	return false
end

local function bagFrameId(cf)
	if cf == ContainerFrameCombinedBags then return "combined" end
	if cf.GetBagID then return cf:GetBagID() end
	return cf:GetID()
end

local function openBagIds()
	local t = {}
	for _, cf in ipairs(NS.BagFrames()) do
		if cf:IsShown() then t[#t + 1] = bagFrameId(cf) end
	end
	return t
end

local function reopenBags(ids)
	for _, id in ipairs(ids) do
		if id == "combined" then
			if ContainerFrameCombinedBags and not ContainerFrameCombinedBags:IsShown() then
				if OpenAllBags then OpenAllBags() elseif OpenBackpack then OpenBackpack() end
			end
		elseif id == 0 then
			if OpenBackpack then OpenBackpack() end
		elseif OpenBag and type(id) == "number" and id > 0 then
			OpenBag(id)
		end
	end
end

local function canOpenBags()
	if menuShown() then return false end
	if ContainerFrame_AllowedToOpenBags then return ContainerFrame_AllowedToOpenBags() end
	return true
end

local function bagsEsc()
	if pinned("bags") and anyBagShown() and not menuShown() then
		bags.wanted = true
		bags.ids = openBagIds()
		NS.Debug("ESC: hiding bags for a moment")
		bags.internal = true
		for _, cf in ipairs(NS.BagFrames()) do if cf:IsShown() then cf:Hide() end end
		bags.internal = false
	end
end

local function onBagHidden()
	if not NS.db or bags.internal or bags.pending then return end
	bags.pending = true
	-- the hooks on B / X run after the bag has closed, so decide on the next frame
	C_Timer.After(0, function()
		bags.pending = false
		if bags.user then
			bags.wanted = anyBagShown()
			if not bags.wanted then NS.db.openBags = {} end
			NS.Debug("bags closed by you, keep open =", tostring(bags.wanted))
		else
			NS.Debug("bags closed by the game - reopening when possible")
		end
	end)
end

local function onBagShown()
	if not NS.db then return end
	bags.wanted = true
	C_Timer.After(0, function()
		local ids = openBagIds()
		if #ids > 0 then NS.db.openBags = ids; bags.ids = ids end
	end)
end

-- WoW's own setting: one combined bag window, or one window per bag.
function NS.CombinedBags()
	return GetCVarBool and GetCVarBool("combinedBags") and true or false
end

local function openOtherBags()
	if not OpenBag or NS.CombinedBags() then return end
	local n = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for i = 1, n do pcall(OpenBag, i) end
end

function NS.SetSeparateBags(separate)
	if InCombatLockdown() then NS.Print("Leave combat first.") return end
	local wasOpen = false
	for _, cf in ipairs(NS.BagFrames()) do if cf:IsShown() then wasOpen = true end end
	SetCVar("combinedBags", separate and "0" or "1")
	-- WoW rebuilds the bag windows; open them again in the new form and put them in their zone
	C_Timer.After(0.3, function()
		if wasOpen or (NS.db and NS.db.pins.bags) then
			if OpenAllBags then pcall(OpenAllBags) end
			openOtherBags()
		end
		if NS.HookPins then NS.HookPins() end
		if NS.ApplyWindows then NS.ApplyWindows() end
	end)
end

local bagHooked = {}
local bagFuncsHooked = false
local function hookBags()
	local function userAct() bags.user = true; C_Timer.After(0, function() bags.user = false end) end
	if not bagFuncsHooked then
		bagFuncsHooked = true
		for _, fn in ipairs({ "ToggleBackpack", "ToggleBag", "ToggleAllBags", "ToggleBags" }) do
			if _G[fn] then hooksecurefunc(fn, userAct) end
		end
		-- separate bags: B only opens the backpack in WoW (closing already closes all). Open the rest too.
		if ToggleBackpack then
			hooksecurefunc("ToggleBackpack", function()
				if not NS.db or not NS.db.enabled or NS.passive or NS.CombinedBags() then return end
				if IsBagOpen and IsBagOpen(0) then openOtherBags() end
			end)
		end
	end
	for _, cf in ipairs(NS.BagFrames()) do
		if not bagHooked[cf] then
			bagHooked[cf] = true
			cf:HookScript("OnHide", onBagHidden)
			cf:HookScript("OnShow", onBagShown)
			local close = cf.CloseButton or (cf:GetName() and _G[cf:GetName() .. "CloseButton"])
			if close then close:HookScript("OnClick", userAct) end
		end
	end
end

local function bagsWatch()
	if not (pinned("bags") and bags.wanted) or bags.pending then return end
	if anyBagShown() or not canOpenBags() then return end
	local ok, err = pcall(function()
		local ids = (#bags.ids > 0) and bags.ids or { "combined" }
		reopenBags(ids)
		if not anyBagShown() then
			if OpenAllBags then OpenAllBags() end
			if not anyBagShown() and OpenBackpack then OpenBackpack() end
		end
	end)
	if not ok and not bags.errShown then
		bags.errShown = true
		NS.Print("could not reopen the bags: " .. tostring(err))
	end
end

-- ================================================================ world map
-- The map is a protected Blizzard panel: addons may only show or hide it outside combat.
local mapState = { hooked = false, user = false, reopening = false, nextTry = 0 }

local function mapEsc()
	local map = WorldMapFrame
	if not (pinned("map") and map and map:IsShown()) or InCombatLockdown() then return end
	if unmanaged.map then return end   -- "always open": ESC does not see the map at all
	HideUIPanel(map)   -- before WoW handles ESC, so the game menu opens if nothing else was open
end

local function hookMap()
	local map = WorldMapFrame
	if mapState.hooked or not map then return end
	mapState.hooked = true
	local function userAct() mapState.user = true; C_Timer.After(0, function() mapState.user = false end) end
	if ToggleWorldMap then hooksecurefunc("ToggleWorldMap", userAct) end
	local close = (map.BorderFrame and map.BorderFrame.CloseButton) or _G.WorldMapFrameCloseButton
	if close then close:HookScript("OnClick", userAct) end
	map:HookScript("OnShow", function() if NS.db then NS.db.wanted.map = true end end)
	map:HookScript("OnHide", function()
		C_Timer.After(0, function()
			if not NS.db then return end
			if mapState.user and not mapState.reopening then
				NS.db.wanted.map = false
				NS.Debug("map closed by you")
			else
				NS.Debug("map closed by the game - reopening when possible")
			end
		end)
	end)
end

local function mapWatch()
	local map = WorldMapFrame
	if not map or not (pinned("map") and NS.db.wanted.map) or mapState.user then return end
	if map:IsShown() or InCombatLockdown() then return end
	if not unmanaged.map and (menuShown() or otherPanelOpen(map)) then return end
	if GetTime() < mapState.nextTry then return end
	mapState.nextTry = GetTime() + 2   -- if WoW refuses, try again in 2 s instead of every frame
	mapState.reopening = true
	if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(ShowUIPanel, map) end
	mapState.reopening = false
end

-- ================================================================ any other window
-- Opening or closing a Blizzard window from addon code can break it (the game then blocks parts of it),
-- so other windows are never hidden and reopened. Instead a pinned window is taken out of the game's
-- panel manager while it is closed: ESC and other panels then leave it alone, and its own key and X
-- button work as usual. Unpinning puts everything back.
local ATTRS = { "UIPanelLayout-defined", "UIPanelLayout-area", "UIPanelLayout-enabled" }
local showHooked = {}   -- [frame] = true

local function genericFrame(key)
	return NS.WindowFrames(key)[1]
end

local function specialIndex(name)
	for i, n in ipairs(UISpecialFrames) do if n == name then return i end end
end

-- Without the panel manager a window may have no position at all (invisible): give it one.
local function ensurePlaced(fr, key)
	if not unmanaged[key] or unmanaged[key].frame ~= fr then return end
	if fr:GetNumPoints() > 0 and fr:GetLeft() then return end
	if InCombatLockdown() and fr:IsProtected() then return end
	fr:ClearAllPoints()
	fr:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	if NS.FindZoneOf(key) or not NS.PlaceInRect or not NS.Active() then return end
	local game = NS.GameScreenId()
	for _, s in ipairs((NS.GetScreens())) do
		if s.id ~= game then NS.PlaceInRect(fr, s) return end
	end
end

local function unmanage(key)
	if unmanaged[key] then return true end
	local fr = genericFrame(key)
	local name = fr and fr:GetName()
	if not name or InCombatLockdown() or fr:IsShown() then return false end
	local st = { frame = fr, name = name, attrs = {} }
	st.win = UIPanelWindows and UIPanelWindows[name]
	for _, a in ipairs(ATTRS) do st.attrs[a] = fr:GetAttribute(a) end
	local i = specialIndex(name)
	if i then st.special = true; tremove(UISpecialFrames, i) end
	if UIPanelWindows then UIPanelWindows[name] = nil end
	for _, a in ipairs(ATTRS) do fr:SetAttribute(a, nil) end
	unmanaged[key] = st
	if not showHooked[fr] then
		showHooked[fr] = true
		fr:HookScript("OnShow", function(self) ensurePlaced(self, key) end)
	end
	NS.Debug(key, "is now kept open (ESC ignores it)")
	return true
end

local function remanage(key)
	local st = unmanaged[key]
	if not st then return true end
	local fr = st.frame
	if InCombatLockdown() or fr:IsShown() then return false end
	if UIPanelWindows and st.win then UIPanelWindows[st.name] = st.win end
	for _, a in ipairs(ATTRS) do fr:SetAttribute(a, st.attrs[a]) end
	if st.special and not specialIndex(st.name) then tinsert(UISpecialFrames, st.name) end
	unmanaged[key] = nil
	NS.Debug(key, "closes with ESC again")
	return true
end

-- "Map always open": the map is taken out of the panel manager like other pinned windows, so NPC windows,
-- vendors and the game menu no longer close it. Experimental: see the note in the options window.
local function mapAlwaysWatch()
	local want = pinned("map") and NS.db.mapAlways
	if want and not unmanaged.map then
		local map = WorldMapFrame
		if not map or InCombatLockdown() then return end
		if map:IsShown() then
			-- it can only be changed while closed: close it once, the watcher opens it again
			mapState.reopening = true
			pcall(HideUIPanel, map)
			mapState.reopening = false
			NS.db.wanted.map = true
			if map:IsShown() then return end
		end
		unmanage("map")
	elseif not want and unmanaged.map then
		local map = unmanaged.map.frame
		if InCombatLockdown() then return end
		if map:IsShown() then
			mapState.reopening = true
			pcall(map.Hide, map)
			mapState.reopening = false
			if map:IsShown() then return end
		end
		remanage("map")
	end
end

local function genericWatch()
	mapAlwaysWatch()
	for key in pairs(NS.db.pins) do
		if key ~= "bags" and key ~= "map" and pinned(key) then unmanage(key) end
	end
	for key in pairs(unmanaged) do
		if key ~= "map" and not pinned(key) then remanage(key) end
	end
end

-- ================================================================ wiring
function NS.HookPins()
	if not NS.db then return end
	hookBags()
	hookMap()
end

function NS.SetPinned(key, on)
	NS.db.pins[key] = on and true or false   -- false, not nil: otherwise the default (on) comes back at next login
	if key == "bags" then
		if on then NS.HookPins(); bags.wanted = anyBagShown() or bags.wanted end
		return
	elseif key == "map" then
		if on then
			NS.HookPins()
			if WorldMapFrame and WorldMapFrame:IsShown() then NS.db.wanted.map = true end
		end
		return
	end
	local fr = NS.WindowFrames(key)[1]
	if fr and fr:IsShown() then
		NS.Print("Close " .. NS.WindowLabel(key) .. " once. The change applies the next time you open it.")
	end
end

function NS.IsPinned(key) return NS.db.pins[key] and true or false end

local keyFrame, keyReady
local function initKeyFrame()
	if keyReady or InCombatLockdown() then return end
	keyFrame:SetPropagateKeyboardInput(true)   -- the key still reaches WoW
	keyFrame:EnableKeyboard(true)
	keyReady = true
end

function NS.InitPins()
	NS.HookPins()
	keyFrame = CreateFrame("Frame", "FarsightKeyFrame", UIParent)
	keyFrame:SetScript("OnKeyDown", function(_, key)
		if key ~= "ESCAPE" or not NS.db or not NS.db.enabled or NS.passive then return end
		bagsEsc()
		mapEsc()
	end)
	initKeyFrame()

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event, isLogin, isReload)
		initKeyFrame()
		if event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) then
			NS.HookPins()
			if pinned("bags") and NS.db.openBags and #NS.db.openBags > 0 then
				bags.ids = NS.db.openBags   -- reopen the bags that were open last time
				bags.wanted = true
			end
		end
	end)

	local elapsed = 0
	CreateFrame("Frame"):SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.2 then return end
		elapsed = 0
		if not NS.db or not NS.db.enabled or NS.passive then return end
		bagsWatch()
		mapWatch()
		genericWatch()
	end)
end
