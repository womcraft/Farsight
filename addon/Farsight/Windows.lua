-- Farsight: window catalog and the code that places windows in zones.
local ADDON, NS = ...

-- ---------------------------------------------------------------- catalog
-- frame = global frame name. open = how to open it (optional). special = handled by dedicated code.
local CATALOG = {
	{ key = "map",  label = "World Map", frame = "WorldMapFrame", special = "map",
		open = function() if ToggleWorldMap then ToggleWorldMap() end end },
	{ key = "bags", label = "Bags", special = "bags",
		open = function() if OpenAllBags then OpenAllBags() elseif OpenBackpack then OpenBackpack() end end },
	{ key = "FarsightInfoPanel", label = "Farsight info panel (clock, XP, gold, bags...)", special = "own",
		open = function() if NS.ShowInfoPanel then NS.ShowInfoPanel(true) end end },
	{ key = "FarsightQuestPanel", label = "Farsight quest panel (all quests, in columns that fill the zone)", special = "own",
		open = function() if NS.ShowQuestPanel then NS.ShowQuestPanel(true) end end },
	{ key = "CharacterFrame", label = "Character",
		open = function() if ToggleCharacter then ToggleCharacter("PaperDollFrame") end end },
	{ key = "PlayerSpellsFrame", label = "Spellbook & Talents" },
	{ key = "SpellBookFrame", label = "Spellbook" },
	{ key = "ProfessionsBookFrame", label = "Professions book" },
	{ key = "ProfessionsFrame", label = "Profession window" },
	{ key = "FriendsFrame", label = "Social (friends, who, raid)" },
	{ key = "CommunitiesFrame", label = "Guild & Communities" },
	{ key = "QuestFrame", label = "Quest dialog" },
	{ key = "GossipFrame", label = "NPC dialog" },
	{ key = "MerchantFrame", label = "Vendor" },
	{ key = "MailFrame", label = "Mail" },
	{ key = "BankFrame", label = "Bank" },
	{ key = "AuctionHouseFrame", label = "Auction House" },
	{ key = "TradeFrame", label = "Trade" },
	{ key = "LootFrame", label = "Loot" },
	{ key = "ClassTrainerFrame", label = "Trainer" },
	{ key = "CollectionsJournal", label = "Collections" },
	{ key = "EncounterJournal", label = "Adventure Guide" },
	{ key = "PVEFrame", label = "Group Finder" },
	{ key = "AchievementFrame", label = "Achievements" },
	{ key = "InspectFrame", label = "Inspect" },
	{ key = "DressUpFrame", label = "Dressing room" },
	{ key = "MacroFrame", label = "Macros" },
	{ key = "FlightMapFrame", label = "Flight map" },
	{ key = "TaxiFrame", label = "Flight map (classic)" },
	{ key = "ItemTextFrame", label = "Books & letters" },
	{ key = "CalendarFrame", label = "Calendar" },
	{ key = "AddonList", label = "AddOn list" },
	-- Parts of the normal interface. They are always on screen, so they are listed only if they exist.
	{ key = "MainActionBar", label = "Action bar 1 (main)", hud = true },
	{ key = "MainMenuBar", label = "Action bar 1 (main)", hud = true },
	{ key = "MultiBarBottomLeft", label = "Action bar 2", hud = true },
	{ key = "MultiBarBottomRight", label = "Action bar 3", hud = true },
	{ key = "MultiBarRight", label = "Action bar 4", hud = true },
	{ key = "MultiBarLeft", label = "Action bar 5", hud = true },
	{ key = "MultiBar5", label = "Action bar 6", hud = true },
	{ key = "MultiBar6", label = "Action bar 7", hud = true },
	{ key = "MultiBar7", label = "Action bar 8", hud = true },
	{ key = "StanceBar", label = "Stance bar", hud = true },
	{ key = "PetActionBar", label = "Pet bar", hud = true },
	{ key = "MicroMenuContainer", label = "Micro menu", hud = true },
	{ key = "BagsBar", label = "Bag bar", hud = true },
	{ key = "PlayerFrame", label = "Player frame", hud = true },
	{ key = "TargetFrame", label = "Target frame", hud = true },
	{ key = "FocusFrame", label = "Focus frame", hud = true },
	{ key = "PetFrame", label = "Pet frame", hud = true },
	{ key = "PartyFrame", label = "Party frames", hud = true },
	{ key = "CompactRaidFrameContainer", label = "Raid frames", hud = true },
	{ key = "MinimapCluster", label = "Minimap (scaled up to fill the zone)", hud = true },
	{ key = "ObjectiveTrackerFrame", label = "Quest tracker (WoW's own)", hud = true, align = "top" },
	{ key = "Questie_BaseFrame", label = "Quest tracker (Questie)", hud = true, align = "top" },
	{ key = "BuffFrame", label = "Buffs", hud = true },
	{ key = "DebuffFrame", label = "Debuffs", hud = true },
	{ key = "PlayerCastingBarFrame", label = "Cast bar", hud = true },
}
local BYKEY = {}
for _, e in ipairs(CATALOG) do BYKEY[e.key] = e end

-- Chat windows: every chat tab (General, Combat Log, your own tabs) is its own window "ChatFrameN".
local function chatEntry(i)
	local fr = _G["ChatFrame" .. i]
	if not fr or not GetChatWindowInfo then return nil end
	local name = GetChatWindowInfo(i)
	if type(name) ~= "string" or name == "" then
		if i ~= 1 then return nil end
		name = "General"
	end
	if i ~= 1 and not fr.isDocked and not fr:IsShown() then return nil end   -- closed tab
	return { key = "ChatFrame" .. i, label = "Chat: " .. name, chat = i }
end

function NS.WindowEntry(key)
	if BYKEY[key] then return BYKEY[key] end
	local ci = type(key) == "string" and tonumber(key:match("^ChatFrame(%d+)$"))
	if ci then return chatEntry(ci) or { key = key, label = "Chat window " .. ci, chat = ci } end
	if key and NS.db.custom[key] then return { key = key, label = NS.db.custom[key], custom = true } end
end

function NS.WindowLabel(key)
	local e = NS.WindowEntry(key)
	return e and e.label or tostring(key)
end

