-- Farsight: core. Screen geometry, game area (3D world), UI scale, events.
-- Coordinates: "root units" are measured on FarsightRoot, an invisible frame covering the whole WoW window.
-- x grows to the right, y grows DOWN from the top edge. Screens and zones are stored as fractions of the window.
local ADDON, NS = ...

NS.DEFAULTS = {
	enabled = true,
	viewport = true,       -- limit the 3D world to the game screen
	gameScreen = nil,      -- screen id; nil = the launcher's choice
	gameRect = nil,        -- manual game area in pixels { x, y, w, h }; nil = the whole game screen
	uiScale = nil,         -- nil = automatic
	hud = "all",           -- where the normal UI lives: "all" (whole window), "game", or a screen id
	manual = false,        -- use manualScreens instead of the launcher's values
	manualWindow = nil,    -- { w, h } in pixels
	manualScreens = nil,   -- { { id, name, x, y, w, h }, ... } in pixels
	layout = {},           -- [screenId] = { split, r, r2, inset = { l, t, r, b }, zones = { [i] = { win, fit } } }
	pins = { bags = true, map = true },   -- [windowKey] = true: ESC and NPC windows do not close it
	infoRows = {},         -- [row name] = false: rows hidden in the info panel
	welcomed = false,      -- the first-start guide has been shown
	mapAlways = false,     -- keep the map open even beside NPC windows (takes it out of the panel manager)
	wanted = {},           -- [windowKey] = true: was open, reopen it
	custom = {},           -- [frameName] = label: windows added with the mouse picker
	profile = "Default",   -- name of the active layout profile
	profiles = {},         -- [name] = { layout, pins }: saved layouts; the active one lives in layout / pins
	autoProfile = {},      -- rest / instance / world = profile name: switch automatically
	maBackup = {},         -- [windowKey] = { [frameName] = { point, scale } }: what MoveAny had saved before we took over
	undocked = {},         -- [chatKey] = true: chat tabs we pulled out of the main chat window
	minimap = { hide = false, angle = 215 },
	debug = false,
}

function NS.Print(msg) print("|cff66ccffFarsight|r: " .. tostring(msg)) end
function NS.Debug(...)
	if not (NS.db and NS.db.debug) then return end
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	print("|cff66ccffFarsight|r |cff888888" .. table.concat(t, " ") .. "|r")
end

local function isLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
	if IsAddOnLoaded then return IsAddOnLoaded(name) end
	return false
end
NS.IsLoaded = isLoaded

-- ---------------------------------------------------------------- root frame
local root = CreateFrame("Frame", "FarsightRoot")
root:SetAllPoints()
NS.root = root

function NS.RootSize() return root:GetWidth(), root:GetHeight() end

-- ---------------------------------------------------------------- screens
-- Returns window = { w, h } (pixels) and a list of screens { id, name, x, y, w, h } (pixels) or nil.
local function rawLayout()
	local db = NS.db
	if db.manual and db.manualScreens and db.manualWindow then
		return db.manualWindow, db.manualScreens, "manual"
	end
	local m = FarsightMonitors
	if type(m) == "table" and type(m.window) == "table" and type(m.screens) == "table" and #m.screens > 0 then
		return m.window, m.screens, "launcher"
	end
	return nil
end

-- Is the WoW window really stretched the way the layout says? Compared by shape, since addons
-- cannot read the window size in pixels reliably.
function NS.IsSpanned()
	local win = rawLayout()
	if not win or not win.w or not win.h or win.h == 0 then return false end
	local rw, rh = NS.RootSize()
	if not rw or not rh or rh == 0 then return false end
	local want, have = win.w / win.h, rw / rh
	return math.abs(want - have) / want < 0.02
end

function NS.Active()
	return NS.db and NS.db.enabled and not NS.passive and NS.IsSpanned()
end

-- Screens with their rectangle in root units. Without layout data: one screen covering the window.
function NS.GetScreens()
	local rw, rh = NS.RootSize()
	local win, screens, source = rawLayout()
	local out = {}
	if not win then
		out[1] = { id = 1, name = "WoW window", x = 0, y = 0, w = rw, h = rh, px = { x = 0, y = 0, w = 0, h = 0 } }
		return out, nil
	end
	for _, s in ipairs(screens) do
		out[#out + 1] = {
			id = s.id, name = s.name or ("Screen " .. tostring(s.id)),
			x = s.x / win.w * rw, y = s.y / win.h * rh, w = s.w / win.w * rw, h = s.h / win.h * rh,
			px = { x = s.x, y = s.y, w = s.w, h = s.h },
		}
	end
	return out, source
