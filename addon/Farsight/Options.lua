-- Farsight: options window (/farsight) and minimap button.
local ADDON, NS = ...
local panel
local widgets = {}
local MAX_SCREENS = 6

local function label(parent, text, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	return fs
end

local function checkbox(parent, text, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb.label = label(cb, text)
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	cb.refresh = function() cb:SetChecked(get() and true or false) end
	widgets[#widgets + 1] = cb
	return cb
end

local function button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function numberBox(parent, width)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width or 56, 20)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(6)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	eb.Get = function(self) return tonumber(self:GetText()) end
	eb.Set = function(self, v) self:SetText(v and tostring(math.floor(v + 0.5)) or "") end
	return eb
end

local function refresh()
	for _, w in ipairs(widgets) do w.refresh() end
end

-- Copies the launcher's values so they can be edited by hand.
local function seedManual()
	local db = NS.db
	if db.manualScreens and db.manualWindow then return end
	local m = FarsightMonitors
	if type(m) == "table" and m.screens then
		db.manualWindow = { w = m.window.w, h = m.window.h }
		db.manualScreens = {}
		for _, s in ipairs(m.screens) do
			db.manualScreens[#db.manualScreens + 1] = { id = s.id, name = s.name, x = s.x, y = s.y, w = s.w, h = s.h }
		end
	else
		db.manualWindow = { w = 1920, h = 1080 }
		db.manualScreens = { { id = 1, name = "Screen 1", x = 0, y = 0, w = 1920, h = 1080 } }
	end
end

local function build()
	local db = NS.db
	local W, H = 620, 980
	local p = CreateFrame("Frame", "FarsightOptions", UIParent, "BasicFrameTemplateWithInset")
	p:SetSize(W, H)
	p:SetFrameStrata("DIALOG")
	p:SetMovable(true)
	p:EnableMouse(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)
	p:SetClampedToScreen(true)
	if p.TitleText then p.TitleText:SetText("Farsight") end
	tinsert(UISpecialFrames, "FarsightOptions")

	local y = -34
	local status = label(p, "", "GameFontNormal")
	status:SetPoint("TOPLEFT", 18, y); status:SetWidth(W - 36)
	widgets[#widgets + 1] = { refresh = function()
		local w, h = NS.WindowPixels()
		local n = #(NS.GetScreens())
		if NS.passive then
			status:SetText("|cffff5555Passive:|r MultiMonViewport is enabled. Disable it to use Farsight.")
		elseif not w then
			status:SetText("|cffffaa00No screen layout.|r Start WoW with the Farsight Launcher, or enter the screens by hand below.")
		elseif not NS.IsSpanned() then
			status:SetText(("|cffffaa00Paused:|r the WoW window is not stretched to %d x %d. Start WoW with the Farsight Launcher."):format(w, h))
		else
			status:SetText(("|cff40ff40Active:|r %d screens, WoW window %d x %d pixels%s."):format(n, w, h, db.manual and " (entered by hand)" or ""))
		end
	end }

	y = y - 40
	local bLayout = button(p, "Edit layout (windows and zones)", 250, function() p:Hide(); NS.ToggleLayout() end)
	bLayout:SetPoint("TOPLEFT", 18, y)
	local bReload = button(p, "Reload UI", 100, function() ReloadUI() end)
	bReload:SetPoint("LEFT", bLayout, "RIGHT", 8, 0)

	y = y - 34
	local cbOn = checkbox(p, "Farsight enabled", function() return db.enabled end, function(v) db.enabled = v; NS.ApplyAll() end)
	cbOn:SetPoint("TOPLEFT", 14, y)
	local cbView = checkbox(p, "Show the 3D world only on the game screen", function() return db.viewport end,
		function(v) db.viewport = v; NS.ApplyAll() end)
	cbView:SetPoint("TOPLEFT", 200, y)

	-- ----- game screen and game area
	y = y - 34
	local h1 = label(p, "Game area", "GameFontNormal"); h1:SetPoint("TOPLEFT", 18, y)
	y = y - 22
	local bGame
	bGame = button(p, "", 280, function()
		local list = NS.GetScreens()
		local cur, idx = NS.GameScreenId(), 1
		for i, s in ipairs(list) do if s.id == cur then idx = i end end
		db.gameScreen = list[idx % #list + 1].id
		db.gameRect = nil
		NS.ApplyAll(); refresh()
	end)
	bGame:SetPoint("TOPLEFT", 18, y)
	bGame.refresh = function()
		local s = NS.GetScreen(NS.GameScreenId())
		bGame:SetText("Game screen: " .. (s and (s.id .. " (" .. s.name .. ")") or "?"))
	end
	widgets[#widgets + 1] = bGame
	y = y - 28
	local gl = label(p, "Position and size in pixels (X, Y, width, height):"); gl:SetPoint("TOPLEFT", 18, y - 3)
	local gbox = {}
	for i = 1, 4 do
		gbox[i] = numberBox(p, 52)
		gbox[i]:SetPoint("TOPLEFT", 316 + (i - 1) * 60, y)
	end
	local function gameAuto()
		local s = NS.GetScreen(NS.GameScreenId())
		return s and s.px or { x = 0, y = 0, w = 0, h = 0 }
	end
	widgets[#widgets + 1] = { refresh = function()
		local g = db.gameRect or gameAuto()
		gbox[1]:Set(g.x); gbox[2]:Set(g.y); gbox[3]:Set(g.w); gbox[4]:Set(g.h)
	end }
	local function applyGame()
		local x, yy, w, h = gbox[1]:Get(), gbox[2]:Get(), gbox[3]:Get(), gbox[4]:Get()
		if x and yy and w and h and w >= 100 and h >= 100 then
			db.gameRect = { x = x, y = yy, w = w, h = h }
			NS.ApplyAll()
		else
			NS.Print("Enter four numbers. Width and height must be at least 100.")
		end
		refresh()
	end
	for i = 1, 4 do gbox[i]:SetScript("OnEnterPressed", function(self) self:ClearFocus(); applyGame() end) end
	y = y - 26
	local bGA = button(p, "Apply", 70, applyGame); bGA:SetPoint("TOPLEFT", 316, y)
	local bGAuto = button(p, "Auto (whole screen)", 150, function() db.gameRect = nil; NS.ApplyAll(); refresh() end)
	bGAuto:SetPoint("LEFT", bGA, "RIGHT", 6, 0)

	-- ----- UI scale and HUD
	y = y - 36
	local h2 = label(p, "User interface", "GameFontNormal"); h2:SetPoint("TOPLEFT", 18, y)
	y = y - 26
	local sl = label(p, "UI scale"); sl:SetPoint("TOPLEFT", 18, y)
	local slider = CreateFrame("Slider", nil, p, "UISliderTemplateWithLabels")
	slider:SetSize(220, 16)
	slider:SetPoint("TOPLEFT", 110, y + 1)
	slider:SetMinMaxValues(0.2, 1.2)
	slider:SetValueStep(0.01)
	slider:SetObeyStepOnDrag(true)
	if slider.Low then slider.Low:SetText("") end
	if slider.High then slider.High:SetText("") end
	if slider.Text then slider.Text:SetText("") end
	local sval = label(p, "", "GameFontNormal"); sval:SetPoint("LEFT", slider, "RIGHT", 10, 0)
	slider:SetScript("OnValueChanged", function(self, v)
		if self.refreshing then return end
		db.uiScale = math.floor(v * 100 + 0.5) / 100
		sval:SetText(("%.2f"):format(db.uiScale))
		NS.ApplyAll()
	end)
	slider.refresh = function()
		slider.refreshing = true
		local v = NS.TargetScale() or UIParent:GetScale()
		slider:SetValue(v)
		sval:SetText(db.uiScale and ("%.2f"):format(v) or ("auto (%.2f)"):format(v))
		slider.refreshing = false
	end
	widgets[#widgets + 1] = slider
	local bSAuto = button(p, "Auto", 60, function() db.uiScale = nil; NS.ApplyAll(); refresh() end)
	bSAuto:SetPoint("TOPLEFT", 440, y + 4)
	y = y - 30

	-- A grey explanation that wraps inside the window. Returns how much height it took.
	local function note(text, x, yy, font)
		local fs = label(p, text, font or "GameFontDisableSmall")
		fs:SetPoint("TOPLEFT", x, yy)
		fs:SetWidth(W - x - 22)
		fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
		fs:SetWordWrap(true)
		if fs.SetSpacing then fs:SetSpacing(2) end
		local h = fs:GetStringHeight() or 0
		if h < 8 then h = math.ceil(#text / 95) * 12 end   -- not measured yet: estimate from the length
		return h
	end

	-- ----- keep open
	y = y - 36
	local h3 = label(p, "Keep open (ESC and NPC windows do not close them)", "GameFontNormal"); h3:SetPoint("TOPLEFT", 18, y)
	y = y - 24
	local cbBags = checkbox(p, "Bags", function() return NS.IsPinned("bags") end, function(v) NS.SetPinned("bags", v) end)
	cbBags:SetPoint("TOPLEFT", 14, y)
	local cbMap = checkbox(p, "World map", function() return NS.IsPinned("map") end, function(v) NS.SetPinned("map", v) end)
	cbMap:SetPoint("TOPLEFT", 110, y)
	local kn = label(p, "Only the bags and the map can be kept open.", "GameFontDisableSmall")
	kn:SetPoint("TOPLEFT", 250, y - 6)
	y = y - 26
	y = y - note("How it works: closing the bags and the map on Escape is built into WoW and cannot be switched off. So Farsight runs a small script: it hides them itself just before the game handles the key, and opens them again right after. The game menu and other windows keep working as usual. It is the same script for WoW's own map and for OpenMap's map. Your own keys (B, M) and the X button still close them.", 42, y) - 6

	-- ----- bags: one combined bag or separate bags (this is WoW's own "combined bags" setting)
	local cbSep = checkbox(p, "Separate bags instead of one combined bag", function() return not NS.CombinedBags() end,
		function(v) NS.SetSeparateBags(v) end)
	cbSep:SetPoint("TOPLEFT", 14, y)
	y = y - 24
	y = y - note("WoW's combined bag is always 10 slots wide, so it stays small in a tall, narrow zone. Separate bags are 4 slots wide and are stacked to fill the zone. B then opens and closes all of them together.", 42, y) - 6

	-- ----- other addons: what Farsight found and how it works together with them
	local hA = label(p, "Other addons", "GameFontNormal"); hA:SetPoint("TOPLEFT", 18, y)
	y = y - 18
	local function has(name) return NS.IsLoaded(name) end
	local G, Y = "|cff40ff40", "|cffffd100"
	local found = {}
	if has("MoveAny") then
		found[#found + 1] = G .. "MoveAny found.|r Windows you put in a zone follow Farsight; MoveAny's saved place for them is set aside and comes back if you take the window out of its zone. Everything else stays MoveAny's. A newly zoned window may need one /reload."
	else
		found[#found + 1] = Y .. "MoveAny not installed|r - not needed. Farsight moves, sizes and keeps open every window you put in a zone."
	end
	if has("OpenMap") then
		found[#found + 1] = G .. "OpenMap found.|r The map can be stretched to fill its zone (zone menu: Size)."
	else
		found[#found + 1] = Y .. "OpenMap not installed|r - not needed. WoW's own map keeps its shape and is scaled to fit its zone."
	end
	if has("MultiMonViewport") then
		found[#found + 1] = "|cffff4040MultiMonViewport is enabled.|r It does the same job, so Farsight stays passive until you disable it."
	end
	if has("MoveAny") then
		found[#found + 1] = "Action bars and unit frames: if MoveAny moves one of them, turn that element off in MoveAny before you put it in a Farsight zone, or the two will pull it back and forth."
	end
	for _, text in ipairs(found) do
		y = y - note(text, 18, y, "GameFontHighlightSmall") - 4
	end
	y = y + 14

	-- ----- screens by hand
	y = y - 36
	local h4 = label(p, "Screens", "GameFontNormal"); h4:SetPoint("TOPLEFT", 18, y)
	y = y - 24
	local rows, winBox = {}, {}
	local cbManual = checkbox(p, "Enter the screens by hand (overrides the launcher)", function() return db.manual end,
		function(v)
			if v then seedManual() end
			db.manual = v
			NS.ApplyAll(); refresh()
		end)
	cbManual:SetPoint("TOPLEFT", 14, y)
	y = y - 28
	local wl = label(p, "WoW window, pixels (width, height):"); wl:SetPoint("TOPLEFT", 18, y - 3)
	winBox[1] = numberBox(p, 60); winBox[1]:SetPoint("TOPLEFT", 316, y)
	winBox[2] = numberBox(p, 60); winBox[2]:SetPoint("TOPLEFT", 384, y)
	y = y - 24
	local cl = label(p, "Screen                                         X            Y           width      height", "GameFontDisableSmall")
	cl:SetPoint("TOPLEFT", 18, y)
	y = y - 16
	local rowsTop = y
	for i = 1, MAX_SCREENS do
		local r = { boxes = {} }
		r.name = label(p, "")
		r.name:SetPoint("TOPLEFT", 18, rowsTop - (i - 1) * 24 - 3); r.name:SetWidth(170); r.name:SetWordWrap(false)
		for n = 1, 4 do
			r.boxes[n] = numberBox(p, 56)
			r.boxes[n]:SetPoint("TOPLEFT", 200 + (n - 1) * 66, rowsTop - (i - 1) * 24)
		end
		rows[i] = r
	end
	local function screensSource()
		if db.manual and db.manualScreens then return db.manualWindow, db.manualScreens end
		local m = FarsightMonitors
		if type(m) == "table" and m.screens then return m.window, m.screens end
		return nil, {}
	end
	widgets[#widgets + 1] = { refresh = function()
		local win, list = screensSource()
		winBox[1]:Set(win and win.w); winBox[2]:Set(win and win.h)
		winBox[1]:SetEnabled(db.manual); winBox[2]:SetEnabled(db.manual)
		for i = 1, MAX_SCREENS do
			local r, s = rows[i], list[i]
			r.name:SetShown(s ~= nil)
			for n = 1, 4 do r.boxes[n]:SetShown(s ~= nil); r.boxes[n]:SetEnabled(db.manual) end
			if s then
				r.name:SetText(s.id .. "  " .. (s.name or ""))
				r.boxes[1]:Set(s.x); r.boxes[2]:Set(s.y); r.boxes[3]:Set(s.w); r.boxes[4]:Set(s.h)
			end
		end
	end }
	local function applyScreens()
		if not db.manual then return end
		local w, h = winBox[1]:Get(), winBox[2]:Get()
		if not (w and h and w >= 100 and h >= 100) then NS.Print("Enter the window width and height.") return end
		db.manualWindow = { w = w, h = h }
		for i, s in ipairs(db.manualScreens) do
			local b = rows[i] and rows[i].boxes
			if b then
				local x, yy, sw, sh = b[1]:Get(), b[2]:Get(), b[3]:Get(), b[4]:Get()
				if x and yy and sw and sh and sw > 0 and sh > 0 then s.x, s.y, s.w, s.h = x, yy, sw, sh end
			end
		end
		NS.ApplyAll(); refresh()
	end
	local by = rowsTop - MAX_SCREENS * 24 - 6
	local bApply = button(p, "Apply", 70, applyScreens); bApply:SetPoint("TOPLEFT", 18, by)
	local bAdd = button(p, "Add screen", 100, function()
		if not db.manual or #db.manualScreens >= MAX_SCREENS then return end
		local id = 0
		for _, s in ipairs(db.manualScreens) do if s.id > id then id = s.id end end
		db.manualScreens[#db.manualScreens + 1] = { id = id + 1, name = "Screen " .. (id + 1), x = 0, y = 0, w = 1920, h = 1080 }
		refresh()
	end)
	bAdd:SetPoint("LEFT", bApply, "RIGHT", 6, 0)
	local bDel = button(p, "Remove last", 100, function()
		if not db.manual or #db.manualScreens <= 1 then return end
		table.remove(db.manualScreens)
		NS.ApplyAll(); refresh()
	end)
	bDel:SetPoint("LEFT", bAdd, "RIGHT", 6, 0)
	local bLaunch = button(p, "Use launcher values", 150, function()
		db.manual = false; db.manualScreens = nil; db.manualWindow = nil
		NS.ApplyAll(); refresh()
	end)
	bLaunch:SetPoint("LEFT", bDel, "RIGHT", 6, 0)

	-- ----- Farsight's own panels
	local cbTq = checkbox(p, "Transparent quest panel", function() return NS.PanelTransparent("FarsightQuestPanel") end,
		function(v) NS.SetPanelTransparent("FarsightQuestPanel", v) end)
	cbTq:SetPoint("BOTTOMLEFT", 14, 40)
	local cbTi = checkbox(p, "Transparent info panel", function() return NS.PanelTransparent("FarsightInfoPanel") end,
		function(v) NS.SetPanelTransparent("FarsightInfoPanel", v) end)
	cbTi:SetPoint("BOTTOMLEFT", 240, 40)

	-- ----- bottom row
	local cbMini = checkbox(p, "Minimap button", function() return not db.minimap.hide end,
		function(v) db.minimap.hide = not v; NS.UpdateMinimapButton() end)
	cbMini:SetPoint("BOTTOMLEFT", 14, 10)
	local cbDebug = checkbox(p, "Debug output in chat", function() return db.debug end, function(v) db.debug = v end)
	cbDebug:SetPoint("BOTTOMLEFT", 160, 10)
	local bReset = button(p, "Reset layout", 110, function()
		db.layout = {}; db.gameRect, db.gameScreen, db.uiScale, db.hud = nil, nil, nil, "all"
		NS.ApplyAll(); refresh()
	end)
	bReset:SetPoint("BOTTOMRIGHT", -16, 12)
	local bCal = button(p, "Auto-calibrate", 120, function() NS.Calibrate(); refresh() end)
	bCal:SetPoint("RIGHT", bReset, "LEFT", -6, 0)

	p:SetScript("OnShow", refresh)
	p:Hide()
	return p
end

function NS.ToggleOptions(forceShow)
	if not NS.db then return end
	if not panel then panel = build() end
	if panel:IsShown() and not forceShow then panel:Hide() return end
	-- open in the middle of the game screen
	local g = NS.GameRect()
	local _, rh = NS.RootSize()
	local s = panel:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	local ox, oy = (UIParent:GetLeft() or 0) * us, (UIParent:GetBottom() or 0) * us
	panel:ClearAllPoints()
	panel:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (g.x + g.w / 2 - ox) / s, (rh - (g.y + g.h / 2) - oy) / s)
	panel:Show()
	panel:Raise()
end

-- ---------------------------------------------------------------- minimap button
local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local btn

local function updatePosition()
	local a = math.rad(NS.db.minimap.angle or 215)
	local r = (Minimap:GetWidth() / 2) + 10
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function NS.UpdateMinimapButton()
	if not btn then return end
	if NS.db.minimap.hide then btn:Hide() else btn:Show() end
	updatePosition()
end

function NS.CreateMinimapButton()
	if btn or not Minimap then return end
	btn = CreateFrame("Button", "FarsightMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20); bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background"); bg:SetPoint("TOPLEFT", 7, -5)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17); icon:SetTexture(ICON); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); icon:SetPoint("TOPLEFT", 7, -6)
	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetPoint("TOPLEFT")
	btn:SetScript("OnClick", function(_, button)
		if button == "RightButton" then NS.ToggleOptions()
		elseif IsShiftKeyDown() then NS.NextProfile()
		else NS.ToggleLayout() end
	end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			NS.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
			updatePosition()
		end)
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Farsight")
		GameTooltip:AddLine("Left-click: edit layout", 1, 1, 1)
		GameTooltip:AddLine("Right-click: options", 1, 1, 1)
		GameTooltip:AddLine("Shift-click: next profile (" .. tostring(NS.db.profile) .. ")", 1, 1, 1)
		GameTooltip:AddLine("Drag: move button", 1, 1, 1)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	NS.UpdateMinimapButton()
end

function Farsight_OnAddonCompartmentClick()
	NS.ToggleOptions()
end


-- ================================================================ info panel
-- A small window of its own with session information, made to sit in a zone on a side screen.
-- Every line is computed inside pcall: if the game hides a value from addons, that line just shows "-".
local info
local session = { start = 0, xp = 0, lastXP = nil, lastMax = nil, money = nil, kills = 0 }

local function fmtTime(sec)
	sec = math.max(0, math.floor(sec))
	local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm"):format(m)
end

local function fmtMoney(c)
	local neg = c < 0
	c = math.abs(c)
	local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
	local t = ("|cffffd700%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r"):format(g, s, k)
	return (neg and "-" or "") .. t
end

-- Every line returns the main value and an optional smaller remark.
local LINES = {
	{ "Time", function()
		return date("%H:%M"), "played this session: " .. fmtTime(GetTime() - session.start)
	end },
	{ "Level", function()
		local xp, max = UnitXP("player"), UnitXPMax("player")
		local rest = GetXPExhaustion and GetXPExhaustion() or 0
		local extra = ("%.0f%% of the way to %d"):format(xp / max * 100, UnitLevel("player") + 1)
		if rest and rest > 0 then extra = extra .. (", |cff4d85e6rested %.0f%%|r"):format(rest / max * 100) end
		return tostring(UnitLevel("player")), extra
	end },
	{ "XP / hour", function()
		local el = GetTime() - session.start
		if el < 30 or session.xp <= 0 then return "-", "no XP gained yet" end
		local rate = session.xp / el * 3600
		local left = UnitXPMax("player") - UnitXP("player")
		return rate >= 1000 and ("%.1fk"):format(rate / 1000) or ("%d"):format(rate),
			"next level in about " .. fmtTime(left / rate * 3600)
	end },
	{ "Gold", function()
		local m = GetMoney()
		local extra
		if session.money then
			local d = m - session.money
			if d ~= 0 then extra = "session: " .. (d > 0 and "|cff40ff40+|r" or "") .. fmtMoney(d) end
		end
		return fmtMoney(m), extra
	end },
	{ "Bags", function()
		local free, total = 0, 0
		for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
			local slots = C_Container.GetContainerNumSlots(bag) or 0
			if slots > 0 then
				total = total + slots
				free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
			end
		end
		local col = (free <= 3) and "|cffff4040" or (free <= 8) and "|cffffd100" or "|cffffffff"
		return ("%s%d|r free"):format(col, free), ("of %d slots"):format(total)
	end },
	{ "Durability", function()
		local low
		for slot = 1, 18 do
			local cur, max = GetInventoryItemDurability(slot)
			if cur and max and max > 0 then
				local pct = cur / max * 100
				if not low or pct < low then low = pct end
			end
		end
		if not low then return "-" end
		local col = (low < 25) and "|cffff4040" or (low < 50) and "|cffffd100" or "|cffffffff"
		return ("%s%.0f%%|r"):format(col, low), "most worn item"
	end },
	{ "Kills", function() return tostring(session.kills), "this session" end },
	{ "FPS", function()
		local _, _, home, world = GetNetStats()
		return ("%.0f"):format(GetFramerate()), ("latency %d ms"):format(world or home or 0)
	end },
}

local function updateInfo()
	if not info or not info:IsShown() then return end
	for i, def in ipairs(LINES) do
		local ok, main, extra = pcall(def[2])
		local r = info.rows[i]
		r.main:SetText(ok and main or "-")
		r.extra:SetText(ok and extra or "")
	end
end

-- The text follows the size of the panel: in a wide panel every row is one line, in a tall narrow
-- panel every row is stacked (name, big value, remark) so the text can be as large as possible.
local function layoutInfo()
	if not info then return end
	local W, H = info:GetWidth(), info:GetHeight()
	if not W or not H or W < 10 or H < 10 then return end
	local vis = {}
	for i, def in ipairs(LINES) do
		local r = info.rows[i]
		local on = NS.db.infoRows[def[1]] ~= false
		r.name:SetShown(on); r.main:SetShown(on); r.extra:SetShown(on)
		if on then vis[#vis + 1] = r end
	end
	local n = math.max(1, #vis)
	local pad = math.max(6, math.min(W, H) * 0.04)
	local rowH = (H - 2 * pad) / n
	local font = STANDARD_TEXT_FONT
	local stacked = (W / rowH) < 9
	for i, r in ipairs(vis) do
		local y = -pad - (i - 1) * rowH
		r.name:ClearAllPoints(); r.main:ClearAllPoints(); r.extra:ClearAllPoints()
		if stacked then
			local fl = math.max(6, math.min(rowH * 0.19, (W - 2 * pad) / 7))
			local fm = math.max(8, math.min(rowH * 0.36, (W - 2 * pad) / 8))
			local fe = math.max(6, math.min(rowH * 0.17, (W - 2 * pad) / 13))
			r.name:SetFont(font, fl, ""); r.main:SetFont(font, fm, ""); r.extra:SetFont(font, fe, "")
			r.name:SetPoint("TOPLEFT", pad, y)
			r.main:SetPoint("TOPLEFT", pad, y - fl * 1.2)
			r.extra:SetPoint("TOPLEFT", pad, y - fl * 1.2 - fm * 1.12)
			r.extra:SetPoint("RIGHT", -pad, 0)
		else
			local f = math.max(7, math.min(rowH * 0.55, (W - 2 * pad) / 24))
			r.name:SetFont(font, f, ""); r.main:SetFont(font, f, ""); r.extra:SetFont(font, f * 0.8, "")
			local yy = y - (rowH - f) / 2
			r.name:SetPoint("TOPLEFT", pad, yy)
			r.main:SetPoint("TOPLEFT", pad + f * 6.4, yy)
			r.extra:SetPoint("BOTTOMLEFT", r.main, "BOTTOMRIGHT", f * 0.7, 0)
			r.extra:SetPoint("RIGHT", -pad, 0)
		end
	end
end

local function buildInfo()
	if info then return info end
	info = CreateFrame("Frame", "FarsightInfoPanel", UIParent)
	info:SetSize(420, 30 + #LINES * 26)
	info:SetPoint("CENTER")
	info:SetFrameStrata("MEDIUM")
	info:SetClampedToScreen(true)
	info:SetMovable(true)
	info:EnableMouse(true)
	info:RegisterForDrag("LeftButton")
	info:SetScript("OnDragStart", info.StartMoving)
	info:SetScript("OnDragStop", info.StopMovingOrSizing)
	info.bg = info:CreateTexture(nil, "BACKGROUND"); info.bg:SetColorTexture(0.04, 0.05, 0.08, 0.88); info.bg:SetAllPoints()
	info.top = info:CreateTexture(nil, "BORDER"); info.top:SetColorTexture(0.4, 0.6, 0.9, 1)
	info.top:SetPoint("TOPLEFT"); info.top:SetPoint("TOPRIGHT"); info.top:SetHeight(2)
	NS.UpdatePanelLook()
	local close = CreateFrame("Button", nil, info, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() NS.db.infoShown = false; info:Hide() end)
	info.rows = {}
	for i, def in ipairs(LINES) do
		local r = {}
		r.name = info:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		r.name:SetText(def[1]); r.name:SetTextColor(1, 0.82, 0)
		r.main = info:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.main:SetTextColor(1, 1, 1)
		r.extra = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		r.extra:SetTextColor(0.6, 0.6, 0.6); r.extra:SetJustifyH("LEFT"); r.extra:SetWordWrap(false)
		info.rows[i] = r
	end
	local elapsed = 0
	info:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 1 then return end
		elapsed = 0
		updateInfo()
	end)
	info:SetScript("OnShow", function() layoutInfo(); updateInfo() end)
	info:SetScript("OnSizeChanged", layoutInfo)
	layoutInfo()
	info:Hide()
	return info
end

function NS.InfoRowNames()
	local t = {}
	for _, def in ipairs(LINES) do t[#t + 1] = def[1] end
	return t
end

function NS.RefreshInfoPanel()
	if info then layoutInfo(); updateInfo() end
end

function NS.ShowInfoPanel(show)
	buildInfo()
	NS.db.infoShown = show and true or false
	info:SetShown(show and true or false)
	if show and NS.ApplyWindows then NS.ApplyWindows() end
end

function NS.ToggleInfoPanel()
	buildInfo()
	NS.ShowInfoPanel(not info:IsShown())
end

function NS.InitInfoPanel()
	session.start = GetTime()
	pcall(function()
		session.lastXP, session.lastMax = UnitXP("player"), UnitXPMax("player")
		session.money = GetMoney()
	end)
	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_XP_UPDATE")
	ev:RegisterEvent("PARTY_KILL")
	ev:SetScript("OnEvent", function(_, event, unit)
		if event == "PARTY_KILL" then
			session.kills = session.kills + 1
			return
		end
		if unit and unit ~= "player" then return end
		pcall(function()
			local xp, max = UnitXP("player"), UnitXPMax("player")
			if session.lastXP then
				local gained = xp - session.lastXP
				if gained < 0 then gained = (session.lastMax - session.lastXP) + xp end   -- level up
				if gained > 0 then session.xp = session.xp + gained end
			end
			session.lastXP, session.lastMax = xp, max
		end)
	end)
	-- show it again if it was open, or if it has a zone
	if NS.db.infoShown or (NS.FindZoneOf and NS.FindZoneOf("FarsightInfoPanel")) then
		C_Timer.After(1, function() NS.ShowInfoPanel(true) end)
	end
end


-- ---------------------------------------------------------------- quest panel
-- The quests in your quest log, laid out to use the whole zone: as many columns as give the largest text.
-- A quest is never split between two columns, and a zone header is never left alone at the bottom of one.
local quests
local qPending = false

local function hex(r, g, b) return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255) end

local function questBlocks()
	local blocks = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return blocks end
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local q = C_QuestLog.GetInfo(i)
		if q and not q.isHidden then
			if q.isHeader then
				blocks[#blocks + 1] = { header = true, title = "|cffffd100" .. (q.title or "") .. "|r" }
			elseif q.questID then
				local r, g, b = 1, 0.82, 0
				local ok, c = pcall(GetQuestDifficultyColor, q.level or 0)
				if ok and type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
				local name = ("[%d] %s"):format(q.level or 0, q.title or "?")
				local blk = { questID = q.questID,
					title = hex(r, g, b) .. name .. "|r",
					titleHover = hex(r + (1 - r) * 0.55, g + (1 - g) * 0.55, b + (1 - b) * 0.55) .. name .. "|r" }
				local lines, hover = {}, {}
				local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(q.questID)
				local failed = C_QuestLog.IsFailed and C_QuestLog.IsFailed(q.questID)
				if failed then
					lines[1] = "|cffff4040Failed|r"; hover[1] = "|cffff8080Failed|r"
				elseif done then
					lines[1] = "|cff40ff40Ready to turn in|r"; hover[1] = "|cff90ff90Ready to turn in|r"
				else
					local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.questID) or {}
					for _, o in ipairs(objs) do
						if o.text and o.text ~= "" then
							lines[#lines + 1] = (o.finished and "|cff808080- " or "|cffd0d0d0- ") .. o.text .. "|r"
							hover[#hover + 1] = (o.finished and "|cffb0b0b0- " or "|cffffffff- ") .. o.text .. "|r"
						end
					end
				end
				blk.objs, blk.objsHover = table.concat(lines, "\n"), table.concat(hover, "\n")
				blocks[#blocks + 1] = blk
			end
		end
	end
	return blocks
end

-- One quest = a title and, indented below it, its objectives (wrapped lines stay indented).
local function blockHeight(b, f, cw)
	b.fs:SetFont(STANDARD_TEXT_FONT, b.header and f * 1.1 or f, "")
	b.fs:SetWidth(cw)
	local h = b.fs:GetStringHeight() or f
	if b.ofs and b.objs ~= "" then
		b.ofs:SetFont(STANDARD_TEXT_FONT, f * 0.92, "")
		b.ofs:SetWidth(math.max(10, cw - f))
		h = h + (b.ofs:GetStringHeight() or 0) + f * 0.1
	end
	return h
end

-- Puts the blocks in columns with font size f. Returns true if everything fits.
local function placeQuests(blocks, f, n, W, H, pad, commit)
	local gap = f * 0.6
	local cw = (W - pad * (n + 1)) / n
	if cw < f * 6 then return false end
	local col, y = 1, 0
	for i, b in ipairs(blocks) do
		local h = blockHeight(b, f, cw)
		local need = h
		if b.header and blocks[i + 1] and not blocks[i + 1].header then   -- keep a header with its first quest
			need = h + gap * 0.4 + blockHeight(blocks[i + 1], f, cw)
			blockHeight(b, f, cw)
		end
		if y > 0 and y + need > H - 2 * pad then col, y = col + 1, 0 end
		if col > n or need > H - 2 * pad then return false end
		if commit then
			local x = pad + (col - 1) * (cw + pad)
			b.fs:ClearAllPoints()
			b.fs:SetPoint("TOPLEFT", quests, "TOPLEFT", x, -pad - y)
			b.fs:Show()
			if b.ofs and b.objs ~= "" then
				b.ofs:ClearAllPoints()
				b.ofs:SetPoint("TOPLEFT", b.fs, "BOTTOMLEFT", f, -f * 0.1)
				b.ofs:Show()
			end
			if b.btn then
				b.btn:ClearAllPoints()
				b.btn:SetPoint("TOPLEFT", quests, "TOPLEFT", x - pad * 0.4, -pad - y + gap * 0.25)
				b.btn:SetSize(cw + pad * 0.8, h + gap * 0.5)
				b.btn:Show()
			end
		end
		y = y + h + (b.header and gap * 0.4 or gap)
	end
	return true
end

local function questButton(i)
	local bt = quests.buttons[i]
	if bt then return bt end
	bt = CreateFrame("Button", nil, quests)
	bt:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bt.hl = bt:CreateTexture(nil, "BACKGROUND")
	bt.hl:SetAllPoints(); bt.hl:SetColorTexture(1, 1, 1, 0.07); bt.hl:Hide()
	bt:SetScript("OnEnter", function(self)
		local b = self.block
		if not b then return end
		self.hl:Show()
		b.fs:SetText(b.titleHover); b.ofs:SetText(b.objsHover)
	end)
	bt:SetScript("OnLeave", function(self)
		local b = self.block
		self.hl:Hide()
		if b then b.fs:SetText(b.title); b.ofs:SetText(b.objs) end
	end)
	bt:SetScript("OnClick", function(self)
		local id = self.block and self.block.questID
		if not id then return end
		if InCombatLockdown() then NS.Print("The quest log cannot be opened in combat.") return end
		if InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() then
			NS.Print("Opening the quest log from an addon is off in controller mode (it would break the controller bindings).")
			return
		end
		if QuestMapFrame_OpenToQuestDetails then
			pcall(QuestMapFrame_OpenToQuestDetails, id)
		end
	end)
	quests.buttons[i] = bt
	return bt
end

local function layoutQuests()
	qPending = false
	if not quests or not quests:IsShown() then return end
	local W, H = quests:GetWidth(), quests:GetHeight()
	if not W or not H or W < 20 or H < 20 then return end
	for _, fs in ipairs(quests.pool) do fs:Hide() end
	for _, bt in ipairs(quests.buttons) do bt:Hide(); bt.block = nil; bt.hl:Hide() end
	local blocks = questBlocks()
	if #blocks == 0 then
		quests.empty:SetFont(STANDARD_TEXT_FONT, math.max(10, math.min(24, H / 10)), "")
		quests.empty:Show()
		return
	end
	quests.empty:Hide()
	local used, nb = 0, 0
	local function fontString()
		used = used + 1
		local fs = quests.pool[used]
		if not fs then
			fs = quests:CreateFontString(nil, "OVERLAY")
			fs:SetFont(STANDARD_TEXT_FONT, 12, ""); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
			fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
			quests.pool[used] = fs
		end
		return fs
	end
	for _, b in ipairs(blocks) do
		b.fs = fontString(); b.fs:SetText(b.title)
		if not b.header then
			b.ofs = fontString(); b.ofs:SetText(b.objs)
			nb = nb + 1
			b.btn = questButton(nb); b.btn.block = b
		end
	end
	local pad = math.max(6, math.min(W, H) * 0.02)
	local best
	for f = 30, 8, -1 do
		for n = 1, 5 do
			if placeQuests(blocks, f, n, W, H, pad, false) then best = { f = f, n = n } break end
		end
		if best then break end
	end
	best = best or { f = 8, n = 5 }
	placeQuests(blocks, best.f, best.n, W, H, pad, true)
	quests.layout = best
end

local function questsSoon()
	if qPending then return end
	qPending = true
	C_Timer.After(0.3, layoutQuests)
end

local function buildQuests()
	if quests then return quests end
	quests = CreateFrame("Frame", "FarsightQuestPanel", UIParent)
	quests:SetSize(420, 520)
	quests:SetPoint("CENTER")
	quests:SetFrameStrata("MEDIUM")
	quests:SetClampedToScreen(true)
	quests:SetMovable(true)
	quests:EnableMouse(true)
	quests:RegisterForDrag("LeftButton")
	quests:SetScript("OnDragStart", quests.StartMoving)
	quests:SetScript("OnDragStop", quests.StopMovingOrSizing)
	quests.bg = quests:CreateTexture(nil, "BACKGROUND"); quests.bg:SetColorTexture(0.04, 0.05, 0.08, 0.88); quests.bg:SetAllPoints()
	quests.top = quests:CreateTexture(nil, "BORDER"); quests.top:SetColorTexture(0.4, 0.6, 0.9, 1)
	quests.top:SetPoint("TOPLEFT"); quests.top:SetPoint("TOPRIGHT"); quests.top:SetHeight(2)
	local close = CreateFrame("Button", nil, quests, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() NS.db.questsShown = false; quests:Hide() end)
	quests.pool, quests.buttons = {}, {}
	quests.empty = quests:CreateFontString(nil, "OVERLAY")
	quests.empty:SetFont(STANDARD_TEXT_FONT, 14, ""); quests.empty:SetPoint("CENTER")
	quests.empty:SetText("|cff888888No quests|r")
	quests:SetScript("OnShow", questsSoon)
	quests:SetScript("OnSizeChanged", questsSoon)
	local ev = CreateFrame("Frame", nil, quests)
	for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN", "QUEST_ACCEPTED" }) do
		pcall(ev.RegisterEvent, ev, e)
	end
	ev:SetScript("OnEvent", questsSoon)
	quests:Hide()
	NS.UpdatePanelLook()
	return quests
end

-- Transparent panels: no background and no top line, only the text (with a shadow so it stays readable).
-- NS.db.transparent[name] = true / false; the quest panel is transparent unless you turn it off.
function NS.PanelTransparent(name)
	local t = NS.db.transparent
	if type(t) ~= "table" then t = {}; NS.db.transparent = t end
	if t[name] == nil then return name == "FarsightQuestPanel" end
	return t[name]
end

function NS.SetPanelTransparent(name, on)
	if type(NS.db.transparent) ~= "table" then NS.db.transparent = {} end
	NS.db.transparent[name] = on and true or false
	NS.UpdatePanelLook()
end

function NS.UpdatePanelLook()
	for _, f in ipairs({ info or false, quests or false }) do
		if f and f.bg then
			local clear = NS.PanelTransparent(f:GetName())
			f.bg:SetShown(not clear); f.top:SetShown(not clear)
			f:EnableMouse(not clear)   -- a see-through panel lets clicks through to the game world (quests stay clickable)
		end
	end
end

function NS.ShowQuestPanel(show)
	buildQuests()
	NS.db.questsShown = show and true or false
	quests:SetShown(show and true or false)
	if show and NS.ApplyWindows then NS.ApplyWindows() end
end

function NS.ToggleQuestPanel()
	buildQuests()
	NS.ShowQuestPanel(not quests:IsShown())
end

function NS.InitQuestPanel()
	if NS.db.questsShown or (NS.FindZoneOf and NS.FindZoneOf("FarsightQuestPanel")) then
		C_Timer.After(1, function() NS.ShowQuestPanel(true) end)
	end
end
