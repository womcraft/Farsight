-- Farsight: layout mode. Shows every screen with its zones; click a zone tab to choose a window,
-- drag the lines between zones to resize them.
local ADDON, NS = ...

local overlay            -- root-level frame holding everything
local screenFrames, zoneFrames, dividers = {}, {}, {}
local list               -- shared popup list
local margins            -- margins popup
local topBar
local dragging           -- { node = cut, screen = id, f = rectangle of the cut }
local cutting            -- true while the "draw a cut" tool is on
local cutFrame, cutLine, cutBtn, cutStart
local profBtn, namePrompt, freeBtn
local floatHandles = {}  -- handles drawn over free windows
local floatDrag          -- { key, dx, dy }: a free window being dragged
local picking            -- { screen = id, zone = i }

local LETTERS = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P" }

-- Everything in the overlay is drawn at the normal UI scale so text has its usual size.
local function us() return UIParent:GetEffectiveScale() end
local function L(v) return v / us() end   -- root units -> overlay units

local function solid(parent, layer, r, g, b, a)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(r, g, b, a)
	return t
end

local function button(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetHeight(24)
	b.SetLabel = function(self, t)
		self:SetText(t)
		self:SetWidth(math.max(60, (self:GetTextWidth() or 40) + 26))
	end
	b:SetLabel(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- ---------------------------------------------------------------- popup list
local ROWS, ROW_H, LIST_W = 20, 22, 330

local function buildList()
	list = CreateFrame("Frame", "FarsightList", overlay)
	list:SetFrameStrata("TOOLTIP")
	list:SetSize(LIST_W, ROWS * ROW_H + 40)
	list:SetClampedToScreen(true)
	list:EnableMouse(true)
	list:EnableMouseWheel(true)
	local bg = solid(list, "BACKGROUND", 0.05, 0.06, 0.09, 0.97); bg:SetAllPoints()
	local edge = solid(list, "BORDER", 0.4, 0.6, 0.9, 1); edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
	list.title = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	list.title:SetPoint("TOPLEFT", 10, -10)
	local close = CreateFrame("Button", nil, list, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function() list:Hide() end)
	list.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(LIST_W - 12, ROW_H)
		row:SetPoint("TOPLEFT", 6, -32 - (i - 1) * ROW_H)
		row.hl = solid(row, "HIGHLIGHT", 0.3, 0.5, 0.9, 0.35); row.hl:SetAllPoints()
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", 6, 0); row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			local item = self.item
			if not item or not item.func then return end
			item.func()
			if item.keep then if list.rebuild then list.rebuild() end else list:Hide() end
		end)
		list.rows[i] = row
	end
	list.offset = 0
	list.Refresh = function()
		local items = list.items or {}
		local maxOff = math.max(0, #items - ROWS)
		if list.offset > maxOff then list.offset = maxOff end
		for i = 1, ROWS do
			local row, item = list.rows[i], items[i + list.offset]
			row.item = item
			if item then
				local txt = item.text
				if item.checked ~= nil then txt = (item.checked and "|cff40ff40[x]|r " or "[  ] ") .. txt end
				if item.header then txt = "|cffffd100" .. txt .. "|r" end
				row.text:SetText(txt)
				row:SetShown(true)
				row:EnableMouse(item.func ~= nil)
			else
				row:Hide()
			end
		end
		list:SetHeight(math.min(#items, ROWS) * ROW_H + 40)
	end
	list:SetScript("OnMouseWheel", function(_, delta)
		list.offset = math.max(0, list.offset - delta * 3)
		list.Refresh()
	end)
	list:Hide()
end

-- items = { { text, func, checked, keep, header }, ... }; rebuild = function returning fresh items (for toggles)
local function showList(anchor, title, makeItems)
	if not list then buildList() end
	if list:IsShown() and list.anchor == anchor then list:Hide() return end   -- same button again: close
	if margins then margins:Hide() end
	list.anchor = anchor
	list.rebuild = function()
		list.items = makeItems()
		list.Refresh()
	end
	list.title:SetText(title)
	list.offset = 0
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	list:Show()
	list.rebuild()
end

-- ---------------------------------------------------------------- mouse picker
local pickFrame, pickBox, pickText

local function isOurs(fr)
	local n = 0
	while fr and n < 40 do
		if fr == overlay or fr == NS.root then return true end
		fr = fr.GetParent and fr:GetParent()
		n = n + 1
	end
	return false
end

-- The window under the mouse: the highest named frame below UIParent.
local function frameUnderMouse()
	local foci = (GetMouseFoci and GetMouseFoci()) or (GetMouseFocus and { GetMouseFocus() }) or {}
	for _, fr in ipairs(foci) do
		if fr and fr ~= WorldFrame and fr ~= UIParent and not isOurs(fr) then
			local best, cur, n = nil, fr, 0
			while cur and cur ~= UIParent and cur ~= WorldFrame and n < 40 do
				local name = cur.GetName and cur:GetName()
				if name and _G[name] == cur then best = cur end
				cur = cur.GetParent and cur:GetParent()
				n = n + 1
			end
			if best then return best end
		end
	end
end

local function stopPicking()
	picking = nil
	if pickFrame then pickFrame:Hide() end
end

-- The key Farsight uses for a picked frame: map and bags have their own, the rest go by frame name.
local function keyForFrame(fr)
	local name = fr:GetName()
	if name == "WorldMapFrame" then return "map" end
	if name == "ContainerFrameCombinedBags" or name:match("^ContainerFrame%d+$") then return "bags" end
	if not NS.WindowEntry(name) then NS.db.custom[name] = name end
	return name
end

-- zoneIndex = nil: the picked window becomes a free window instead of going into a zone
local function startPicking(screenId, zoneIndex)
	picking = { screen = screenId, zone = zoneIndex, free = (zoneIndex == nil) }
	if list then list:Hide() end
	if not pickFrame then
		pickFrame = CreateFrame("Frame", nil, overlay)
		pickFrame:SetFrameStrata("TOOLTIP")
		pickFrame:SetSize(10, 10)
		pickBox = CreateFrame("Frame", nil, pickFrame)
		pickBox:SetFrameStrata("TOOLTIP")
		local t = solid(pickBox, "OVERLAY", 1, 0.85, 0, 0.25); t:SetAllPoints()
		pickText = pickFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		local tbg = solid(pickFrame, "BACKGROUND", 0, 0, 0, 0.85)
		tbg:SetPoint("TOPLEFT", pickText, -6, 6); tbg:SetPoint("BOTTOMRIGHT", pickText, 6, -6)
		pickFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
		pickFrame:SetScript("OnEvent", function(self, _, btn)
			if not picking then return end
			local target = self.target
			local p = picking
			stopPicking()
			if btn == "LeftButton" and target then
				local key = keyForFrame(target)
				if p.free then
					local es = target:GetEffectiveScale()
					local rw, rh = NS.RootSize()
					local l, t = target:GetLeft() or 0, target:GetTop() or 0
					NS.SetFloat(key, (l * es + target:GetWidth() * es / 2) / rw, (rh - t * es + target:GetHeight() * es / 2) / rh)
				else
					NS.AssignWindow(p.screen, p.zone, key)
				end
				NS.RefreshLayoutOverlay()
			end
		end)
		pickFrame:SetScript("OnUpdate", function(self)
			if not picking then return end
			local fr = frameUnderMouse()
			self.target = fr
			local cx, cy = GetCursorPosition()
			pickText:ClearAllPoints()
			pickText:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", L(cx) + 18, L(cy) + 18)
			if fr and fr:GetLeft() then
				pickText:SetText("Click to use: |cffffffff" .. fr:GetName() .. "|r\nRight-click to cancel")
				local es = fr:GetEffectiveScale()
				pickBox:ClearAllPoints()
				pickBox:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", L(fr:GetLeft() * es), L(fr:GetBottom() * es))
				pickBox:SetSize(L(fr:GetWidth() * es), L(fr:GetHeight() * es))
				pickBox:Show()
			else
				pickText:SetText("Point at an open window and click it\nRight-click to cancel")
				pickBox:Hide()
			end
		end)
	end
	pickFrame:Show()
end

-- ---------------------------------------------------------------- zone menu
local FITS = { fit = "scale to fit the zone", stretch = "stretch to fill the zone", none = "keep its own size" }
local FIT_ORDER = { "fit", "stretch", "none" }

local function zoneMenu(anchor, zone, label)
	showList(anchor, "Zone " .. label, function()
		local items = {}
		local cur = zone.data.win
		local here = {}
		for _, k in ipairs(NS.ZoneKeys(zone.data)) do here[k] = true end
		local bars = cur and NS.IsBar(cur)
		items[#items + 1] = { text = "Empty zone", checked = (cur == nil), func = function()
			NS.AssignWindow(zone.screen, zone.index, nil); NS.RefreshLayoutOverlay() end }
		if cur then
			items[#items + 1] = { text = "Settings for " .. NS.WindowLabel(cur), header = true }
			if cur == "bags" or cur == "map" then
				items[#items + 1] = { text = "Keep open (ESC does not close it)", checked = NS.IsPinned(cur), keep = true,
					func = function() NS.SetPinned(cur, not NS.IsPinned(cur)) end }
			end
			if cur ~= "bags" then
				local fit = NS.FitFor(cur, zone.data)
				items[#items + 1] = { text = "Size: " .. FITS[fit] .. "  (click to change)", keep = true, func = function()
					local idx = 1
					for i, f in ipairs(FIT_ORDER) do if f == fit then idx = i end end
					zone.data.fit = FIT_ORDER[idx % #FIT_ORDER + 1]
					NS.ApplyWindows()
				end }
			else
				items[#items + 1] = { text = "|cff888888Size: scale to fit the zone (always, for bags)|r", keep = true, func = function() end }
				items[#items + 1] = { text = "Separate bags, stacked (better in a tall zone)", checked = not NS.CombinedBags(), keep = true,
					func = function() NS.SetSeparateBags(NS.CombinedBags()) end }
			end
		end
		if bars then
			local DIRS = { "auto", "h", "v" }
			local NAMES = { auto = "auto (whichever makes the bars biggest)", h = "horizontal", v = "vertical" }
			local d = zone.data.barDir
			local now = d and NAMES[d] or "as set in Edit Mode"
			if d == "auto" then now = now .. ", now " .. (NS.ZoneBarDirection(zone) == "h" and "horizontal" or "vertical") end
			items[#items + 1] = { text = "Bar direction: " .. now .. "  (click to change)", keep = true, func = function()
				local i = 0
				for n, v in ipairs(DIRS) do if v == zone.data.barDir then i = n end end
				zone.data.barDir = DIRS[i + 1]   -- after "v" comes nil: as set in Edit Mode
				NS.ApplyWindows()
			end }
		end
		if (cur == "FarsightInfoPanel" or cur == "FarsightQuestPanel") and NS.PanelTransparent then
			items[#items + 1] = { text = "Transparent background", checked = NS.PanelTransparent(cur), keep = true, func = function()
				NS.SetPanelTransparent(cur, not NS.PanelTransparent(cur)) end }
		end
		if cur == "FarsightInfoPanel" and NS.InfoRowNames then
			items[#items + 1] = { text = "Rows in the info panel", header = true }
			for _, row in ipairs(NS.InfoRowNames()) do
				items[#items + 1] = { text = row, checked = NS.db.infoRows[row] ~= false, keep = true, func = function()
					NS.db.infoRows[row] = (NS.db.infoRows[row] == false) and true or false
					if NS.RefreshInfoPanel then NS.RefreshInfoPanel() end
				end }
			end
		end
		items[#items + 1] = { text = "Change this zone", header = true }
		items[#items + 1] = { text = "Split in two: left | right", func = function()
			NS.SplitZone(zone.data, "v", 0.5); NS.ApplyWindows(); NS.RefreshLayoutOverlay() end }
		items[#items + 1] = { text = "Split in two: top | bottom", func = function()
			NS.SplitZone(zone.data, "h", 0.5); NS.ApplyWindows(); NS.RefreshLayoutOverlay() end }
		items[#items + 1] = { text = "Remove this zone (its neighbour grows)", func = function()
			NS.RemoveZone(zone.screen, zone.data); NS.ApplyWindows(); NS.RefreshLayoutOverlay() end }
		items[#items + 1] = { text = "Put a window here", header = true }
		items[#items + 1] = { text = "|cff66ccffPick any window with the mouse...|r", func = function()
			startPicking(zone.screen, zone.index) end }
		for _, e in ipairs(NS.WindowList()) do
		if e.header then
			items[#items + 1] = { text = e.header, header = true }
		else
			local exists = e.special == "bags" or e.special == "own" or #NS.WindowFrames(e.key) > 0
			local other = NS.FindZoneOf(e.key)
			local txt = e.label
			if other and not (other.screen == zone.screen and other.index == zone.index) then
				txt = txt .. " |cff888888(moves from another zone)|r"
			elseif not exists then
				txt = txt .. " |cff888888(not opened yet this session)|r"
			end
			local key = e.key
			local addonLabel = e.addonFrame and e.label
			if NS.BarIsHorizontal then
				local hz = NS.BarIsHorizontal(key)
				if hz ~= nil then txt = txt .. " |cff888888(" .. (hz and "horizontal" or "vertical") .. ")|r" end
			end
			if bars and NS.IsBar(key) and not here[key] then txt = txt .. " |cff66ff66(adds to this zone)|r" end
			-- a ticked window leaves the zone when clicked again; bars can share a zone
			items[#items + 1] = { text = txt, checked = here[key] or false, keep = true, func = function()
				if addonLabel and not NS.db.custom[key] then NS.db.custom[key] = addonLabel end
				NS.ToggleWindow(zone.screen, zone.index, key); NS.RefreshLayoutOverlay() end }
		end
		end
		return items
	end)
end

-- ---------------------------------------------------------------- margins popup
local function showMargins(anchor, screenId)
	if margins and margins:IsShown() and margins.anchor == anchor then margins:Hide() return end   -- same button again: close
	if list then list:Hide() end
	if not margins then
		margins = CreateFrame("Frame", "FarsightMargins", overlay)
		margins:SetFrameStrata("TOOLTIP")
		margins:SetSize(300, 150)
		margins:EnableMouse(true)
		local bg = solid(margins, "BACKGROUND", 0.05, 0.06, 0.09, 0.97); bg:SetAllPoints()
		local t = margins:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		t:SetPoint("TOPLEFT", 10, -10); t:SetWidth(280); t:SetJustifyH("LEFT")
		t:SetText("Space to keep free at the screen edges, in pixels (for action bars, chat and so on).")
		margins.boxes = {}
		for i, name in ipairs({ "Left", "Top", "Right", "Bottom" }) do
			local lab = margins:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			lab:SetPoint("TOPLEFT", 14 + (i - 1) * 70, -58); lab:SetText(name)
			local eb = CreateFrame("EditBox", nil, margins, "InputBoxTemplate")
			eb:SetSize(52, 20); eb:SetPoint("TOPLEFT", 16 + (i - 1) * 70, -74)
			eb:SetAutoFocus(false); eb:SetNumeric(true); eb:SetMaxLetters(5)
			eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); margins.Apply() end)
			eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
			margins.boxes[i] = eb
		end
		margins.Apply = function()
			local l = NS.ScreenLayout(margins.screen)
			for i = 1, 4 do l.inset[i] = tonumber(margins.boxes[i]:GetText()) or 0 end
			NS.ApplyWindows(); NS.RefreshLayoutOverlay()
		end
		local ok = button(margins, "Apply", function() margins.Apply() end); ok:SetPoint("BOTTOMLEFT", 12, 12)
		local cl = button(margins, "Close", function() margins:Hide() end); cl:SetPoint("LEFT", ok, "RIGHT", 6, 0)
	end
	margins.screen = screenId
	margins.anchor = anchor
	local l = NS.ScreenLayout(screenId)
	for i = 1, 4 do margins.boxes[i]:SetText(tostring(l.inset[i] or 0)) end
	margins:ClearAllPoints()
	margins:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	margins:Show()
end

-- ---------------------------------------------------------------- profiles
-- A small box to type or copy text. opts = { title, text, button, select, max }
local function askText(anchor, opts, onOk)
	if not namePrompt then
		namePrompt = CreateFrame("Frame", "FarsightNamePrompt", overlay)
		namePrompt:SetFrameStrata("TOOLTIP")
		namePrompt:SetSize(460, 96)
		namePrompt:EnableMouse(true)
		local bg = solid(namePrompt, "BACKGROUND", 0.05, 0.06, 0.09, 0.97); bg:SetAllPoints()
		namePrompt.title = namePrompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		namePrompt.title:SetPoint("TOPLEFT", 10, -10)
		local eb = CreateFrame("EditBox", nil, namePrompt, "InputBoxTemplate")
		eb:SetSize(430, 20); eb:SetPoint("TOPLEFT", 16, -34)
		eb:SetAutoFocus(false)
		namePrompt.eb = eb
		local function accept()
			local txt = eb:GetText()
			eb:ClearFocus()
			namePrompt:Hide()
			if namePrompt.onOk then namePrompt.onOk(txt) end
		end
		eb:SetScript("OnEnterPressed", accept)
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); namePrompt:Hide() end)
		namePrompt.ok = button(namePrompt, "OK", accept); namePrompt.ok:SetPoint("BOTTOMLEFT", 12, 10)
		local cl = button(namePrompt, "Cancel", function() eb:ClearFocus(); namePrompt:Hide() end)
		cl:SetPoint("LEFT", namePrompt.ok, "RIGHT", 6, 0)
	end
	namePrompt.onOk = onOk
	namePrompt.title:SetText(opts.title or "")
	namePrompt.ok:SetLabel(opts.button or "OK")
	namePrompt.eb:SetMaxLetters(opts.max or 0)
	namePrompt.eb:SetText(opts.text or "")
	namePrompt:ClearAllPoints()
	namePrompt:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	namePrompt:Show()
	namePrompt.eb:SetFocus()
	if opts.select then namePrompt.eb:HighlightText() end
end

local function askName(anchor, onOk)
	askText(anchor, { title = "Name of the new profile", button = "Create", max = 24 }, onOk)
end

local CONTEXTS = { { "rest", "In cities and inns" }, { "instance", "In dungeons, raids, battlegrounds" }, { "world", "Everywhere else" } }

local function profileMenu(anchor)
	showList(anchor, "Layout profiles", function()
		local db = NS.db
		local items = {}
		items[#items + 1] = { text = "Switch profile", header = true }
		for _, name in ipairs(NS.ProfileNames()) do
			items[#items + 1] = { text = name, checked = (name == db.profile), func = function() NS.SwitchProfile(name) end }
		end
		items[#items + 1] = { text = "|cff66ccffNew profile (starts as a copy of this one)...|r", func = function()
			askName(anchor, function(txt) NS.NewProfile(txt) end) end }
		if #NS.ProfileNames() > 1 then
			items[#items + 1] = { text = "|cffff7070Delete profile \"" .. db.profile .. "\"|r", func = function() NS.DeleteProfile(db.profile) end }
		end
		items[#items + 1] = { text = "Share", header = true }
		items[#items + 1] = { text = "Export this profile as text (to share it)...", func = function()
			askText(anchor, { title = "Press Ctrl+C to copy, then paste it where you want to share it", text = NS.ExportProfile(), button = "Close", select = true }, nil)
		end }
		items[#items + 1] = { text = "Import a profile from text...", func = function()
			askText(anchor, { title = "Paste a Farsight layout here (Ctrl+V), then press Import", button = "Import" }, function(txt)
				local ok, res = NS.ImportProfile(txt)
				if ok then NS.Print("Imported as profile: " .. res) else NS.Print("Import failed: " .. tostring(res)) end
			end)
		end }
		items[#items + 1] = { text = "Switch automatically (click to change)", header = true }
		for _, c in ipairs(CONTEXTS) do
			local ctx, label = c[1], c[2]
			local cur = db.autoProfile[ctx] and NS.FindProfile(db.autoProfile[ctx])
			items[#items + 1] = { text = label .. ":  |cffffffff" .. (cur or "do not switch") .. "|r", keep = true, func = function()
				-- cycle: do not switch -> first profile -> next ... -> do not switch
				local names = NS.ProfileNames()
				local idx = 0
				for i, n in ipairs(names) do if n == cur then idx = i end end
				db.autoProfile[ctx] = names[idx + 1]
			end }
		end
		items[#items + 1] = { text = "|cff888888A profile holds zones, their windows, margins and Keep open.|r" }
		return items
	end)
end

-- ---------------------------------------------------------------- free windows
local function freeMenu(anchor)
	showList(anchor, "Free windows (not in a zone)", function()
		local items = {}
		items[#items + 1] = { text = "|cff66ccffPick a window with the mouse...|r", func = function() startPicking(nil, nil) end }
		items[#items + 1] = { text = "|cff888888Then drag its green handle. Mouse wheel = size. Right-click = release.|r" }
		local float = NS.FloatTable()
		local any = false
		for key in pairs(float) do
			if not any then any = true; items[#items + 1] = { text = "Release a free window", header = true } end
			items[#items + 1] = { text = NS.WindowLabel(key), func = function() NS.ClearFloat(key); NS.RefreshLayoutOverlay() end }
		end
		items[#items + 1] = { text = "Add from the list", header = true }
		for _, e in ipairs(NS.WindowList()) do
			if e.header then
				items[#items + 1] = { text = e.header, header = true }
			elseif e.special ~= "bags" and not float[e.key] then
				local key = e.key
				items[#items + 1] = { text = e.label, func = function()
					local fr = NS.WindowFrames(key)[1]
					local cx, cy = 0.5, 0.75
					if fr and fr:GetLeft() then
						local es = fr:GetEffectiveScale()
						local rw, rh = NS.RootSize()
						cx = (fr:GetLeft() * es + fr:GetWidth() * es / 2) / rw
						cy = (rh - fr:GetTop() * es + fr:GetHeight() * es / 2) / rh
					end
					NS.SetFloat(key, cx, cy)
					NS.RefreshLayoutOverlay()
				end }
			end
		end
		return items
	end)
end

local function getFloatHandle(i)
	local h = floatHandles[i]
	if h then return h end
	h = CreateFrame("Button", nil, overlay)
	h:SetFrameStrata("FULLSCREEN_DIALOG")
	h:SetFrameLevel(45)
	h.tex = solid(h, "BACKGROUND", 0.2, 0.9, 0.3, 0.28); h.tex:SetAllPoints()
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("CENTER")
	h:RegisterForClicks("RightButtonUp")
	h:EnableMouseWheel(true)
	h:SetScript("OnMouseDown", function(self, btn)
		if btn ~= "LeftButton" then return end
		local d = NS.FloatTable()[self.key]
		if not d then return end
		local rw, rh = NS.RootSize()
		local cx, cy = GetCursorPosition()
		floatDrag = { key = self.key, dx = cx / rw - d.cx, dy = (rh - cy) / rh - d.cy }
	end)
	h:SetScript("OnMouseUp", function() floatDrag = nil; NS.ApplyWindows(); NS.RefreshLayoutOverlay() end)
	h:SetScript("OnClick", function(self, btn)
		if btn == "RightButton" then NS.ClearFloat(self.key); NS.RefreshLayoutOverlay() end
	end)
	h:SetScript("OnMouseWheel", function(self, delta)
		local d = NS.FloatTable()[self.key]
		if not d then return end
		local fr = NS.WindowFrames(self.key)[1]
		local cur = d.scale or (fr and fr:GetScale()) or 1
		NS.SetFloat(self.key, d.cx, d.cy, cur * (delta > 0 and 1.06 or 1 / 1.06))
		NS.RefreshLayoutOverlay()
	end)
	floatHandles[i] = h
	return h
end

local function refreshFloats()
	local rw, rh = NS.RootSize()
	local n = 0
	for key, d in pairs(NS.FloatTable()) do
		n = n + 1
		local h = getFloatHandle(n)
		h.key = key
		local fr = NS.WindowFrames(key)[1]
		local rect
		if fr and fr:IsShown() and fr:GetLeft() then
			local es = fr:GetEffectiveScale()
			rect = { x = fr:GetLeft() * es, y = rh - fr:GetTop() * es, w = fr:GetWidth() * es, h = fr:GetHeight() * es }
		else
			rect = { x = d.cx * rw - 45, y = d.cy * rh - 14, w = 90, h = 28 }
		end
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(rect.x), -L(rect.y))
		h:SetSize(math.max(60, L(rect.w)), math.max(24, L(rect.h)))
		h.text:SetText("Free: " .. NS.WindowLabel(key) .. ((fr and fr:IsShown()) and "" or "\n(closed)"))
		h:Show()
	end
	for i = n + 1, #floatHandles do floatHandles[i]:Hide() end
end

-- ---------------------------------------------------------------- screens, zones, dividers
local function place(frame, rect)   -- rect in root units, y from the top
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(rect.x), -L(rect.y))
	frame:SetSize(math.max(1, L(rect.w)), math.max(1, L(rect.h)))
end

local function getScreenFrame(i)
	local f = screenFrames[i]
	if f then return f end
	f = CreateFrame("Frame", nil, overlay)
	f:SetFrameStrata("BACKGROUND")
	f.tint = solid(f, "BACKGROUND", 0, 0, 0, 0.2); f.tint:SetAllPoints()
	f.num = f:CreateFontString(nil, "ARTWORK")
	f.num:SetFont(STANDARD_TEXT_FONT, 200, "OUTLINE")
	f.num:SetPoint("CENTER", 0, 30)
	f.num:SetAlpha(0.35)
	f.name = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	f.name:SetPoint("TOP", f.num, "BOTTOM", 0, -6)
	f.name:SetAlpha(0.7)
	-- toolbar lives in its own high-strata frame so windows never cover it
	f.bar = CreateFrame("Frame", nil, overlay)
	f.bar:SetFrameStrata("FULLSCREEN_DIALOG")
	f.bar:SetSize(10, 30)
	local bbg = solid(f.bar, "BACKGROUND", 0, 0, 0, 0.75); bbg:SetAllPoints()
	f.bar.title = f.bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.bar.title:SetPoint("LEFT", 8, 0)
	f.gameBtn = button(f.bar, "Game screen", function()
		NS.db.gameScreen = f.screenId
		NS.db.gameRect = nil
		NS.ApplyAll()
	end)
	f.splitBtn = button(f.bar, "Zones", function(self)
		local id = f.screenId
		showList(self, "Zones on screen " .. id, function()
			local items = {}
			local l = NS.ScreenLayout(id)
			items[#items + 1] = { text = "Start from a ready-made split", header = true }
			for _, s in ipairs(NS.SPLITS) do
				local key = s.key
				items[#items + 1] = { text = s.label, func = function()
					-- keep the windows that are already placed, in order
					local old = {}
					for _, part in ipairs((NS.TreeParts(l))) do old[#old + 1] = part.node end
					l.tree = NS.PresetTree(key, 0.5, 0.5, old)
					NS.ApplyWindows(); NS.RefreshLayoutOverlay()
				end }
			end
			items[#items + 1] = { text = "|cff888888Cut zones further with \"Draw a cut\" at the top,|r" }
			items[#items + 1] = { text = "|cff888888or click a zone tab and choose Split.|r" }
			return items
		end)
	end)
	f.marginBtn = button(f.bar, "Margins", function(self) showMargins(self, f.screenId) end)
	f.gameBtn:SetPoint("LEFT", f.bar.title, "RIGHT", 10, 0)
	f.splitBtn:SetPoint("LEFT", f.gameBtn, "RIGHT", 4, 0)
	f.marginBtn:SetPoint("LEFT", f.splitBtn, "RIGHT", 4, 0)
	screenFrames[i] = f
	return f
end

local function getZoneFrame(i)
	local z = zoneFrames[i]
	if z then return z end
	z = CreateFrame("Frame", nil, overlay)
	z:SetFrameStrata("FULLSCREEN_DIALOG")
	local T = 3
	z.edges = {}
	for n = 1, 4 do z.edges[n] = solid(z, "OVERLAY", 1, 1, 1, 0.85) end
	z.edges[1]:SetPoint("TOPLEFT"); z.edges[1]:SetPoint("TOPRIGHT"); z.edges[1]:SetHeight(T)
	z.edges[2]:SetPoint("BOTTOMLEFT"); z.edges[2]:SetPoint("BOTTOMRIGHT"); z.edges[2]:SetHeight(T)
	z.edges[3]:SetPoint("TOPLEFT"); z.edges[3]:SetPoint("BOTTOMLEFT"); z.edges[3]:SetWidth(T)
	z.edges[4]:SetPoint("TOPRIGHT"); z.edges[4]:SetPoint("BOTTOMRIGHT"); z.edges[4]:SetWidth(T)
	z.tab = button(z, "", function(self) zoneMenu(self, z.zone, z.label) end)
	z.tab:SetPoint("TOPLEFT", 6, -6)
	zoneFrames[i] = z
	return z
end

local function getDivider(i)
	local d = dividers[i]
	if d then return d end
	d = CreateFrame("Button", nil, overlay)
	d:SetFrameStrata("FULLSCREEN_DIALOG")
	d:SetFrameLevel(50)
	d.tex = solid(d, "OVERLAY", 1, 0.82, 0, 0.9); d.tex:SetAllPoints()
	d:SetScript("OnEnter", function(self) self.tex:SetColorTexture(1, 1, 1, 1) end)
	d:SetScript("OnLeave", function(self) self.tex:SetColorTexture(1, 0.82, 0, 0.9) end)
	d:SetScript("OnMouseDown", function(self) dragging = { node = self.node, screen = self.screenId, f = self.f } end)
	d:SetScript("OnMouseUp", function()
		dragging = nil
		NS.ApplyWindows(); NS.RefreshLayoutOverlay()
	end)
	dividers[i] = d
	return d
end

local function snap(v)
	for _, s in ipairs({ 0.25, 1 / 3, 0.5, 2 / 3, 0.75 }) do
		if math.abs(v - s) < 0.015 then return s end
	end
	return v
end

function NS.RefreshLayoutOverlay()
	if not overlay or not overlay:IsShown() then return end
	overlay:SetScale(us())
	local screens = NS.GetScreens()
	local gameId = NS.GameScreenId()
	local zi, di = 0, 0
	for i, s in ipairs(screens) do
		local f = getScreenFrame(i)
		f.screenId = s.id
		place(f, s)
		local game = (s.id == gameId)
		if game then f.tint:SetColorTexture(0.1, 0.6, 0.25, 0.16) else f.tint:SetColorTexture(0.1, 0.35, 0.85, 0.22) end
		f.num:SetText(tostring(s.id))
		f.name:SetText(s.name .. ((s.px and s.px.w > 0) and ("   " .. s.px.w .. " x " .. s.px.h) or "")
			.. (game and "\nGAME SCREEN" or ""))
		f.bar.title:SetText("Screen " .. s.id)
		f.gameBtn:SetLabel(game and "Game screen (this one)" or "Make this the game screen")
		f.gameBtn:SetEnabled(not game)
		f.bar:SetWidth(f.bar.title:GetStringWidth() + f.gameBtn:GetWidth() + f.splitBtn:GetWidth() + f.marginBtn:GetWidth() + 36)
		f.bar:ClearAllPoints()
		f.bar:SetPoint("TOP", f, "TOP", 0, -(game and 70 or 12))
		f:Show(); f.bar:Show()

		local l = NS.ScreenLayout(s.id)
		local area = NS.ScreenArea(s)
		local parts, cuts = NS.TreeParts(l)
		for n, part in ipairs(parts) do
			zi = zi + 1
			local z = getZoneFrame(zi)
			local fr = part.f
			z.zone = { screen = s.id, index = n, data = part.node }
			z.label = s.id .. (LETTERS[n] or tostring(n))
			place(z, { x = area.x + fr[1] * area.w, y = area.y + fr[2] * area.h, w = fr[3] * area.w, h = fr[4] * area.h })
			local names = {}
			for _, k in ipairs(NS.ZoneKeys(part.node)) do names[#names + 1] = NS.WindowLabel(k) end
			z.tab:SetLabel(z.label .. ":  " .. (names[1] and table.concat(names, " + ") or "empty - click to choose"))
			z:Show()
		end
		local W = 8   -- line thickness in overlay units
		for _, c in ipairs(cuts) do
			di = di + 1
			local d = getDivider(di)
			local fr, r = c.f, c.node.r or 0.5
			d.screenId, d.node, d.f = s.id, c.node, fr
			local x, y, w, h = area.x + fr[1] * area.w, area.y + fr[2] * area.h, fr[3] * area.w, fr[4] * area.h
			d:ClearAllPoints()
			if c.node.dir == "v" then
				d:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(x + r * w) - W / 2, -L(y))
				d:SetSize(W, math.max(1, L(h)))
			else
				d:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(x), -L(y + r * h) + W / 2)
				d:SetSize(math.max(1, L(w)), W)
			end
			d:Show()
		end
	end
	for i = #screens + 1, #screenFrames do screenFrames[i]:Hide(); screenFrames[i].bar:Hide() end
	for i = zi + 1, #zoneFrames do zoneFrames[i]:Hide() end
	for i = di + 1, #dividers do dividers[i]:Hide() end

	if profBtn then profBtn:SetLabel("Profile: " .. NS.db.profile) end
	refreshFloats()
	-- top bar on the game screen
	local g = NS.GetScreen(gameId)
	if g and topBar then
		topBar:ClearAllPoints()
		topBar:SetPoint("TOP", overlay, "TOPLEFT", L(g.x + g.w / 2), -L(g.y) - 14)
	end
end

-- The zone under a point (root units, y from the top).
local function zoneAt(x, y)
	for _, z in ipairs(NS.AllZones()) do
		local r = z.rect
		if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return z end
	end
end

-- "Draw a cut": press the mouse in a zone, drag in the direction the line should go, release.
-- "Draw a cut": a line follows the mouse through the zone under it; click to cut there. The mouse wheel turns
-- the line between vertical and horizontal; until you turn it, it runs across the longer side of the zone.
local cutDir   -- "v" / "h" once turned with the wheel
local function cutPreview()
	local _, rh = NS.RootSize()
	local cx, cy = GetCursorPosition()
	local x, y = cx, rh - cy
	local z = zoneAt(x, y)
	if not z or z.float then cutLine:Hide() return nil end
	local r = z.rect
	local dir = cutDir or ((r.w >= r.h) and "v" or "h")
	local pos
	cutLine:ClearAllPoints()
	if dir == "v" then
		pos = math.max(0.08, math.min(0.92, (x - r.x) / r.w))
		cutLine:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(r.x + pos * r.w) - 3, -L(r.y))
		cutLine:SetSize(6, math.max(1, L(r.h)))
	else
		pos = math.max(0.08, math.min(0.92, (y - r.y) / r.h))
		cutLine:SetPoint("TOPLEFT", overlay, "TOPLEFT", L(r.x), -L(r.y + pos * r.h) + 3)
		cutLine:SetSize(math.max(1, L(r.w)), 6)
	end
	cutLine:Show()
	return z, dir, pos
end

local function setCutting(on)
	cutting = on and true or false
	cutStart, cutDir = nil, nil
	if cutBtn then cutBtn:SetLabel(cutting and "Cutting: click = cut, wheel = turn line, right-click = stop" or "Draw a cut") end
	if not cutFrame then
		if not on then return end
		cutFrame = CreateFrame("Frame", nil, overlay)
		cutFrame:SetAllPoints(overlay)
		cutFrame:SetFrameStrata("FULLSCREEN_DIALOG")
		cutFrame:SetFrameLevel(40)
		cutFrame:EnableMouse(true)
		cutLine = CreateFrame("Frame", nil, cutFrame)
		cutLine:SetFrameStrata("TOOLTIP")
		local t = solid(cutLine, "OVERLAY", 0.3, 1, 0.3, 0.95); t:SetAllPoints()
		cutFrame:SetScript("OnMouseDown", function(_, btn)
			if btn ~= "LeftButton" then setCutting(false) return end
			cutStart = true
		end)
		cutFrame:EnableMouseWheel(true)
		cutFrame:SetScript("OnMouseWheel", function()
			local _, d = cutPreview()
			cutDir = (d == "v") and "h" or "v"
			cutPreview()
		end)
		cutFrame:SetScript("OnMouseUp", function(_, btn)
			if btn ~= "LeftButton" or not cutStart then return end
			local z, dir, pos = cutPreview()
			cutStart = nil
			if z then
				NS.SplitZone(z.data, dir, pos)
				NS.ApplyWindows(); NS.RefreshLayoutOverlay()
			end
		end)
		cutFrame:SetScript("OnUpdate", function() if cutting then cutPreview() end end)
	end
	cutFrame:SetShown(cutting)
	if cutting then
		if list then list:Hide() end
		if margins then margins:Hide() end
	end
end

local function onUpdate()
	if floatDrag then
		local d = NS.FloatTable()[floatDrag.key]
		if not d then floatDrag = nil return end
		local rw, rh = NS.RootSize()
		local cx, cy = GetCursorPosition()
		d.cx = math.max(0.01, math.min(0.99, cx / rw - floatDrag.dx))
		d.cy = math.max(0.01, math.min(0.99, (rh - cy) / rh - floatDrag.dy))
		NS.ApplyWindow(floatDrag.key)
		refreshFloats()
		return
	end
	if not dragging then return end
	local screen = NS.GetScreen(dragging.screen)
	if not screen then dragging = nil return end
	local area = NS.ScreenArea(screen)
	local _, rh = NS.RootSize()
	local cx, cy = GetCursorPosition()
	local f, node = dragging.f, dragging.node
	local v
	if node.dir == "v" then
		v = (cx - (area.x + f[1] * area.w)) / math.max(1, f[3] * area.w)
	else
		v = ((rh - cy) - (area.y + f[2] * area.h)) / math.max(1, f[4] * area.h)
	end
	node.r = snap(math.max(0.08, math.min(0.92, v)))
	local now = GetTime()
	if now - (overlay.lastApply or 0) > 0.05 then
		overlay.lastApply = now
		NS.RefreshLayoutOverlay()
		NS.ApplyWindows()
	end
end

local function build()
	overlay = CreateFrame("Frame", "FarsightLayout", NS.root)
	overlay:SetAllPoints(NS.root)
	overlay:SetFrameStrata("BACKGROUND")
	overlay:SetScript("OnUpdate", onUpdate)
	overlay:SetScript("OnHide", function()
		dragging = nil
		stopPicking()
		if cutting then setCutting(false) end
		floatDrag = nil
		if namePrompt then namePrompt:Hide() end
		if list then list:Hide() end
		if margins then margins:Hide() end
	end)
	overlay:Hide()

	topBar = CreateFrame("Frame", nil, overlay)
	topBar:SetFrameStrata("FULLSCREEN_DIALOG")
	topBar:SetSize(1400, 46)
	topBar:SetFrameLevel(60)   -- stays clickable above the cut tool
	local bg = solid(topBar, "BACKGROUND", 0, 0, 0, 0.8); bg:SetAllPoints()
	local t = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("LEFT", 12, 0); t:SetWidth(470); t:SetJustifyH("LEFT")
	t:SetText("Farsight layout: click a zone tab to choose its window, drag the yellow lines to resize, use Draw a cut to split a zone.")
	local done = button(topBar, "Done", function() overlay:Hide() end)
	done:SetPoint("RIGHT", -10, 0)
	local opt = button(topBar, "Options", function() NS.ToggleOptions(true) end)
	opt:SetPoint("RIGHT", done, "LEFT", -6, 0)
	cutBtn = button(topBar, "Draw a cut", function() setCutting(not cutting) end)
	cutBtn:SetPoint("RIGHT", opt, "LEFT", -6, 0)
	profBtn = button(topBar, "Profile", function(self) profileMenu(self) end)
	profBtn:SetPoint("RIGHT", cutBtn, "LEFT", -6, 0)
	freeBtn = button(topBar, "Free window", function(self) freeMenu(self) end)
	freeBtn:SetPoint("RIGHT", profBtn, "LEFT", -6, 0)
	tinsert(UISpecialFrames, "FarsightLayout")   -- ESC leaves layout mode
end

function NS.ToggleLayout()
	if not NS.db then return end
	if NS.passive then NS.Print("Farsight is passive because MultiMonViewport is enabled.") return end
	if not NS.IsSpanned() then
		NS.Print("The WoW window is not stretched across your screens yet. Start WoW with the Farsight Launcher first.")
		return
	end
	if InCombatLockdown() then NS.Print("Leave combat first.") return end
	if not overlay then build() end
	if overlay:IsShown() then overlay:Hide() else overlay:Show(); NS.RefreshLayoutOverlay() end
end


-- ================================================================ first-start guide
local welcome

local function biggestOtherScreen()
	local game = NS.GameScreenId()
	local best
	for _, sc in ipairs((NS.GetScreens())) do
		if sc.id ~= game and (not best or sc.w * sc.h > best.w * best.h) then best = sc end
	end
	return best
end

local PRESETS = {
	{ label = "Map and bags", wins = { "map", "bags" },
		wide = function(z) return { dir = "v", r = 0.3, a = z("bags"), b = z("map") } end,
		tall = function(z) return { dir = "h", r = 0.65, a = z("map"), b = z("bags") } end },
	{ label = "Map, bags and chat", wins = { "map", "bags", "ChatFrame1" },
		wide = function(z) return { dir = "v", r = 0.3, a = { dir = "h", r = 0.5, a = z("bags"), b = z("ChatFrame1") }, b = z("map") } end,
		tall = function(z) return { dir = "h", r = 0.6, a = z("map"), b = { dir = "v", r = 0.5, a = z("bags"), b = z("ChatFrame1") } } end },
	{ label = "Map, bags, chat and info panel", wins = { "map", "bags", "ChatFrame1", "FarsightInfoPanel" },
		wide = function(z) return { dir = "v", r = 0.3,
			a = { dir = "h", r = 0.36, a = z("bags"), b = { dir = "h", r = 0.5, a = z("FarsightInfoPanel"), b = z("ChatFrame1") } }, b = z("map") } end,
		tall = function(z) return { dir = "h", r = 0.55, a = z("map"),
			b = { dir = "v", r = 0.34, a = z("bags"), b = { dir = "v", r = 0.5, a = z("FarsightInfoPanel"), b = z("ChatFrame1") } } } end },
}

local function applyPreset(preset)
	local sc = biggestOtherScreen()
	if not sc then
		NS.Print("WoW only covers one screen. Pick more screens in the Farsight Launcher first.")
		return
	end
	if InCombatLockdown() then NS.Print("Leave combat first.") return end
	local want = {}
	for _, k in ipairs(preset.wins) do want[k] = true end
	for _, zn in ipairs(NS.AllZones()) do
		if want[zn.data.win] then zn.data.win = nil; zn.data.fit = nil end
	end
	local function z(key) return { win = key } end
	local l = NS.ScreenLayout(sc.id)
	l.tree = (sc.h > sc.w * 1.1) and preset.tall(z) or preset.wide(z)
	NS.db.pins.bags, NS.db.pins.map = true, true
	if NS.ReleaseAssignedFromMoveAny then pcall(NS.ReleaseAssignedFromMoveAny) end
	NS.ApplyWindows()
	NS.OpenWindow("map"); NS.OpenWindow("bags")
	if want.FarsightInfoPanel and NS.ShowInfoPanel then NS.ShowInfoPanel(true) end
	C_Timer.After(0.3, function() NS.ApplyWindows() end)
	NS.Print("Done: " .. preset.label .. " on screen " .. sc.id .. ". Change anything with /farsight layout.")
	if NS.IsLoaded("MoveAny") then
		NS.Print("You use MoveAny: if a window does not go to its zone, type /reload once.")
	end
end

function NS.ShowWelcome(auto)
	if not NS.db or NS.passive then return end
	if not NS.Active() then
		if not auto then NS.Print("Start WoW with the Farsight Launcher first, so the window covers your screens.") end
		return
	end
	if auto then
		-- only for a fresh setup: nothing placed yet
		for _, zn in ipairs(NS.AllZones()) do if zn.data.win then NS.db.welcomed = true return end end
	end
	if not welcome then
		welcome = CreateFrame("Frame", "FarsightWelcome", UIParent)
		welcome:SetFrameStrata("DIALOG")
		welcome:SetSize(520, 330)
		welcome:EnableMouse(true)
		local bg = solid(welcome, "BACKGROUND", 0.04, 0.05, 0.08, 0.96); bg:SetAllPoints()
		local top = solid(welcome, "BORDER", 0.4, 0.6, 0.9, 1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(3)
		local title = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		title:SetPoint("TOP", 0, -18); title:SetText("Welcome to Farsight")
		welcome.text = welcome:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		welcome.text:SetPoint("TOP", title, "BOTTOM", 0, -12); welcome.text:SetWidth(470); welcome.text:SetJustifyH("CENTER")
		local prev
		for i, preset in ipairs(PRESETS) do
			local b = button(welcome, preset.label, function() NS.db.welcomed = true; welcome:Hide(); applyPreset(preset) end)
			b:SetHeight(30); b:SetWidth(330)
			if prev then b:SetPoint("TOP", prev, "BOTTOM", 0, -8) else b:SetPoint("TOP", welcome.text, "BOTTOM", 0, -18) end
			prev = b
		end
		local own = button(welcome, "I will set it up myself", function()
			NS.db.welcomed = true; welcome:Hide()
			NS.ToggleLayout()
		end)
		own:SetHeight(26); own:SetWidth(330); own:SetPoint("TOP", prev, "BOTTOM", 0, -18)
		local later = button(welcome, "Not now", function() NS.db.welcomed = true; welcome:Hide() end)
		later:SetHeight(24); later:SetPoint("TOP", own, "BOTTOM", 0, -8)
		local hint = welcome:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		hint:SetPoint("BOTTOM", 0, 10); hint:SetText("You can open this again with /farsight welcome")
	end
	local sc = biggestOtherScreen()
	welcome.text:SetText(sc
		and ("WoW covers " .. #(NS.GetScreens()) .. " screens. The game is on screen " .. tostring(NS.GameScreenId())
			.. ".\nWhat do you want on screen " .. sc.id .. " (" .. sc.name .. ")?")
		or "WoW only covers one screen right now. Pick more screens in the Farsight Launcher to use the presets.")
	-- in the middle of the game screen
	local g = NS.GameRect()
	local es = UIParent:GetEffectiveScale()
	welcome:ClearAllPoints()
	welcome:SetPoint("CENTER", UIParent, "TOPLEFT", (g.x + g.w / 2) / es, -(g.y + g.h / 2) / es)
	welcome:Show()
end