end

function NS.GetScreen(id)
	for _, s in ipairs((NS.GetScreens())) do if s.id == id then return s end end
end

function NS.GameScreenId()
	local db = NS.db
	if db.gameScreen and NS.GetScreen(db.gameScreen) then return db.gameScreen end
	local m = FarsightMonitors
	if not db.manual and type(m) == "table" and m.game and NS.GetScreen(m.game) then return m.game end
	local list = NS.GetScreens()
	return list[1] and list[1].id
end

-- Game area in root units.
function NS.GameRect()
	local db = NS.db
	local win = rawLayout()
	local rw, rh = NS.RootSize()
	if db.gameRect and win then
		local g = db.gameRect
		return { x = g.x / win.w * rw, y = g.y / win.h * rh, w = g.w / win.w * rw, h = g.h / win.h * rh }
	end
	local s = NS.GetScreen(NS.GameScreenId())
	if not s then return { x = 0, y = 0, w = rw, h = rh } end
	return { x = s.x, y = s.y, w = s.w, h = s.h }
end

function NS.WindowPixels()
	local win = rawLayout()
	return win and win.w, win and win.h
end

-- ---------------------------------------------------------------- UI scale
function NS.AutoScale()
	local win = rawLayout()
	local s = NS.GetScreen(NS.GameScreenId())
	if not win or not s or not s.px or win.h == 0 then return nil end
	local base = 1
	if GetCVarBool and GetCVarBool("useUiScale") then base = tonumber(GetCVar("uiScale")) or 1 end
	-- same physical size as that UI scale would give on the game screen alone
	return math.max(0.2, math.min(1.5, base * s.px.h / win.h))
end

function NS.TargetScale()
	return NS.db.uiScale or NS.AutoScale()
end

-- ---------------------------------------------------------------- apply
local pending = false
local hudTouched = false
local viewTouched = false
local origScale

local function hudRect()
	return nil   -- removed: the game does not allow moving the whole UI to one screen
end

-- Restricting UIParent to one screen is experimental. If the game refuses it, UIParent must never be
-- left without anchors (that breaks the whole UI), so it is restored and the option switched off.
local function applyHud(scale)
	local db = NS.db
	if scale then
		origScale = origScale or UIParent:GetScale()
		UIParent:SetScale(scale)
	elseif origScale then
		UIParent:SetScale(origScale)   -- we are paused: give the UI its normal scale back
		origScale = nil
	end
	local rect = hudRect()
	if rect then
		local s = UIParent:GetEffectiveScale()
		local ok, err = pcall(function()
			UIParent:ClearAllPoints()
			UIParent:SetPoint("TOPLEFT", nil, "TOPLEFT", rect.x / s, -rect.y / s)
			UIParent:SetSize(rect.w / s, rect.h / s)
		end)
		hudTouched = true
		if not ok or (UIParent:GetWidth() or 0) < 1 or (UIParent:GetHeight() or 0) < 1 then
			db.hud = "all"
			NS.Print("This game version does not allow moving the whole UI to one screen, so that option was switched off.")
			NS.Debug(err)
			rect = nil
		end
	end
	if not rect and hudTouched then
		UIParent:ClearAllPoints()
		UIParent:SetAllPoints()
		hudTouched = false
	end
end

-- Back to automatic values for everything that depends on the screens.
function NS.Calibrate()
	local db = NS.db
	db.enabled, db.viewport, db.manual = true, true, false
	db.gameScreen, db.gameRect, db.uiScale, db.hud = nil, nil, nil, "all"
	hudTouched = true   -- force UIParent back onto the whole window
	NS.ApplyAll()
	if InCombatLockdown() then
		NS.Print("Auto-calibrate runs as soon as you leave combat.")
	elseif NS.Active() then
		local g = NS.GetScreen(NS.GameScreenId())
		NS.Print(("Auto-calibrated: game on screen %s (%dx%d), UI scale %.2f."):format(tostring(g and g.id), g and g.px.w or 0, g and g.px.h or 0, NS.TargetScale() or 0))
	else
		NS.Print("Auto-calibrate: the WoW window is not stretched across your screens. Start WoW with the Farsight Launcher.")
	end