-- Windows to offer in the zone menu: built-in ones first, then the ones added with the mouse.
function NS.WindowList()
	local out = {}
	local hudHeader = false
	for _, e in ipairs(CATALOG) do
		if e.hud then
			local fr = _G[e.key]
			if type(fr) == "table" and fr.SetPoint then
				if not hudHeader then
					hudHeader = true
					out[#out + 1] = { header = "Action bars, unit frames and other interface parts" }
				end
				out[#out + 1] = e
			end
		else
			out[#out + 1] = e
		end
		if e.key == "bags" then   -- chat tabs right after map and bags
			for i = 1, NUM_CHAT_WINDOWS or 10 do
				local c = chatEntry(i)
				if c then out[#out + 1] = c end
			end
		end
	end
	local custom = {}
	for name, label in pairs(NS.db.custom) do custom[#custom + 1] = { key = name, label = label, custom = true } end
	table.sort(custom, function(a, b) return a.label < b.label end)
	if #custom > 0 then out[#out + 1] = { header = "Windows you added" } end
	for _, e in ipairs(custom) do out[#out + 1] = e end
	-- Windows of other addons that are open right now (any named frame an addon put on UIParent)
	local found = NS.AddonFrames()
	if #found > 0 then out[#out + 1] = { header = "Other addons (open now)" } end
	for _, e in ipairs(found) do out[#out + 1] = e end
	return out
end

-- Named frames that other addons created directly on UIParent and that are shown now. The addon that made a
-- frame is the one that "tainted" its global name, which WoW can tell us.
function NS.AddonFrames()
	local out = {}
	if not issecurevariable then return out end
	local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
	for _, fr in ipairs({ UIParent:GetChildren() }) do
		local ok, name = pcall(fr.GetName, fr)
		-- menus, tooltips, pop-ups and minimap buttons are not windows anyone wants in a zone
		local helper = type(name) == "string" and (name:find("Menu") or name:find("[Dd]rop[Dd]own") or name:find("Tooltip")
			or name:find("Popup") or name:find("^LibDBIcon") or name:find("Button$") or name:find("Sizer"))
		if ok and not helper and type(name) == "string" and _G[name] == fr and not BYKEY[name] and not NS.db.custom[name]
			and not name:match("^Farsight") and not (fr.IsForbidden and fr:IsForbidden()) and fr:IsShown() then
			local secure, owner = issecurevariable(_G, name)
			local w, h = fr:GetWidth() or 0, fr:GetHeight() or 0
			local sc = fr:GetScale() or 1
			if not secure and owner and owner ~= ADDON and w * sc >= 30 and h * sc >= 20
				and not (w * sc >= uw * 0.9 and h * sc >= uh * 0.9) then
				local pretty = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
				out[#out + 1] = { key = name, label = owner .. ": " .. pretty, addonFrame = true }
			end
		end
	end
	table.sort(out, function(a, b) return a.label < b.label end)
	return out
end

local function bagFrames()
	local t = {}
	if ContainerFrameCombinedBags then t[#t + 1] = ContainerFrameCombinedBags end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local cf = _G["ContainerFrame" .. i]
		if cf then t[#t + 1] = cf end
	end
	return t
end
NS.BagFrames = bagFrames

-- Frames that belong to a window key (may be empty if the window is not loaded yet).
function NS.WindowFrames(key)
	local e = NS.WindowEntry(key)
	if not e then return {} end
	if e.special == "bags" then return bagFrames() end
	local fr = _G[e.frame or e.key]
	if type(fr) == "table" and fr.GetObjectType and fr.SetPoint then return { fr } end
	return {}
end

function NS.OpenWindow(key)
	if InCombatLockdown() then return end
	local e = NS.WindowEntry(key)
	if not e then return end
	if e.open then pcall(e.open) return end
	local fr = NS.WindowFrames(key)[1]
	if fr and not fr:IsShown() then
		if not pcall(ShowUIPanel, fr) or not fr:IsShown() then pcall(fr.Show, fr) end
	end
end

-- ---------------------------------------------------------------- placing
local PAD = 6            -- gap between a window and its zone edge, in root units
local hooked = {}        -- [frame] = true
local busy = {}          -- [frame] = true while we are moving it ourselves
local burst = {}         -- [frame] = { t = time, n = count }: stops endless tug-of-war with other addons
local original = {}      -- [frame] = { scale, w, h }
local queued = {}        -- [frame] = true: reposition scheduled
local combatPending = false

local function uiOrigin()
	-- UIParent's top-left corner in root units (it moves when the HUD area is limited to one screen)
	local _, rh = NS.RootSize()
	local s = UIParent:GetEffectiveScale()
	local left, top = UIParent:GetLeft() or 0, UIParent:GetTop() or (rh / s)
	return left * s, rh - top * s
end

local function near(a, b, tol) return a and b and math.abs(a - b) <= (tol or 1) end

-- MoveAny remembers a position and a scale for windows you moved with it, and puts them back whenever
-- anything else changes them. It offers no way to tell it otherwise, so for windows that live in a zone
-- its saved values are taken out of its settings (and kept in ours, to put back when the window leaves
-- the zone). MoveAny reads its settings when the UI loads, so a change needs one /reload to take effect.
local function maFrames()
	local tab = type(MATAB) == "table" and type(MATABPC) == "table" and type(MATAB.PROFILES) == "table"
		and MATAB.PROFILES[MATABPC.CURRENTPROFILE]
	if type(tab) == "table" and type(tab.FRAMES) == "table" then return tab.FRAMES end
end

local function frameNames(key)
	local e = NS.WindowEntry(key)
	if e and e.special == "bags" then
		local t = { "ContainerFrameCombinedBags" }
		for i = 1, NUM_CONTAINER_FRAMES or 13 do t[#t + 1] = "ContainerFrame" .. i end
		return t
	end
	return { (e and e.frame) or key }
end

local function maRelease(key)
	local fr = maFrames()
	if not fr then return false end
	local removed = false
	for _, name in ipairs(frameNames(key)) do
		local p = type(fr.POINTS) == "table" and fr.POINTS[name]
		local z = type(fr.SIZES) == "table" and fr.SIZES[name]
		local bk = {}
		if type(p) == "table" and p.AN then
			bk.point = { AN = p.AN, RE = p.RE, PX = p.PX, PY = p.PY }
			fr.POINTS[name] = {}
		end
		if type(z) == "table" and z.SCALE then bk.scale = z.SCALE; z.SCALE = nil end
		if bk.point or bk.scale then
			NS.db.maBackup[key] = NS.db.maBackup[key] or {}
			NS.db.maBackup[key][name] = bk
			removed = true
		end
	end
	return removed
end

local function maRestore(key)
	local saved = NS.db.maBackup[key]
	NS.db.maBackup[key] = nil
	local fr = maFrames()
	if not fr or type(saved) ~= "table" then return end
	for name, bk in pairs(saved) do
		if bk.point and type(fr.POINTS) == "table" then fr.POINTS[name] = bk.point end
		if bk.scale and type(fr.SIZES) == "table" then
			fr.SIZES[name] = fr.SIZES[name] or {}
			fr.SIZES[name].SCALE = bk.scale
		end
	end
end

-- Calls fn(windowKey) for every window that sits in a zone of the given layout.
local function eachKey(layout, fn)
	if type(layout) ~= "table" then return end
	local function walk(n)
		if type(n) ~= "table" then return end
		if n.dir then walk(n.a); walk(n.b) else
			if n.win then fn(n.win) end
			if type(n.more) == "table" then for _, k in ipairs(n.more) do fn(k) end end
		end
	end
	for _, screen in pairs(layout) do
		if type(screen) == "table" then
			if screen.tree == nil and type(screen.zones) == "table" then   -- saved by an older version
				for _, z in pairs(screen.zones) do if type(z) == "table" and z.win then fn(z.win) end end
			end
			walk(screen.tree)
		end
	end
	if type(layout.float) == "table" then
		for key, d in pairs(layout.float) do if type(d) == "table" and d.win == key then fn(key) end end
	end
end

-- Every window that sits in a zone in any profile.
local function keysEverywhere()
	local set = {}
	local function add(k) set[k] = true end
	eachKey(NS.db.layout, add)
	for _, p in pairs(NS.db.profiles) do if type(p) == "table" then eachKey(p.layout, add) end end
	return set
end

function NS.ReleaseAssignedFromMoveAny()
	for key in pairs(keysEverywhere()) do maRelease(key) end
end

-- Edit Mode replaces SetScale / SetPoint / ClearAllPoints on its own frames (action bars, unit frames, ...) with
-- versions that react to every change: the vertical action bars get their scale and place reset at once.
-- The plain functions are kept as ...Base; use those so the game does not answer our change.
local function setScale(frame, sc) (frame.SetScaleBase or frame.SetScale)(frame, sc) end

local function setTopLeft(frame, ax, ay)
	(frame.ClearAllPointsBase or frame.ClearAllPoints)(frame);
	(frame.SetPointBase or frame.SetPoint)(frame, "TOPLEFT", UIParent, "TOPLEFT", ax, ay)
end

-- Some windows are bigger than what they draw (empty space below a bag, for example). Returns how much
-- empty space there is on each side (left, top, right, bottom) in the window's own units, measured from
-- what is actually shown inside it.
local insetSeen = {}
local function visualInsets(frame)
	local il, it, ir, ib = 0, 0, 0, 0
	pcall(function()
		local es = frame:GetEffectiveScale()
		local fl, fr, ft, fb = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
		if not (fl and fr and ft and fb) then return end
		fl, fr, ft, fb = fl * es, fr * es, ft * es, fb * es
		local l, r, t, b
		local function add(o)
			if not o.IsShown or not o:IsShown() then return end
			if o.GetAlpha and o:GetAlpha() == 0 then return end
			if o.GetTexture and not o:GetTexture() and not (o.GetAtlas and o:GetAtlas()) then return end   -- empty texture
			local s = (o.GetEffectiveScale and o:GetEffectiveScale()) or es
			local ol, orr, ot, ob = o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom()
			if not (ol and orr and ot and ob) then return end
			ol, orr, ot, ob = ol * s, orr * s, ot * s, ob * s
			if orr - ol < 1 or ot - ob < 1 then return end
			l = math.min(l or ol, ol); r = math.max(r or orr, orr)
			t = math.max(t or ot, ot); b = math.min(b or ob, ob)
		end
		for _, o in ipairs({ frame:GetRegions() }) do add(o) end
		for _, o in ipairs({ frame:GetChildren() }) do add(o) end
		if not l then return end
		local a, c, d, e = math.max(0, l - fl), math.max(0, ft - t), math.max(0, fr - r), math.max(0, b - fb)
		-- only trust it if a sensible part of the window remains
		if (fr - fl) - a - d < 0.4 * (fr - fl) or (ft - fb) - c - e < 0.4 * (ft - fb) then return end
		il, it, ir, ib = a / es, c / es, d / es, e / es
	end)
	if not insetSeen[frame] and (il + it + ir + ib) > 2 then
		insetSeen[frame] = true
		NS.Debug((frame:GetName() or "?") .. " draws less than its size: empty left/top/right/bottom =",
			("%.0f/%.0f/%.0f/%.0f of %.0fx%.0f"):format(il, it, ir, ib, frame:GetWidth(), frame:GetHeight()))
	end
	return il, it, ir, ib
end

-- Returns ok, changed (changed = something actually had to be moved or resized).
-- align = "top": the window keeps to the top of its zone (quest trackers grow and shrink downwards).
local function placeFrame(frame, rect, fit, pad, align)
	if InCombatLockdown() and frame:IsProtected() then combatPending = true return false end
	local _, rh = NS.RootSize()
	if not original[frame] then
		original[frame] = { scale = frame:GetScale(), w = frame:GetWidth(), h = frame:GetHeight() }
		if frame:GetNumPoints() > 0 then original[frame].point = { frame:GetPoint(1) } end
	end
	pad = pad or PAD
	local x, y, w, h = rect.x + pad, rect.y + pad, rect.w - 2 * pad, rect.h - 2 * pad
	if w < 1 or h < 1 then return false end   -- root units can be small (a 5-unit-wide bar is ~20 pixels)
	local parentScale = frame:GetEffectiveScale() / frame:GetScale()
	local changed = false
	local il, it, ir, ib = 0, 0, 0, 0
	if fit ~= "stretch" and fit ~= "none" then il, it, ir, ib = visualInsets(frame) end
	busy[frame] = true
	local ok, err = pcall(function()
		if fit == "stretch" then
			local es = frame:GetEffectiveScale()
			if not near(frame:GetWidth() * es, w) or not near(frame:GetHeight() * es, h) then
				frame:SetSize(w / es, h / es)
				changed = true
			end
		elseif fit ~= "none" then
			local fw, fh = frame:GetWidth() - il - ir, frame:GetHeight() - it - ib
			if fw and fh and fw > 0 and fh > 0 then
				local sc = math.min(w / (fw * parentScale), h / (fh * parentScale))
				sc = math.max(0.3, math.min(4, sc))
				if not near(frame:GetScale(), sc, 0.003) then setScale(frame, sc); changed = true end
			end
		end
		local es = frame:GetEffectiveScale()
		local fw, fh = (frame:GetWidth() - il - ir) * es, (frame:GetHeight() - it - ib) * es
		-- center what the window draws in its zone
		local px, py = x + (w - fw) / 2 - il * es, y + (h - fh) / 2 - it * es
		if align == "top" then py = y - it * es end
		local left, top = frame:GetLeft(), frame:GetTop()
		if left and top and near(left * es, px, 1.5) and near(rh - top * es, py, 1.5) then return end
		local ox, oy = uiOrigin()
		setTopLeft(frame, (px - ox) / es, -(py - oy) / es)
		changed = true
	end)
	busy[frame] = nil
	if not ok then NS.Debug("could not place", frame:GetName() or "?", err) end
	return ok, changed
end

-- Used for pinned windows that have no zone: put them in the middle of a rectangle without resizing.
function NS.PlaceInRect(frame, rect) return placeFrame(frame, rect, "none") end

local function restoreFrame(frame)
	local o = original[frame]
	if not o then return end
	if InCombatLockdown() and frame:IsProtected() then return end
	busy[frame] = true
	pcall(function()
		setScale(frame, o.scale)
		if o.resized then frame:SetSize(o.w, o.h) end
		local pt = o.point
		if pt and pt[1] and (pt[2] == nil or pt[2] == UIParent) then   -- back to where it was
			frame:ClearAllPoints()
			frame:SetPoint(pt[1], UIParent, pt[3] or pt[1], pt[4] or 0, pt[5] or 0)
		end
	end)
	busy[frame] = nil
	original[frame] = nil
end

-- Lays out several bag frames inside one zone: columns from the right, bottom-up, one common scale.
local function placeBags(frames, rect)
	local shown = {}
	for _, cf in ipairs(frames) do if cf:IsShown() then shown[#shown + 1] = cf end end
	if #shown == 0 then return end
	if #shown == 1 then local _, ch = placeFrame(shown[1], rect, "fit") return ch end
	if InCombatLockdown() then combatPending = true return end
	local changed = false
	local _, rh = NS.RootSize()
	local x, y, w, h = rect.x + PAD, rect.y + PAD, rect.w - 2 * PAD, rect.h - 2 * PAD
	local parentScale = shown[1]:GetEffectiveScale() / shown[1]:GetScale()
	local chosen, plan
	for step = 0, 44 do
		local sc = 4 * 0.94 ^ step   -- from 4x down to about 0.26x: the biggest scale where every bag fits
		local es = sc * parentScale
		local cx, cy, colW, fits, p = x + w, y + h, 0, true, {}
		for _, cf in ipairs(shown) do
			local fw, fh = cf:GetWidth() * es, cf:GetHeight() * es
			if cy - fh < y - 0.5 then cx, cy, colW = cx - colW - 2, y + h, 0 end   -- next column
			if fh > h + 0.5 or cx - fw < x - 0.5 then fits = false break end
			p[#p + 1] = { cf, cx - fw, cy - fh }
			cy = cy - fh - 2
			if fw > colW then colW = fw end
		end
		if fits then chosen, plan = sc, p break end
	end
	if not plan then return end
	-- the bags are packed against the bottom right corner: move the whole block to the middle of the zone
	local minX, minY = x + w, y + h
	for _, item in ipairs(plan) do
		if item[2] < minX then minX = item[2] end
		if item[3] < minY then minY = item[3] end
	end
	local dx, dy = (minX - x) / 2, (minY - y) / 2
	for _, item in ipairs(plan) do item[2], item[3] = item[2] - dx, item[3] - dy end
	local ox, oy = uiOrigin()
	for _, item in ipairs(plan) do
		local cf, px, py = item[1], item[2], item[3]
		if not original[cf] then original[cf] = { scale = cf:GetScale(), w = cf:GetWidth(), h = cf:GetHeight() } end
		busy[cf] = true
		pcall(function()
			if not near(cf:GetScale(), chosen, 0.003) then setScale(cf, chosen); changed = true end
			local es = cf:GetEffectiveScale()
			local left, top = cf:GetLeft(), cf:GetTop()
			if left and top and near(left * es, px, 1.5) and near(rh - top * es, py, 1.5) then return end
			setTopLeft(cf, (px - ox) / es, -(py - oy) / es)
			changed = true
		end)
		busy[cf] = nil
	end
	return changed
end

local function fitFor(key, zoneData)
	if zoneData.fit then return zoneData.fit end
	-- OpenMap makes the map resizable, so it can fill the zone; Blizzard's own map keeps its shape
	if key == "map" and NS.IsLoaded("OpenMap") then return "stretch" end
	if type(key) == "string" and key:match("^ChatFrame%d+$") then return "stretch" end   -- chat is made to be resized
	if key == "FarsightInfoPanel" or key == "FarsightQuestPanel" then return "stretch" end   -- it lays out its own text for any size
	return "fit"
end
NS.FitFor = fitFor

-- A zone can hold several bars. They get one common scale and are placed edge to edge in the middle of the
-- zone: on top of each other or side by side, whichever makes them larger.
local PACKABLE = {
	MainActionBar = true, MainMenuBar = true, MultiBarBottomLeft = true, MultiBarBottomRight = true,
	MultiBarRight = true, MultiBarLeft = true, MultiBar5 = true, MultiBar6 = true, MultiBar7 = true,
	StanceBar = true, PetActionBar = true, MicroMenuContainer = true, BagsBar = true,
}
function NS.IsBar(key) return PACKABLE[key] or false end

-- Returns the rectangle the bar `key` should fill in its zone, or nil if it is alone there.
local function packRect(zone, key)
	local keys = NS.ZoneKeys(zone.data)
	if #keys < 2 then return nil end
	local list, mine = {}, nil
	for _, k in ipairs(keys) do
		local fr = NS.WindowFrames(k)[1]
		if fr then
			local il, it, ir, ib = visualInsets(fr)
			local w, h = fr:GetWidth() - il - ir, fr:GetHeight() - it - ib
			if w and h and w > 1 and h > 1 then
				list[#list + 1] = { w = w, h = h }
				if k == key then mine = #list end
			end
		end
	end
	if not mine or #list < 2 then return nil end
	local r = zone.rect
	local X, Y, W, H = r.x + PAD, r.y + PAD, r.w - 2 * PAD, r.h - 2 * PAD
	local sumW, sumH, maxW, maxH = 0, 0, 0, 0
	for _, f in ipairs(list) do
		sumW, sumH = sumW + f.w, sumH + f.h
		maxW, maxH = math.max(maxW, f.w), math.max(maxH, f.h)
	end
	local sCol, sRow = math.min(W / maxW, H / sumH), math.min(W / sumW, H / maxH)
	local before = 0
	if sCol >= sRow then   -- on top of each other
		for i = 1, mine - 1 do before = before + list[i].h end
		local f, s = list[mine], sCol
		return { x = X + (W - f.w * s) / 2, y = Y + (H - sumH * s) / 2 + before * s, w = f.w * s, h = f.h * s }
	end
	for i = 1, mine - 1 do before = before + list[i].w end
	local f, s = list[mine], sRow
	return { x = X + (W - sumW * s) / 2 + before * s, y = Y + (H - f.h * s) / 2, w = f.w * s, h = f.h * s }
end

-- Places every frame of one window key, if it is assigned to a zone.
function NS.ApplyWindow(key)
	if not NS.Active() then return end
	local zone = NS.FindZoneOf(key)
	if not zone then return end
	local e = NS.WindowEntry(key)
	local frames = NS.WindowFrames(key)
	if #frames == 0 then return end
	if e and e.special == "bags" then
		return placeBags(frames, zone.rect)
	end
	local frame = frames[1]
	if not frame:IsShown() then return end
	if key == "map" and frame.IsMaximized and frame:IsMaximized() then return end
	local fit = fitFor(key, zone.data)
	if zone.float then
		-- a free window: its own place, and its own size if you changed it with the mouse wheel
		fit = "none"
		local sc = zone.data.scale
		if sc and math.abs(frame:GetScale() - sc) > 0.003 and not (InCombatLockdown() and frame:IsProtected()) then
			if not original[frame] then
				original[frame] = { scale = frame:GetScale(), w = frame:GetWidth(), h = frame:GetHeight() }
				if frame:GetNumPoints() > 0 then original[frame].point = { frame:GetPoint(1) } end
			end
			busy[frame] = true
			pcall(setScale, frame, sc)
			busy[frame] = nil
		end
	end
	if fit == "stretch" then
		if not original[frame] then
			original[frame] = { scale = frame:GetScale(), w = frame:GetWidth(), h = frame:GetHeight() }
		end
		original[frame].resized = true
	end
	local rect = zone.rect
	if e and e.chat then
		-- the tabs sit above the chat window and the typing box below it: keep room for both
		local es = frame:GetEffectiveScale()
		local top, bottom = 26 * es, 36 * es
		rect = { x = rect.x, y = rect.y + top, w = rect.w, h = math.max(40, rect.h - top - bottom) }
	end
	local pad
	if not zone.float then
		local pr = packRect(zone, key)
		if pr then rect, pad, fit = pr, 0, "fit" end
	end
	local _, changed = placeFrame(frame, rect, fit, pad, e and e.align)
	if changed and key == "map" and fit == "stretch" then
		local sc = frame.ScrollContainer
		if sc and sc.OnCanvasSizeChanged then pcall(sc.OnCanvasSizeChanged, sc) end
	end
	return changed
end

local keyOfFrame = {}   -- [frame] = window key

local function describe(frame)
	local es = frame:GetEffectiveScale()
	local _, rh = NS.RootSize()
	return ("scale %.3f, at %.0f,%.0f size %.0fx%.0f"):format(frame:GetScale(), (frame:GetLeft() or 0) * es,
		rh - (frame:GetTop() or 0) * es, frame:GetWidth() * es, frame:GetHeight() * es)
end

-- Counts corrections. If another addon keeps undoing ours, pause instead of fighting every frame.
local function countCorrection(frame, key)
	local now = GetTime()
	local bb = burst[frame]
	if not bb or now - bb.t > 2 then bb = { t = now, n = 0 }; burst[frame] = bb end
	bb.n = bb.n + 1
	if bb.n > 12 then
		bb.pause = now + 3
		NS.Debug("pausing", frame:GetName() or key, "for 3 s (something else keeps changing it):", describe(frame))
		C_Timer.After(3.1, function() if keyOfFrame[frame] then NS.ApplyWindow(keyOfFrame[frame]) end end)
	end
end

local applying = false

local function later(frame)
	if busy[frame] then return end
	local key = keyOfFrame[frame]
	if not key or not NS.Active() or not NS.FindZoneOf(key) then return end
	local b = burst[frame]
	if b and b.pause then
		if GetTime() < b.pause then return end
		burst[frame] = nil
	end
	-- Right away, in the same frame: otherwise a window that the game just opened or moved is drawn in
	-- the game's place for one frame before it jumps to its zone (the map flickering on the game screen).
	local editMode = frame.SetPointBase ~= nil   -- Edit Mode lays these out again often; that is not a fight
	if not applying and not (InCombatLockdown() and frame:IsProtected()) then
		applying = true
		local ok, changed = pcall(NS.ApplyWindow, key)
		applying = false
		if ok and changed and not editMode then countCorrection(frame, key) end
		if not ok then NS.Debug("could not place", key, changed) end
	end
	-- and once more on the next frame, when the game has finished whatever it was doing
	if queued[frame] then return end
	queued[frame] = true
	C_Timer.After(0, function()
		queued[frame] = nil
		if NS.ApplyWindow(key) and not editMode then countCorrection(frame, key) end
	end)
end

local function hookFrame(frame, key)
	keyOfFrame[frame] = key
	if hooked[frame] then return end
	hooked[frame] = true
	hooksecurefunc(frame, "SetPoint", later)
	hooksecurefunc(frame, "SetScale", later)
	frame:HookScript("OnShow", function(self) burst[self] = nil; later(self) end)
	if key == "map" then
		for _, m in ipairs({ "Minimize", "Maximize", "SetDisplayState" }) do
			if frame[m] then hooksecurefunc(frame, m, function() later(frame) end) end
		end
	end
end

-- Action bars 2-8 are switched on and off in WoW's options. A bar that is put in a zone is switched on for
-- you, and switched off again when it is no longer in a zone (only bars Farsight switched on itself).
local BAR_SETTING = {
	MultiBarBottomLeft = "PROXY_SHOW_ACTIONBAR_2", MultiBarBottomRight = "PROXY_SHOW_ACTIONBAR_3",
	MultiBarRight = "PROXY_SHOW_ACTIONBAR_4", MultiBarLeft = "PROXY_SHOW_ACTIONBAR_5",
	MultiBar5 = "PROXY_SHOW_ACTIONBAR_6", MultiBar6 = "PROXY_SHOW_ACTIONBAR_7", MultiBar7 = "PROXY_SHOW_ACTIONBAR_8",
}
local barSetAt = {}

function NS.BarSetting(key) return BAR_SETTING[key] end

-- Bars 2-8 are switched with WoW's own SetActionBarToggles (the same call the options window ends in).
-- Going through Settings.SetValue from an addon would leave Farsight's mark ("taint") on the setting, and
-- the action bar code reads it in combat.
local BAR_INDEX = { MultiBarBottomLeft = 1, MultiBarBottomRight = 2, MultiBarRight = 3, MultiBarLeft = 4,
	MultiBar5 = 5, MultiBar6 = 6, MultiBar7 = 7 }

local function barShownSetting(key)
	if not GetActionBarToggles then return nil end
	return (select(BAR_INDEX[key], GetActionBarToggles())) and true or false
end

local function setBar(key, on)
	if not (GetActionBarToggles and SetActionBarToggles and BAR_INDEX[key]) then return false end
	if barShownSetting(key) == on then return true end
	-- the game confirms the change a moment later; do not send it again meanwhile
	if barSetAt[key] and GetTime() - barSetAt[key] < 3 then return true end
	barSetAt[key] = GetTime()
	local t = { GetActionBarToggles() }
	t[BAR_INDEX[key]] = on
	return (pcall(SetActionBarToggles, unpack(t, 1, 7)))
end

local function syncBars(assigned)
	local db = NS.db
	if type(db.barsOn) ~= "table" then db.barsOn = {} end
	if InCombatLockdown() then combatPending = true return end
	for key in pairs(BAR_SETTING) do
		if assigned[key] then
			local cur = barShownSetting(key)
			if cur == false and setBar(key, true) then
				db.barsOn[key] = true
				NS.Debug("switched on " .. key)
			end
		elseif db.barsOn[key] then
			if setBar(key, false) then
				db.barsOn[key] = nil
				NS.Debug("switched off " .. key)
			end
		end
	end
end

-- Hooks and places every assigned window. Also releases windows that were removed from their zone.
function NS.ApplyWindows()
	local assigned = {}
	if NS.Active() then
		for _, z in ipairs(NS.AllZones()) do
			for _, key in ipairs(NS.ZoneKeys(z.data)) do
				assigned[key] = true
				for _, fr in ipairs(NS.WindowFrames(key)) do hookFrame(fr, key) end
				NS.ApplyWindow(key)
			end
		end
	end
	for frame, key in pairs(keyOfFrame) do
		if not assigned[key] then
			keyOfFrame[frame] = nil
			restoreFrame(frame)
		end
	end
	if not NS.Active() then return end
	if GetActionBarToggles then syncBars(assigned) end
	if NS.SyncBarDirections then pcall(NS.SyncBarDirections) end
	-- windows that left their zone: MoveAny gets its saved values back, chat tabs go back into the chat window
	local everywhere = keysEverywhere()
	for key in pairs(NS.db.maBackup) do
		if not everywhere[key] then maRestore(key) end
	end
	for key in pairs(NS.db.undocked) do
		if not assigned[key] then
			NS.db.undocked[key] = nil
			local fr = _G[key]
			if fr and not fr.isDocked and FCF_DockFrame and GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
				pcall(FCF_DockFrame, fr, #GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES + 1, false)
			end
		end
	end
end

-- Edit Mode moves every action bar in its default place whenever a bar is shown, hidden or resized. Put the
-- bars that are in zones back right after it.
local barNote = {}
local function reapplyBars()
	if not (NS.db and NS.Active()) or InCombatLockdown() then return end
	for _, z in ipairs(NS.AllZones()) do
		for _, key in ipairs(NS.ZoneKeys(z.data)) do
			if PACKABLE[key] then
				local fr = NS.WindowFrames(key)[1]
				if fr then
					if not hooked[fr] then hookFrame(fr, key) end
					local ok, err = pcall(NS.ApplyWindow, key)
					if not ok then NS.Debug("could not place", key, err) end
					if not barNote[key] then
						barNote[key] = true
						NS.Debug(key, fr:IsShown() and "shown" or "HIDDEN", describe(fr))
					end
				end
			end
		end
	end
end
-- ---------------------------------------------------------------- bar direction (Edit Mode orientation)
-- Each zone can say which way its action bars run: nil = as set in Edit Mode, "h", "v", or "auto" (whichever
-- makes the bars biggest in the zone). The orientation is an Edit Mode setting, so Farsight changes it in the
-- active Edit Mode layout. WoW's preset layouts cannot be changed; they are first copied to a layout of our own.
local function isOrientable(fr)
	return fr and Enum and Enum.EditModeSystem and fr.system == Enum.EditModeSystem.ActionBar and fr.systemIndex ~= nil
end

function NS.BarIsHorizontal(key)
	local fr = NS.WindowFrames(key)[1]
	if not isOrientable(fr) then return nil end
	return fr.isHorizontal and true or false
end

-- The size a bar would have in the other direction: its visible width and height swapped.
local function barDims(fr, horizontal)
	local il, it, ir, ib = visualInsets(fr)
	local w, h = fr:GetWidth() - il - ir, fr:GetHeight() - it - ib
	if not (w and h and w > 0 and h > 0) then return nil end
	local isH = fr.isHorizontal and true or false
	if isOrientable(fr) and isH ~= horizontal then w, h = h, w end
	return w, h
end

-- How large the bars of a zone get with all of them horizontal (or vertical): the common scale of the pack.
local function packScale(zone, horizontal)
	local r = zone.rect
	if not r then
		for _, z in ipairs(NS.AllZones()) do if z.data == zone.data then r = z.rect end end
		if not r then return 0 end
	end
	local W, H = r.w - 2 * PAD, r.h - 2 * PAD
	local sumW, sumH, maxW, maxH, n = 0, 0, 0, 0, 0
	for _, k in ipairs(NS.ZoneKeys(zone.data)) do
		local fr = NS.WindowFrames(k)[1]
		local w, h
		if fr then w, h = barDims(fr, horizontal) end
		if w then
			n = n + 1
			sumW, sumH = sumW + w, sumH + h
			maxW, maxH = math.max(maxW, w), math.max(maxH, h)
		end
	end
	if n == 0 then return 0 end
	return math.max(math.min(W / maxW, H / sumH), math.min(W / sumW, H / maxH))
end

function NS.ZoneBarDirection(zone)
	local d = zone.data.barDir
	if d == "auto" then return (packScale(zone, true) >= packScale(zone, false)) and "h" or "v" end
	return d
end

local orientBusy = 0
local orientPending = {}   -- [frame] = direction saved but not shown until the layout is loaded again
local function setOrientations(changes)   -- changes = { [frame] = true (horizontal) / false }
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and EditModePresetLayoutManager) then
		NS.Print("Bar direction cannot be changed in this version of the game. Use Edit Mode instead.")
		return false
	end
	local info = C_EditMode.GetLayouts()
	if not (info and info.layouts) then return false end
	local presets = EditModePresetLayoutManager:GetCopyOfPresetLayouts()
	local layouts = {}
	for _, l in ipairs(presets) do layouts[#layouts + 1] = l end
	for _, l in ipairs(info.layouts) do layouts[#layouts + 1] = l end
	local activeIndex = info.activeLayout
	local active = layouts[activeIndex]
	if not active then return false end
	local added
	if active.layoutType == Enum.EditModeLayoutType.Preset then
		-- WoW's own layouts are read-only: continue in a copy of it
		local copy = CopyTable(active)
		copy.layoutType = Enum.EditModeLayoutType.Account
		local name, n = "Farsight", 1
		local function taken(nm) for _, l in ipairs(layouts) do if l.layoutName == nm then return true end end end
		while taken(name) do n = n + 1; name = "Farsight " .. n end
		copy.layoutName = name
		local at = #presets + 1
		for i, l in ipairs(layouts) do if l.layoutType == Enum.EditModeLayoutType.Account then at = i + 1 end end
		table.insert(layouts, at, copy)
		active, activeIndex, added = copy, at, name
	end
	local value = { [true] = Enum.ActionBarOrientation.Horizontal, [false] = Enum.ActionBarOrientation.Vertical }
	local n = 0
	for fr, horizontal in pairs(changes) do
		for _, sys in ipairs(active.systems) do
			if sys.system == fr.system and sys.systemIndex == fr.systemIndex then
				for _, st in ipairs(sys.settings) do
					if st.setting == Enum.EditModeActionBarSetting.Orientation then st.value = value[horizontal]; n = n + 1 end
				end
			end
		end
	end
	if n == 0 then return false end
	orientBusy = GetTime()
	local ok, err = pcall(C_EditMode.SaveLayouts, { layouts = layouts, activeLayout = info.activeLayout })
	if not ok then NS.Debug("could not save the Edit Mode layout:", err) return false end
	if added then
		pcall(C_EditMode.OnLayoutAdded, activeIndex, true, false)
		NS.Print("WoW's preset Edit Mode layout cannot be changed, so it was copied to a new layout \"" .. added
			.. "\" to change the bar direction there.")
	end
	-- Ask the game to load the layout again; WoW then lays the bars out itself. Calling Edit Mode's own Lua from
	-- here would taint it (errors in unit frames, action bars acting up in combat), so if the game does not
	-- reload it by itself the change waits for the next /reload.
	for fr, horizontal in pairs(changes) do orientPending[fr] = horizontal end
	if not added and C_EditMode.SetActiveLayout then pcall(C_EditMode.SetActiveLayout, activeIndex) end
	C_Timer.After(1, function()
		local still
		for fr, horizontal in pairs(changes) do if (fr.isHorizontal and true or false) ~= horizontal then still = true end end
		if still then
			NS.Print("The bar direction is saved in your Edit Mode layout. Type /reload to see it.")
		end
		NS.ApplySoon(0.1)
	end)
	return true
end

-- Turns the bars of every zone the way the zone asks for. Only bars that are the wrong way are changed.
function NS.SyncBarDirections()
	if InCombatLockdown() or GetTime() - orientBusy < 2 then return end
	local changes, any = {}, false
	for _, z in ipairs(NS.AllZones()) do
		local dir = (not z.float) and NS.ZoneBarDirection(z)
		if dir then
			for _, k in ipairs(NS.ZoneKeys(z.data)) do
				local fr = NS.WindowFrames(k)[1]
				if isOrientable(fr) then
					local want = (dir == "h")
					if (fr.isHorizontal and true or false) ~= want and orientPending[fr] ~= want then changes[fr] = want; any = true end
				end
			end
		end
	end
	if any then setOrientations(changes) end
end

-- /far bars: what Farsight sees and does for each bar in a zone (for bug reports).
function NS.DebugBars()
	NS.Print("bars: Edit Mode hooks " .. (EditModeManagerFrame and "on" or "MISSING") .. ", combat " .. tostring(InCombatLockdown()))
	for _, z in ipairs(NS.AllZones()) do
		for _, key in ipairs(NS.ZoneKeys(z.data)) do
			if PACKABLE[key] then
				local fr = NS.WindowFrames(key)[1]
				if not fr then
					NS.Print(key .. ": no frame")
				else
					local r = packRect(z, key) or z.rect
					local il, it, ir, ib = visualInsets(fr)
					NS.Print(("%s zone %s%d: %s, protected %s, base %s, insets %.0f/%.0f/%.0f/%.0f"):format(key, z.screen, z.index,
						fr:IsShown() and "shown" or "HIDDEN", tostring(fr:IsProtected()), tostring(fr.SetPointBase ~= nil), il, it, ir, ib))
					NS.Print(("   target %.0f,%.0f %.0fx%.0f (zone %.0f,%.0f %.0fx%.0f)"):format(r.x, r.y, r.w, r.h,
						z.rect.x, z.rect.y, z.rect.w, z.rect.h))
					NS.Print("   before: " .. describe(fr))
					local ok, changed = pcall(NS.ApplyWindow, key)
					NS.Print("   apply: " .. tostring(ok) .. " " .. tostring(changed) .. ", after: " .. describe(fr))
					local p = { fr:GetPoint(1) }
					NS.Print(("   point %s %s %s %.0f %.0f, %d points"):format(tostring(p[1]), p[2] and (p[2].GetName and p[2]:GetName() or "?") or "nil",
						tostring(p[3]), p[4] or 0, p[5] or 0, fr:GetNumPoints()))
				end
			end
		end
	end
end

if EditModeManagerFrame then
	for _, m in ipairs({ "UpdateRightActionBarPositions", "UpdateBottomActionBarPositions" }) do
		if EditModeManagerFrame[m] then hooksecurefunc(EditModeManagerFrame, m, reapplyBars) end
	end
end

-- Bags are re-anchored by Blizzard whenever a bag opens or closes.
if UpdateContainerFrameAnchors then
	hooksecurefunc("UpdateContainerFrameAnchors", function()
		if NS.db and NS.Active() and NS.FindZoneOf("bags") then
			C_Timer.After(0, function() NS.ApplyWindow("bags") end)
		end
	end)
end

-- Load-on-demand Blizzard windows appear later: hook them when their addon loads.
function NS.OnOtherAddonLoaded()
	if NS.HookPins then NS.HookPins() end   -- e.g. the world map loads on demand
	if not NS.Active() then return end
	for _, z in ipairs(NS.AllZones()) do
		for _, key in ipairs(NS.ZoneKeys(z.data)) do
			for _, fr in ipairs(NS.WindowFrames(key)) do
				if not hooked[fr] then hookFrame(fr, key); later(fr) end
			end
		end
	end
end

function NS.OnLeaveCombat()
	if combatPending then
		combatPending = false
		C_Timer.After(0.1, NS.ApplyWindows)
	end
end

-- Assigns a window to a zone (or clears the zone with key = nil). A window lives in one zone only.
-- add = true keeps what is already in the zone (used for bars, which can share a zone).
function NS.AssignWindow(screenId, zoneIndex, key, add)
	if key then
		for _, z in ipairs(NS.AllZones()) do NS.ZoneRemoveKey(z.data, key) end
	end
	local part = (NS.TreeParts(NS.ScreenLayout(screenId)))[zoneIndex]
	if not part then return end
	local node = part.node
	if key and add and node.win and node.win ~= key then
		node.more = node.more or {}
		node.more[#node.more + 1] = key
	else
		node.win, node.fit, node.more = key, nil, nil
	end
	if key and maRelease(key) then
		NS.Print("MoveAny had its own position or size saved for " .. NS.WindowLabel(key)
			.. ". Type /reload once so it lets go; after that the window follows its zone.")
	end
	NS.ApplyWindows()
	if key then
		local e = NS.WindowEntry(key)
		local fr = NS.WindowFrames(key)[1]
		if e and e.chat then
			-- a tab that shares the chat window with others must be pulled out to get a place of its own
			if fr and e.chat ~= 1 and fr.isDocked and FCF_UnDockFrame then
				NS.db.undocked[key] = true
				pcall(FCF_UnDockFrame, fr)
				pcall(fr.Show, fr)
				local tab = _G[fr:GetName() .. "Tab"]
				if tab then pcall(tab.Show, tab) end
			end
		elseif e and e.special then
			NS.OpenWindow(key)   -- map and bags can be opened by an addon without side effects
		elseif not (fr and fr:IsShown()) then
			if e and BAR_SETTING[key] then
				-- switched on by syncBars; it moves into the zone when the game shows it
			elseif e and e.hud then
				NS.Print(NS.WindowLabel(key) .. " is not shown right now. It moves to this zone as soon as it is.")
			else
				NS.Print(NS.WindowLabel(key) .. " goes to this zone the next time you open it.")
			end
		end
		C_Timer.After(0.2, function() NS.ApplyWindows() end)
	end
end


-- ---------------------------------------------------------------- free windows
-- A free window is not in a zone: you drag it where you want it in layout mode and it stays there.
-- What a click on a window in the zone menu does: a ticked window leaves the zone; a bar joins the bars that
-- are already there; anything else replaces what the zone held.
function NS.ToggleWindow(screenId, zoneIndex, key)
	local part = (NS.TreeParts(NS.ScreenLayout(screenId)))[zoneIndex]
	if not part then return end
	local keys = NS.ZoneKeys(part.node)
	for _, k in ipairs(keys) do
		if k == key then
			NS.ZoneRemoveKey(part.node, key)
			NS.ApplyWindows()
			return
		end
	end
	local allBars = PACKABLE[key] and #keys > 0
	for _, k in ipairs(keys) do if not PACKABLE[k] then allBars = false end end
	NS.AssignWindow(screenId, zoneIndex, key, allBars)
end

function NS.SetFloat(key, cx, cy, scale)
	local e = NS.WindowEntry(key)
	if e and e.special == "bags" then
		NS.Print("Bags cannot be free windows. Put them in a zone instead.")
		return false
	end
	-- a window lives in one place only: take it out of any zone
	for _, z in ipairs(NS.AllZones()) do
		if not z.float then NS.ZoneRemoveKey(z.data, key) end
	end
	local float = NS.FloatTable()
	local d = float[key] or { win = key }
	d.win = key
	d.cx, d.cy = math.max(0.01, math.min(0.99, cx or d.cx or 0.5)), math.max(0.01, math.min(0.99, cy or d.cy or 0.5))
	if scale then d.scale = math.max(0.2, math.min(5, scale)) end
	local new = not float[key]
	float[key] = d
	if new and maRelease(key) then
		NS.Print("MoveAny had its own position or size saved for " .. NS.WindowLabel(key)
			.. ". Type /reload once so it lets go.")
	end
	NS.ApplyWindows()
	return true
end

function NS.ClearFloat(key)
	NS.FloatTable()[key] = nil
	NS.ApplyWindows()
end