end

-- The game refuses to anchor WorldFrame to an addon frame ("anchor family"), so it is anchored to
-- UIParent, which covers the whole window unless the experimental HUD option moved it.
local function applyViewport()
	local db = NS.db
	local rel = (not hudTouched) and UIParent or nil
	if not (NS.Active() and db.viewport) then
		if viewTouched then   -- only undo what we changed ourselves
			viewTouched = false
			WorldFrame:ClearAllPoints()
			WorldFrame:SetAllPoints(rel)
		end
		return
	end
	viewTouched = true
	local g = NS.GameRect()
	local ws = WorldFrame:GetEffectiveScale()
	WorldFrame:ClearAllPoints()
	local ok, err = pcall(function()
		WorldFrame:SetPoint("TOPLEFT", rel, "TOPLEFT", g.x / ws, -g.y / ws)
		WorldFrame:SetPoint("BOTTOMRIGHT", rel, "TOPLEFT", (g.x + g.w) / ws, -(g.y + g.h) / ws)
	end)
	if not ok then
		WorldFrame:ClearAllPoints()
		WorldFrame:SetAllPoints(UIParent)
		NS.Print("Could not set the game area: " .. tostring(err))
	end
end

-- Applies everything that depends on the window: scale, HUD area, game area, window zones.
function NS.ApplyAll()
	if not NS.db or NS.passive then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	local active = NS.Active()
	applyHud(active and NS.TargetScale() or nil)
	local ok, err = pcall(applyViewport)
	if not ok then NS.Print("game area error: " .. tostring(err)) end
	NS.wasActive = active
	if NS.ApplyWindows then NS.ApplyWindows() end
	if NS.RefreshLayoutOverlay then NS.RefreshLayoutOverlay() end
end

function NS.ApplySoon(delay)
	C_Timer.After(delay or 0.1, NS.ApplyAll)
end

-- ---------------------------------------------------------------- layout data helpers
NS.SPLITS = {
	{ key = "none",  label = "No zones" },
	{ key = "full",  label = "One zone (whole screen)" },
	{ key = "cols2", label = "Two zones side by side" },
	{ key = "rows2", label = "Two zones, top and bottom" },
	{ key = "cols3", label = "Three zones side by side" },
	{ key = "rows3", label = "Three zones stacked" },
	{ key = "grid4", label = "Four zones (2 x 2)" },
	{ key = "left2", label = "One big zone left, two on the right" },
	{ key = "right2", label = "Two on the left, one big zone right" },
}

-- Zones of a screen are stored as a tree: a node is either a zone { win, fit } or a cut
-- { dir = "v" | "h", r = position 0..1, a = left/top part, b = right/bottom part }.
-- tree = false means the screen has no zones.
local function Z(zones, i) local z = zones[i] or {}; return { win = z.win, fit = z.fit } end

function NS.PresetTree(split, r, r2, zones)
	r, r2, zones = r or 0.5, r2 or 0.5, zones or {}
	local function V(rr, a, b) return { dir = "v", r = rr, a = a, b = b } end
	local function H(rr, a, b) return { dir = "h", r = rr, a = a, b = b } end
	if split == "full" then return Z(zones, 1)
	elseif split == "cols2" then return V(r, Z(zones, 1), Z(zones, 2))
	elseif split == "rows2" then return H(r2, Z(zones, 1), Z(zones, 2))
	elseif split == "cols3" then return V(r * 2 / 3, Z(zones, 1), V(0.5, Z(zones, 2), Z(zones, 3)))
	elseif split == "rows3" then return H(r2 * 2 / 3, Z(zones, 1), H(0.5, Z(zones, 2), Z(zones, 3)))
	elseif split == "grid4" then return H(r2, V(r, Z(zones, 1), Z(zones, 2)), V(r, Z(zones, 3), Z(zones, 4)))
	elseif split == "left2" then return V(r, Z(zones, 1), H(r2, Z(zones, 2), Z(zones, 3)))
	elseif split == "right2" then return V(r, H(r2, Z(zones, 1), Z(zones, 2)), Z(zones, 3))
	end
	return false
end

function NS.ScreenLayout(id)
	local l = NS.db.layout[id]
	if not l then
		l = { inset = { 0, 0, 0, 0 }, tree = false }
		NS.db.layout[id] = l
	end
	l.inset = l.inset or { 0, 0, 0, 0 }
	if l.tree == nil then   -- layout saved by an older version
		l.tree = NS.PresetTree(l.split or "none", l.r, l.r2, l.zones)
		l.split, l.r, l.r2, l.zones = nil, nil, nil, nil
	end
	return l
end

local function walk(node, x, y, w, h, leaves, cuts)
	if type(node) ~= "table" then return end
	if node.dir then
		local r = node.r or 0.5
		node.a, node.b = node.a or {}, node.b or {}
		cuts[#cuts + 1] = { node = node, f = { x, y, w, h } }
		if node.dir == "v" then
			walk(node.a, x, y, w * r, h, leaves, cuts)
			walk(node.b, x + w * r, y, w * (1 - r), h, leaves, cuts)
		else
			walk(node.a, x, y, w, h * r, leaves, cuts)
			walk(node.b, x, y + h * r, w, h * (1 - r), leaves, cuts)
		end
	else
		leaves[#leaves + 1] = { node = node, f = { x, y, w, h } }
	end
end

-- Returns the zones and the cuts of a screen layout, each with its rectangle f = { x, y, w, h }
-- as fractions of the screen's usable area.
function NS.TreeParts(l)
	local leaves, cuts = {}, {}
	if l.tree then walk(l.tree, 0, 0, 1, 1, leaves, cuts) end
	return leaves, cuts
end

-- Cuts a zone in two. What the zone held stays in the larger part (left / top when they are equal), so
-- cutting a thin slice off a zone makes a new empty zone instead of squeezing the window into the slice.
function NS.SplitZone(zone, dir, r)
	if zone.dir then return end
	r = math.max(0.08, math.min(0.92, r or 0.5))
	local keep = { win = zone.win, fit = zone.fit, more = zone.more, barDir = zone.barDir }
	if r < 0.5 then zone.a, zone.b = {}, keep else zone.a, zone.b = keep, {} end
	zone.win, zone.fit, zone.more, zone.barDir = nil, nil, nil, nil
	zone.dir, zone.r = dir, r
end

-- Removes a zone; its neighbour takes over the space.
function NS.RemoveZone(screenId, zone)
	local l = NS.ScreenLayout(screenId)
	if l.tree == zone then l.tree = false return end
	local function find(n)
		if type(n) ~= "table" or not n.dir then return nil end
		if n.a == zone or n.b == zone then return n end
		return find(n.a) or find(n.b)
	end
	local p = find(l.tree)
	if not p then return end
	local keep = (p.a == zone) and p.b or p.a
	p.dir, p.r, p.a, p.b, p.win, p.fit = keep.dir, keep.r, keep.a, keep.b, keep.win, keep.fit
	p.more, p.stack, p.barDir = keep.more, nil, keep.barDir
end

-- Usable area of a screen (screen minus reserved margins) in root units.
function NS.ScreenArea(screen)
	local l = NS.ScreenLayout(screen.id)
	local sx = (screen.px and screen.px.w and screen.px.w > 0) and (screen.w / screen.px.w) or 0
	local sy = (screen.px and screen.px.h and screen.px.h > 0) and (screen.h / screen.px.h) or 0
	local il, it, ir, ib = (l.inset[1] or 0) * sx, (l.inset[2] or 0) * sy, (l.inset[3] or 0) * sx, (l.inset[4] or 0) * sy
	return { x = screen.x + il, y = screen.y + it, w = math.max(1, screen.w - il - ir), h = math.max(1, screen.h - it - ib) }
end

-- All zones: { screen = id, index = i, rect = { x, y, w, h } (root units), data = zone table }
function NS.AllZones()
	local out = {}
	for _, screen in ipairs((NS.GetScreens())) do
		local l = NS.ScreenLayout(screen.id)
		local area = NS.ScreenArea(screen)
		for i, p in ipairs((NS.TreeParts(l))) do
			local f = p.f
			out[#out + 1] = {
				screen = screen.id, index = i, data = p.node,
				rect = { x = area.x + f[1] * area.w, y = area.y + f[2] * area.h, w = f[3] * area.w, h = f[4] * area.h },
			}
		end
	end
	-- Free windows: not in a zone, but kept at a place and size of their own (layout.float).
	-- cx, cy = the middle of the window as fractions of the whole WoW window.
	local float = NS.db.layout.float
	if type(float) == "table" then
		local rw, rh = NS.RootSize()
		local n = 0
		for key, d in pairs(float) do
			if type(d) ~= "table" or d.win ~= key then
				float[key] = nil
			else
				n = n + 1
				out[#out + 1] = {
					screen = 0, index = n, data = d, float = true,
					rect = { x = (d.cx or 0.5) * rw - 20, y = (d.cy or 0.5) * rh - 20, w = 40, h = 40 },
				}
			end
		end
	end
	return out
end

function NS.FloatTable()
	local l = NS.db.layout
	if type(l.float) ~= "table" then l.float = {} end
	return l.float
end

-- The windows of a zone: usually one (data.win). A zone can hold several bars; the extra ones are in data.more.
function NS.ZoneKeys(data)
	local keys = {}
	if type(data) ~= "table" then return keys end
	if type(data.more) == "table" then
		if not data.win then data.win = table.remove(data.more, 1) end
		if #data.more == 0 then data.more = nil end
	end
	if data.win then keys[1] = data.win end
	if data.more then for _, k in ipairs(data.more) do keys[#keys + 1] = k end end
	return keys
end

-- Takes a window out of a zone. Returns true if it was there.
function NS.ZoneRemoveKey(data, key)
	if data.win == key then
		data.win, data.fit = nil, nil
		NS.ZoneKeys(data)   -- promotes the next bar, if any
		return true
	end
	if data.more then
		for i, k in ipairs(data.more) do
			if k == key then table.remove(data.more, i); NS.ZoneKeys(data); return true end
		end
	end
	return false
end

function NS.FindZoneOf(winKey)
	for _, z in ipairs(NS.AllZones()) do
		for _, k in ipairs(NS.ZoneKeys(z.data)) do if k == winKey then return z end end
	end
end

-- ---------------------------------------------------------------- layout profiles
-- A profile holds the zones, their windows, the margins and the "keep open" choices. The active profile is
-- the live layout; it is stored under its name whenever you switch away from it.
local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

local pendingProfile

function NS.SaveProfile()
	local db = NS.db
	db.profiles[db.profile] = { layout = copy(db.layout), pins = copy(db.pins) }
end

function NS.ProfileNames()
	local t = {}
	for name in pairs(NS.db.profiles) do t[#t + 1] = name end
	table.sort(t, function(a, b) return a:lower() < b:lower() end)
	return t
end

function NS.FindProfile(name)
	if type(name) ~= "string" then return nil end
	for n in pairs(NS.db.profiles) do if n:lower() == name:lower() then return n end end
end

function NS.SwitchProfile(name, quiet)
	local db = NS.db
	name = NS.FindProfile(name)
	if not name then return false end
	if name == db.profile then return true end
	if InCombatLockdown() then
		pendingProfile = name
		if not quiet then NS.Print("Switching to profile " .. name .. " when you leave combat.") end
		return false
	end
	pendingProfile = nil
	NS.SaveProfile()
	local p = db.profiles[name]
	db.layout = copy(p.layout or {})
	db.pins = copy(p.pins or { bags = true, map = true })
	db.profile = name
	if NS.ReleaseAssignedFromMoveAny then pcall(NS.ReleaseAssignedFromMoveAny) end
	NS.ApplyAll()
	if not quiet then NS.Print("Profile: " .. name) end
	return true
end

-- A new profile starts as a copy of the current one.
function NS.NewProfile(name)
	local db = NS.db
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then return false end
	if NS.FindProfile(name) then return NS.SwitchProfile(name) end
	NS.SaveProfile()
	db.profile = name
	NS.SaveProfile()
	NS.Print("New profile: " .. name .. " (a copy of the previous one - change it as you like)")
	if NS.RefreshLayoutOverlay then NS.RefreshLayoutOverlay() end
	return true
end

function NS.DeleteProfile(name)
	local db = NS.db
	name = NS.FindProfile(name)
	if not name then return false end
	if name == db.profile then
		local other
		for _, n in ipairs(NS.ProfileNames()) do if n ~= name then other = n break end end
		if not other then NS.Print("This is the only profile.") return false end
		if not NS.SwitchProfile(other, true) then return false end
	end
	db.profiles[name] = nil
	for ctx, n in pairs(db.autoProfile) do if n == name then db.autoProfile[ctx] = nil end end
	NS.Print("Deleted profile " .. name .. ". Active: " .. db.profile)
	if NS.RefreshLayoutOverlay then NS.RefreshLayoutOverlay() end
	return true
end

-- ----- sharing: a profile as one line of text
local function ser(v, out)
	local t = type(v)
	if t == "number" then
		local n = ("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")
		out[#out + 1] = n
	elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
	elseif t == "string" then
		local q = v:gsub('[%%"]', function(c) return ("%%%02X"):format(c:byte()) end)
		out[#out + 1] = '"' .. q .. '"'
	elseif t == "table" then
		out[#out + 1] = "{"
		for k, val in pairs(v) do
			if type(k) == "number" or type(k) == "string" then
				ser(k, out); out[#out + 1] = "="; ser(val, out); out[#out + 1] = ","
			end
		end
		out[#out + 1] = "}"
	else out[#out + 1] = "F" end
end

local function deser(str)
	local pos = 1
	local function value(depth)
		if depth > 30 then error("too deep") end
		local c = str:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local t = {}
			while str:sub(pos, pos) ~= "}" do
				if pos > #str then error("unfinished") end
				local k = value(depth + 1)
				if str:sub(pos, pos) ~= "=" then error("bad key") end
				pos = pos + 1
				t[k] = value(depth + 1)
				if str:sub(pos, pos) == "," then pos = pos + 1 end
			end
			pos = pos + 1
			return t
		elseif c == '"' then
			local e = str:find('"', pos + 1, true)
			if not e then error("bad text") end
			local raw = str:sub(pos + 1, e - 1)
			pos = e + 1
			local txt = raw:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
			return txt
		elseif c == "T" then pos = pos + 1 return true
		elseif c == "F" then pos = pos + 1 return false
		else
			local num = str:match("^-?%d+%.?%d*", pos)
			if not num then error("bad value") end
			pos = pos + #num
			return tonumber(num)
		end
	end
	return value(0)
end

function NS.ExportProfile()
	NS.SaveProfile()
	local out = {}
	ser(NS.db.profiles[NS.db.profile], out)
	return "FARSIGHT1:" .. table.concat(out)
end

-- Returns true and the new profile's name, or false and a reason.
function NS.ImportProfile(text, name)
	text = (text or ""):gsub("[\r\n]", "")
	text = text:match("^%s*(.-)%s*$")
	local body = text:match("^FARSIGHT1:(.+)$")
	if not body then return false, "That is not a Farsight layout (it should start with FARSIGHT1:)." end
	local ok, data = pcall(deser, body)
	if not ok or type(data) ~= "table" or type(data.layout) ~= "table" then return false, "The text is damaged or incomplete." end
	-- screens are numbered per computer: move screens we do not have onto free screens of ours
	local mine, used, layout = {}, {}, {}
	for _, sc in ipairs((NS.GetScreens())) do mine[sc.id] = true end
	for id, l in pairs(data.layout) do
		if id == "float" or mine[id] then layout[id] = l; used[id] = true end
	end
	local foreign = {}
	for id in pairs(data.layout) do if id ~= "float" and not mine[id] then foreign[#foreign + 1] = id end end
	table.sort(foreign, function(a, b) return tostring(a) < tostring(b) end)
	local game = NS.GameScreenId()
	for _, id in ipairs(foreign) do
		for _, sc in ipairs((NS.GetScreens())) do
			if not used[sc.id] and sc.id ~= game then layout[sc.id] = data.layout[id]; used[sc.id] = true break end
		end
	end
	name = (name or ""):match("^%s*(.-)%s*$")
	if name == "" then name = "Imported" end
	local base, n = name, 1
	while NS.FindProfile(name) do n = n + 1; name = base .. " " .. n end
	NS.db.profiles[name] = { layout = layout, pins = type(data.pins) == "table" and data.pins or { bags = true, map = true } }
	NS.SwitchProfile(name)
	return true, name
end

function NS.NextProfile()
	local names = NS.ProfileNames()
	if #names < 2 then NS.Print("There is only one profile. Create more in /farsight layout.") return end
	local idx = 1
	for i, n in ipairs(names) do if n == NS.db.profile then idx = i end end
	NS.SwitchProfile(names[idx % #names + 1])
end

-- Where you are: "instance" (dungeon, raid, battleground), "rest" (city or inn), "world" (everything else).
function NS.ProfileContext()
	if IsInInstance and IsInInstance() then return "instance" end
	if IsResting and IsResting() then return "rest" end
	return "world"
end

function NS.CheckAutoProfile()
	local db = NS.db
	if not db or NS.passive or not db.enabled then return end
	local want = pendingProfile or db.autoProfile[NS.ProfileContext()]
	if want and NS.FindProfile(want) and NS.FindProfile(want) ~= db.profile then NS.SwitchProfile(want) end
end

-- ---------------------------------------------------------------- events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("DISPLAY_SIZE_CHANGED")
f:RegisterEvent("UI_SCALE_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_UPDATE_RESTING")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON then
			FarsightDB = FarsightDB or {}
			local db = FarsightDB
			for k, v in pairs(NS.DEFAULTS) do
				if type(v) == "table" then
					if type(db[k]) ~= "table" then db[k] = {} end
					if k == "pins" or k == "minimap" then
						for k2, v2 in pairs(v) do if db[k][k2] == nil then db[k][k2] = v2 end end
					end
				elseif db[k] == nil then
					db[k] = v
				end
			end
			db.v, db.hud = 3, "all"   -- 0.1.0 could break the UI with this option
			-- "Auto-calibrate" pressed in the launcher: back to automatic values, once per press
			local m = FarsightMonitors
			if type(m) == "table" and m.calibrate and db.calibrated ~= m.calibrate then
				db.calibrated = m.calibrate
				db.enabled, db.viewport, db.manual = true, true, false
				db.gameScreen, db.gameRect, db.uiScale, db.hud = nil, nil, nil, "all"
				NS.calibratedNow = true
			end
			NS.db = db
			if type(db.profile) ~= "string" or db.profile == "" then db.profile = "Default" end
			if not db.profiles[db.profile] then NS.SaveProfile() end
			if isLoaded("MultiMonViewport") then NS.passive = true end
			-- before MoveAny reads its saved positions: make it let go of the windows that live in zones
			if not NS.passive and NS.ReleaseAssignedFromMoveAny then pcall(NS.ReleaseAssignedFromMoveAny) end
			if NS.InitPins then NS.InitPins() end
		elseif NS.db then
			if NS.OnOtherAddonLoaded then NS.OnOtherAddonLoaded(arg1) end
		end
		return
	end
	if not NS.db then return end
	if event == "PLAYER_LOGIN" then
		if NS.CreateMinimapButton then NS.CreateMinimapButton() end
		if NS.InitInfoPanel then NS.InitInfoPanel() end
		if NS.InitQuestPanel then NS.InitQuestPanel() end
		if NS.calibratedNow and not NS.passive then
			NS.Print("Auto-calibrated by the launcher: game area, UI scale and UI placement are back to automatic.")
		end
		if NS.passive then
			NS.Print("MultiMonViewport is also enabled, so Farsight stays passive. Disable MultiMonViewport in the AddOns list to use Farsight.")
		elseif not FarsightMonitors and not NS.db.manual then
			NS.Print("No screen layout yet. Start WoW with the Farsight Launcher, or type /farsight to enter the screens by hand.")
		elseif not NS.IsSpanned() then
			NS.Print("The WoW window is not stretched across your screens, so Farsight is paused. Start WoW with the Farsight Launcher.")
		elseif not NS.db.welcomed and not NS.db.introShown then
			C_Timer.After(3, function() if NS.ShowWelcome then NS.ShowWelcome(true) end end)
		end
		return
	end
	if event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED_NEW_AREA" then
		C_Timer.After(0.5, NS.CheckAutoProfile)
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
		C_Timer.After(1, NS.CheckAutoProfile)
	end
	if event == "PLAYER_REGEN_ENABLED" then
		if NS.OnLeaveCombat then NS.OnLeaveCombat() end
		if not pending then return end
	end
	NS.ApplySoon(0.1)
end)

-- ---------------------------------------------------------------- key bindings (Options > Keybindings > AddOns)
BINDING_HEADER_FARSIGHT = "Farsight"
BINDING_NAME_FARSIGHT_LAYOUT = "Open or close layout mode"
BINDING_NAME_FARSIGHT_NEXTPROFILE = "Switch to the next layout profile"
BINDING_NAME_FARSIGHT_INFO = "Show or hide the info panel"
BINDING_NAME_FARSIGHT_OPTIONS = "Open the options window"

function Farsight_Binding(what)
	if not NS.db then return end
	if what == "layout" then NS.ToggleLayout()
	elseif what == "next" then NS.NextProfile()
	elseif what == "info" then if NS.ToggleInfoPanel then NS.ToggleInfoPanel() end
	elseif what == "options" then NS.ToggleOptions() end
end

-- ---------------------------------------------------------------- slash
SLASH_FARSIGHT1 = "/farsight"
SLASH_FARSIGHT2 = "/far"
SlashCmdList.FARSIGHT = function(input)
	local cmd = (input or ""):lower():match("^%s*(%S*)")
	local db = NS.db
	if cmd == "" or cmd == "options" then
		NS.ToggleOptions()
	elseif cmd == "layout" then
		NS.ToggleLayout()
	elseif cmd == "on" or cmd == "off" then
		db.enabled = (cmd == "on")
		NS.Print(db.enabled and "enabled" or "disabled (the 3D world fills the whole window again)")
		NS.ApplyAll()
	elseif cmd == "auto" or cmd == "calibrate" then
		NS.Calibrate()
	elseif cmd == "debug" then
		db.debug = not db.debug
		NS.Print("debug " .. (db.debug and "on" or "off"))
	elseif cmd == "profile" or cmd == "profiles" then
		local arg = (input or ""):match("^%s*%S+%s+(.-)%s*$")
		if arg and arg ~= "" then
			if not NS.FindProfile(arg) then NS.Print("No profile called " .. arg .. ". Create it in /farsight layout.")
			else NS.SwitchProfile(arg) end
		else
			NS.Print("Profiles (active: " .. db.profile .. "): " .. table.concat(NS.ProfileNames(), ", ") .. ".  Switch with /farsight profile <name>")
		end
	elseif cmd == "welcome" then
		if NS.ShowWelcome then NS.ShowWelcome() end
	elseif cmd == "next" then
		NS.NextProfile()
	elseif cmd == "quests" then
		if NS.ToggleQuestPanel then NS.ToggleQuestPanel() end
	elseif cmd == "info" then
		if NS.ToggleInfoPanel then NS.ToggleInfoPanel() end
	elseif cmd == "bars" then
		if NS.DebugBars then NS.DebugBars() end
	elseif cmd == "status" then
		local w, h = NS.WindowPixels()
		local rw, rh = NS.RootSize()
		NS.Print(("layout %s x %s px, window shape %.3f (expected %.3f), stretched: %s, active: %s"):format(
			tostring(w), tostring(h), rw / rh, (w and h and h > 0) and (w / h) or 0, tostring(NS.IsSpanned()), tostring(NS.Active())))
		for _, s in ipairs((NS.GetScreens())) do
			NS.Print(("  screen %s %s: %d,%d %dx%d px%s"):format(tostring(s.id), s.name, s.px.x, s.px.y, s.px.w, s.px.h,
				s.id == NS.GameScreenId() and "  (game screen)" or ""))
		end
	elseif cmd == "reset" then
		db.layout = {}
		db.gameRect, db.gameScreen, db.uiScale, db.hud = nil, nil, nil, "all"
		NS.Print("layout reset")
		NS.ApplyAll()
	else
		print("  /farsight  -  open the options window")
		print("  /farsight layout  -  choose which windows go on which screen")
		print("  /farsight on | off  -  enable / disable")
		print("  /farsight auto  -  auto-calibrate: game area, UI scale and UI placement back to automatic")
		print("  /farsight status  -  show what Farsight knows about your screens")
		print("  /farsight profile <name>  -  switch layout profile (no name: list them)")
		print("  /farsight next  -  switch to the next layout profile")
		print("  /farsight welcome  -  show the first-start guide again")
		print("  /farsight info  -  show or hide the info panel")
		print("  /farsight quests  -  show or hide the quest panel")
		print("  /farsight reset  -  clear the layout")
		print("  /farsight debug  -  print what the addon does to chat")
	end
end
