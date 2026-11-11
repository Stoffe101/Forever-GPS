-- Professions: what this character has, the cheapest way up, what is worth making, lists of
-- what to make and buy, and the auction house's prices. Five views on one page, chosen by
-- chips, all as one list so it scrolls and scales like every other page.
local FG = ForeverGPS
local View = {}
FG.ProfessionsView = View

local Kit, Theme, List, Format = FG.Kit, FG.Theme, FG.List, FG.Format
local Prof, Craft, Market, Fares = FG.Professions, FG.Crafting, FG.Market, FG.Fares
local L = FG.L

local VIEWS = { "overview", "leveling", "profit", "lists", "market" }
local VIEW_LABEL = { overview = "PV_OVERVIEW", leveling = "PV_LEVELING", profit = "PV_PROFIT", lists = "PV_LISTS", market = "PV_MARKET" }
local SORT_LABEL = { profit = "PV_SORT_PROFIT", share = "PV_SORT_SHARE", cheap = "PV_SORT_CHEAP", safe = "PV_SORT_SAFE",
                     recovery = "PV_SORT_RECOVERY" }
local FILTER_LABEL = { complete = "PV_ONLY_COMPLETE", makeable = "PV_ONLY_MAKEABLE", sellers = "PV_ONLY_SELLERS", gain = "PV_ONLY_GAIN" }
local MODE_LABEL = { upfront = "PV_MODE_UPFRONT", net = "PV_MODE_NET", mine = "PV_MODE_MINE" }
local COVER_LABEL = { known = "PV_COVER_KNOWN", obtainable = "PV_COVER_OBTAINABLE" }
local SURE_KEY = { fresh = "PV_FRESH", recent = "PV_RECENT", stale = "PV_STALE", vendor = "PV_VENDOR" }
local TREND_KEY = { up = "PV_TREND_UP", down = "PV_TREND_DOWN", flat = "PV_TREND_FLAT" }

local f, list
local view, sort, mode, coverage = "overview", "profit", "upfront", "known"
local chosen, target, project
local only = {}
local quantity = 1

local Money = Fares.Money

-- ==== rows ==================================================================
-- Every row is as tall as its text, measured with the font, width and line limit it is
-- drawn with. 2.4 gave a line row a fixed 44 and measured at the list's full width while
-- drawing 8 narrower once the scrollbar showed; in the game, text near a line break then
-- took a line more than its row had and ran into the next one. After drawing, each row
-- also checks its text's real height, and grows if the game's fonts need more room.

local PAD_X, NAME_X, LINE_TOP, LINE_GAP, LINE_BOTTOM = 10, 28, 7, 2, 8
local NAME_LINES, SUB_LINES, TITLE_LINES = 2, 3, 2
local CARD_BUTTON_CLEAR = 8 + 24 + 6    -- a card's button: its top, its height, a gap
local measures = {}

-- The height text takes at a width, in a style, within a line limit (0: none).
local function TextHeight(text, width, style, lines)
    if not text or text == "" then return 0 end
    local key = style .. ":" .. (lines or 0)
    local fs = measures[key]
    if not fs then
        fs = UIParent:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        fs:SetAlpha(0)
        fs:SetWordWrap(true)
        if lines and lines > 0 then fs:SetMaxLines(lines) end
        measures[key] = fs
    end
    Kit.SetStyle(fs, style)
    fs:SetWidth(math.max(1, width))
    fs:SetText(text)
    return fs:GetStringHeight()
end
View._TextHeight = TextHeight

local function TextWidth(text, style)
    if not text or text == "" then return 0 end
    local key = style .. ":w"
    local fs = measures[key]
    if not fs then
        fs = UIParent:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        fs:SetAlpha(0)
        fs:SetWordWrap(false)
        measures[key] = fs
    end
    Kit.SetStyle(fs, style)
    fs:SetText(text)
    return fs:GetStringWidth()
end

-- The widths a line row gives its name and its second line, from the row's width.
local function LineWidths(item, width)
    local right = item.right and item.right ~= "" and TextWidth(item.right, "label") + 8 or 0
    return math.max(40, width - NAME_X - PAD_X - right), math.max(40, width - NAME_X - PAD_X)
end

-- A card's title room: short of a button, or of the figure on the right.
local function CardRoom(item)
    if item.action then return TextWidth(item.action, "label") + 24 + 20 end
    if item.right then return TextWidth(item.right, "label") + 24 end
    return 12
end

local function MakeCard(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) row.back:SetColor(c.card) end)
    row.action = Kit.Button(row, { text = "", height = 24, width = "fit", onClick = function(self)
        local item = self:GetParent().item
        if item.run then item.run() end
    end })
    row.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.title = Kit.Text(row, "heading", "text", TITLE_LINES)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -9)
    row.right = Kit.Text(row, "label", "accent")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -10)
    row.right:SetJustifyH("RIGHT")
    row.body = Kit.Text(row, "small", "textDim", 0)
    return row
end

local function MakeLine(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.mark = Kit.Icon(row, 12, "textDim")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", PAD_X, -9)
    row.right = Kit.Text(row, "label", "text")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD_X, -LINE_TOP)
    row.right:SetJustifyH("RIGHT")
    row.name = Kit.Text(row, "body", "text", NAME_LINES)
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X, -LINE_TOP)
    row.sub = Kit.Text(row, "small", "textDim", SUB_LINES)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -LINE_GAP)
    row:SetScript("OnEnter", function(self) self.back:SetShown(self.item.run ~= nil) end)
    row:SetScript("OnLeave", function(self) self.back:SetShown(false) end)
    row:SetScript("OnClick", function(self) if self.item.run then self.item.run() end end)
    return row
end

local function MakeSection(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.label = Kit.Text(row, "caption", "textFaint")
    row.label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 6)
    row.label:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 6)
    return row
end

local function MakeChips(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.chips = {}
    return row
end

-- Rows whose drawn text needed more room than measured: given it, and counted for the report.
View.overflows = 0
local relayoutWaits = false
local function Grow(item, need)
    if need <= (item._minH or 0) + 0.5 then return end
    item._minH = need
    View.overflows = View.overflows + 1
    if relayoutWaits then return end
    relayoutWaits = true
    FG.After(0, function()
        relayoutWaits = false
        if list then list:Refresh() end
    end)
end

local function Bind(row, item)
    row.item = item
    local width = row:GetWidth()
    if item.kind == "card" then
        row.action:SetShown(item.action ~= nil)
        if item.action then row.action:SetLabel(item.action) end
        local room = item.action and (row.action:GetWidth() + 20) or CardRoom(item)
        row.title:SetWidth(math.max(40, width - 12 - room))
        row.title:SetText(item.title or "")
        -- The text starts below the title, and below a button: never under it.
        local top = math.max(9 + row.title:GetStringHeight() + 4, item.action and CARD_BUTTON_CLEAR or 0)
        row.body:ClearAllPoints()
        row.body:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -top)
        row.body:SetWidth(math.max(40, width - 24))
        row.body:SetText(item.body or "")
        row.right:SetShown(item.action == nil and item.right ~= nil)
        row.right:SetText(item.right or "")
        local body = (item.body or "") ~= "" and row.body:GetStringHeight() or 0
        local need = top + body + 10
        if need > row:GetHeight() + 0.5 then Grow(item, need) end
    elseif item.kind == "line" then
        local nameW, subW = LineWidths(item, width)
        row.mark:SetIcon(item.icon or "dot")
        row.mark:SetColorKey(item.color or "textFaint")
        row.name:SetWidth(nameW)
        row.name:SetText(item.name or "")
        row.sub:SetWidth(subW)
        row.sub:SetText(item.sub or "")
        row.sub:SetShown((item.sub or "") ~= "")
        row.right:SetText(item.right or "")
        row.right:SetColorKey(item.rightColor or "text")
        local sub = (item.sub or "") ~= "" and (LINE_GAP + row.sub:GetStringHeight()) or 0
        local need = LINE_TOP + row.name:GetStringHeight() + sub + LINE_BOTTOM
        if need > row:GetHeight() + 0.5 then Grow(item, need) end
    elseif item.kind == "section" then
        row.label:SetText(item.text)
    elseif item.kind == "chips" then
        for _, chip in ipairs(row.chips) do chip:Hide() end
        for i, entry in ipairs(item.chips) do
            local chip = row.chips[i]
            if not chip then
                chip = Kit.Chip(row, "", function(self) self.entry.run() end)
                row.chips[i] = chip
            end
            chip.entry = entry
            chip:SetLabel(entry.label)
            chip:SetSelected(entry.selected and true or false)
            chip:Show()
        end
        local shown = {}
        for i = 1, #item.chips do shown[i] = row.chips[i] end
        local used = Kit.FlowChips(shown, row, width - 12, 6, -4)
        if used + 10 > row:GetHeight() + 0.5 then Grow(item, used + 10) end
    end
end

-- A chip's width as Kit.Chip will make it: its label measured in the chip's own style.
local function ChipWidth(label) return TextWidth(label, "caption") + 22 end

local function Height(item, width)
    local h = 30
    if item.kind == "card" then
        local title = TextHeight(item.title or "", math.max(40, width - 12 - CardRoom(item)), "heading", TITLE_LINES)
        local body = TextHeight(item.body or "", math.max(40, width - 24), "small", 0)
        local top = math.max(9 + math.max(title, 14) + 4, item.action and CARD_BUTTON_CLEAR or 0)
        h = math.max(item.action and 40 or 0, top + body + 10)
    elseif item.kind == "line" then
        local nameW, subW = LineWidths(item, width)
        local name = math.max(TextHeight(item.name or " ", nameW, "body", NAME_LINES), 14)
        local sub = (item.sub or "") ~= "" and (LINE_GAP + TextHeight(item.sub, subW, "small", SUB_LINES)) or 0
        h = math.max(30, LINE_TOP + name + sub + LINE_BOTTOM)
    elseif item.kind == "section" then
        h = 26
    elseif item.kind == "chips" then
        local w, rows, x = width - 12, 1, 0
        for _, entry in ipairs(item.chips) do
            local need = ChipWidth(entry.label)
            if x > 0 and x + need > w then rows, x = rows + 1, 0 end
            x = x + need + 6
        end
        h = rows * 30 + 6
    end
    return math.max(h, item._minH or 0)
end

-- ==== views =================================================================

local function Crafting()
    local out = {}
    for _, p in ipairs(Prof.List()) do
        if not Prof.IsGathering(p) then out[#out + 1] = p end
    end
    return out
end

local function Chosen()
    local crafting = Crafting()
    for _, p in ipairs(crafting) do
        if p.line == chosen then return p end
    end
    chosen = crafting[1] and crafting[1].line
    return crafting[1]
end

local function ProfessionChips(items)
    local chips = {}
    for _, p in ipairs(Crafting()) do
        chips[#chips + 1] = { label = p.name, selected = p.line == chosen, run = function()
            chosen, target = p.line, nil
            View.Remember()
            View.Refresh()
        end }
    end
    if #chips > 1 then items[#items + 1] = { kind = "chips", chips = chips } end
end

local function SureWord(sure) return SURE_KEY[sure] and L[SURE_KEY[sure]] or L["PV_NO_PRICE"] end

local function TrainerSearch(p)
    FG.Window.Show("search")
    FG.SearchView.Query(p.name .. " trainer")
end

local function Overview(items)
    local professions = Prof.List()
    if #professions == 0 then
        items[#items + 1] = { kind = "card", title = L["PV_NONE"], body = L["PV_NONE_HINT"] }
        return
    end
    for _, p in ipairs(professions) do
        local next = Prof.NextRank(p)
        local lines = { L["PV_SKILL_FMT"]:format(p.skill, p.max, Prof.RankName(p.max) or "") }
        if next then
            lines[#lines + 1] = next.ready and L["PV_NEXT_READY_FMT"]:format(next.name or "?")
                or next.close and L["PV_NEXT_SOON_FMT"]:format(next.name or "?") or L["PV_NEXT_LATER_FMT"]:format(next.name or "?")
        end
        if Prof.IsGathering(p) then lines[#lines + 1] = L["PV_GATHERING"] end
        items[#items + 1] = { kind = "card", title = p.name, body = table.concat(lines, "\n"),
                              action = next and L["PV_FIND_TRAINER"] or nil, run = function() TrainerSearch(p) end }
    end
    local summary = Market.Summary()
    items[#items + 1] = { kind = "section", text = L["PV_PRICES"] }
    items[#items + 1] = { kind = "line", icon = "auction", name = summary.at and L["PV_PRICES_FMT"]:format(summary.count) or L["PV_PRICES_NONE"],
                          sub = summary.at and L["PV_SCANNED_FMT"]:format(Format.Duration(time() - summary.at) or "?") or L["PV_PRICES_HOW"],
                          run = function() View.Show("market") end }
    -- The account's other characters, as each last showed itself: a copy, with its age.
    local alts = FG.Alts.List()
    if #alts > 0 then
        items[#items + 1] = { kind = "section", text = L["PV_ALTS"] }
        for _, a in ipairs(alts) do
            local parts = {}
            for _, ap in ipairs(a.professions) do parts[#parts + 1] = ("%s %d/%d"):format(ap.name or "?", ap.skill or 0, ap.max or 0) end
            items[#items + 1] = { kind = "line", icon = "star-line", color = "textDim", name = a.name or a.key,
                                  sub = (#parts > 0 and table.concat(parts, ", ") or L["PV_ALT_NONE"]) .. " \194\183 "
                                      .. L["PV_CACHED_FMT"]:format(Format.Duration(time() - (a.at or 0)) or "?") }
        end
    end
end

-- The skill-up plan is worked out in slices (Craft.PlanAsync). Its state, for the page:
--   planning  under way, with how far it has got
--   done      a plan, complete or partial (plan.stuck says where it stops, and why)
--   failed    an error, with its message; the page offers to try again
--   stalled   no progress for STALL seconds: given up, and the page offers to try again
-- The question it answers is keyed by everything that changes its answer: profession,
-- skill, target, mode, recipes to use, when the recipes were read, and the prices' version.
local STALL = 10
local planState = {}

local SOURCE_KEY = { client = "PV_SRC_CLIENT", seen = "PV_SRC_SEEN", estimate = "PV_SRC_ESTIMATE" }
local WHY_KEY = { rank = "PV_STUCK_RANK", prices = "PV_STUCK_PRICES", recipes = "PV_STUCK_HINT" }

local function PlanKey(p)
    return table.concat({ p.line, p.skill, target, mode, coverage, Prof.ReadAt() or 0, Market.Version() }, ":")
end

local function StartPlan(p, key)
    planState = { key = key, status = "planning", started = GetTime(), progressAt = GetTime(), done = 0, total = target - p.skill }
    local mine = planState
    Craft.PlanAsync(p.line, p.skill, target, mode, {
        coverage = coverage, learnUnknownFree = coverage == "obtainable",
        progress = function(done, total)
            if planState ~= mine then return end
            mine.done, mine.total, mine.progressAt = done, total, GetTime()
        end,
    }, function(plan, err)
        if planState ~= mine then return end
        if plan then
            mine.status, mine.plan = "done", plan
        else
            mine.status, mine.err = "failed", err
        end
        View.state.lastPlan = mine.status .. (err and (": " .. tostring(err)) or "")
        View.Refresh()
    end)
end

local function Retry(p)
    return function()
        planState = {}
        StartPlan(p, PlanKey(p))
        View.Refresh()
    end
end

local function Leveling(items)
    local p = Chosen()
    if not p then
        items[#items + 1] = { kind = "card", title = L["PV_NO_CRAFT"], body = L["PV_NO_CRAFT_HINT"] }
        return
    end
    ProfessionChips(items)
    local next = Prof.NextRank(p)
    if not target or target <= p.skill then target = math.min(next and next.cap or p.max, p.skill + 25) end
    local chips = {}
    for _, t in ipairs({ p.skill + 10, p.skill + 25, p.max, next and next.cap or nil }) do
        if t and t > p.skill then
            chips[#chips + 1] = { label = L["PV_TO_FMT"]:format(t), selected = t == target, run = function()
                target = t
                View.Remember()
                View.Refresh()
            end }
        end
    end
    for _, m in ipairs(Craft.MODES) do
        chips[#chips + 1] = { label = L[MODE_LABEL[m]], selected = m == mode, run = function()
            mode = m
            View.Remember()
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = chips }
    local cover = {}
    for _, cv in ipairs(Craft.COVERAGE) do
        cover[#cover + 1] = { label = L[COVER_LABEL[cv]], selected = cv == coverage, run = function()
            coverage = cv
            View.Remember()
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = cover }
    local title = L["PV_PLAN_FMT"]:format(p.name, p.skill, target)
    if coverage == "known" and #Prof.Recipes(p.line) == 0 then
        items[#items + 1] = { kind = "card", title = L["PV_NO_RECIPES_FMT"]:format(p.name), body = L["PV_NO_RECIPES_HINT"] }
        return
    end
    local key = PlanKey(p)
    if planState.key ~= key then StartPlan(p, key) end
    if planState.status == "planning" and GetTime() - planState.progressAt > STALL then
        planState.status, planState.err = "stalled", L["PV_PLAN_STALLED"]
    end
    if planState.status == "planning" then
        local share = planState.total > 0 and math.floor(100 * planState.done / planState.total) or 0
        items[#items + 1] = { kind = "card", title = title, body = L["PV_PLANNING_FMT"]:format(share) }
        return
    end
    if planState.status ~= "done" then
        items[#items + 1] = { kind = "card", title = title, body = L["PV_PLAN_FAILED_FMT"]:format(tostring(planState.err or "?")),
                              action = L["PV_TRY_AGAIN"], run = Retry(p) }
        return
    end
    local plan = planState.plan
    local body = {}
    if plan.stuck then
        body[#body + 1] = plan.stuck > p.skill and L["PV_PARTIAL_PLAN_FMT"]:format(plan.stuck, plan.stuck) or L["PV_NO_PLAN_FMT"]:format(p.skill)
    end
    body[#body + 1] = plan.unsure and L["PV_PLAN_UNSURE"] or L["PV_PLAN_SEEN"]
    body[#body + 1] = L["PV_PLAN_HOW"]
    if plan.learnUnknown then body[#body + 1] = L["PV_LEARN_UNKNOWN"] end
    if plan.incomplete then body[#body + 1] = L["PV_PLAN_INCOMPLETE"] end
    items[#items + 1] = { kind = "card", title = title, body = table.concat(body, "\n"),
                          right = plan.total and #plan.segments > 0 and Money(plan.total) or "?" }
    local trains, learns = {}, {}
    for _, t in ipairs(plan.train) do trains[t.at] = t end
    for _, l in ipairs(plan.learn) do learns[l.at] = l end
    for _, seg in ipairs(plan.segments) do
        local t = trains[seg.from]
        if t then
            local sub = t.known and L["PV_TRAIN_KNOWN_FMT"]:format(t.known) or L["PV_TRAIN_SUB"]
            if t.level then sub = sub .. " \194\183 " .. L["PV_TRAIN_LEVEL_FMT"]:format(t.level) end
            items[#items + 1] = { kind = "line", icon = "trainer", color = "accent", name = L["PV_TRAIN_FMT"]:format(t.name or "?", t.at),
                                  sub = sub, right = t.cost and Money(t.cost) or nil, run = function() TrainerSearch(p) end }
        end
        local l = learns[seg.from]
        if l then
            items[#items + 1] = { kind = "line", icon = "quest", color = "accent", name = L["PV_LEARN_FMT"]:format(l.recipe.name or "?"),
                                  sub = L[l.how == "item" and "PV_LEARN_ITEM" or "PV_LEARN_TRAINER"],
                                  right = l.cost and Money(l.cost) or "?" }
        end
        local r = seg.recipe
        local sub = L["PV_CRAFTS_SAFE_FMT"]:format(seg.crafts, seg.safe) .. " \194\183 " .. L[SOURCE_KEY[seg.source] or "PV_SRC_ESTIMATE"]
        items[#items + 1] = { kind = "line", icon = "check", color = seg.sure and "good" or "warn",
                              name = L["PV_SEGMENT_FMT"]:format(seg.from, seg.to, r.name or "?"), sub = sub, right = Money(seg.cost) }
    end
    if plan.stuck then
        local action, run
        if plan.stuckWhy == "prices" and Market.IsOpen() then
            action, run = L["PV_REFRESH_LIST"], function() FG.MarketSearch.Ask(Craft.MissingPrices(p.line)) end
        elseif plan.stuckWhy == "recipes" and coverage == "known" then
            action, run = L["PV_COVER_OBTAINABLE"], function()
                coverage = "obtainable"
                View.Remember()
                View.Refresh()
            end
        end
        items[#items + 1] = { kind = "card", title = L["PV_STUCK_FMT"]:format(plan.stuck), body = L[WHY_KEY[plan.stuckWhy] or "PV_STUCK_HINT"],
                              action = action, run = run }
    end
    if #plan.shopping > 0 then
        items[#items + 1] = { kind = "section", text = L["PV_PLAN_BUY"] }
        for _, row in ipairs(plan.shopping) do
            local sub = L["PV_BUY_SAFE_FMT"]:format(row.expected, row.safe)
            if row.have > 0 then sub = sub .. " \194\183 " .. L["PV_IN_BAGS_FMT"]:format(row.have) end
            if row.short and row.short > 0 then sub = sub .. " \194\183 " .. L["PV_SHORT_FMT"]:format(row.short) end
            items[#items + 1] = { kind = "line", icon = "dot", color = "textDim", name = FG.Item.Label(row.id), sub = sub,
                                  right = row.status == "known" and Money(row.cost) or "?" }
        end
    end
end

-- Why a recipe has no figure, in a line: which reagent has no price, or the output none.
local function Missing(e)
    if e.missing and #e.missing > 0 then
        local first = FG.Item.Label(e.missing[1])
        if #e.missing > 1 then return L["PV_MISSING_REAGENTS_FMT"]:format(first, #e.missing - 1) end
        return L["PV_MISSING_REAGENT_FMT"]:format(first)
    end
    if not e.sale then return L["PV_MISSING_SALE"] end
    return L["PV_INCOMPLETE"]
end

local QUANTITIES = { 1, 5, 10 }

local function ProfitView(items)
    local p = Chosen()
    if not p then
        items[#items + 1] = { kind = "card", title = L["PV_NO_CRAFT"], body = L["PV_NO_CRAFT_HINT"] }
        return
    end
    ProfessionChips(items)
    local chips = {}
    for _, key in ipairs(Craft.SORTS) do
        chips[#chips + 1] = { label = L[SORT_LABEL[key]], selected = key == sort, run = function()
            sort = key
            View.Remember()
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = chips }
    local filters = {}
    for _, key in ipairs(Craft.FILTERS) do
        filters[#filters + 1] = { label = L[FILTER_LABEL[key]], selected = only[key] and true or false, run = function()
            only[key] = not only[key] or nil
            View.Remember()
            View.Refresh()
        end }
    end
    for _, n in ipairs(QUANTITIES) do
        filters[#filters + 1] = { label = L["PV_MAKE_N_FMT"]:format(n), selected = n == quantity, run = function()
            quantity = n
            View.Remember()
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = filters }
    local recipes = 0
    for _, r in ipairs(Prof.Recipes(p.line)) do
        if r.learned and r.out then recipes = recipes + 1 end
    end
    if recipes == 0 then
        local reading = Prof.status.windowOpen and Prof.status.lastWhy ~= "ok"
        items[#items + 1] = { kind = "card", title = reading and L["PV_READING"] or L["PV_NO_RECIPES_FMT"]:format(p.name),
                              body = reading and L["PV_READING_HINT"] or (#Prof.Recipes(p.line) > 0 and L["PV_NO_LEARNED"] or L["PV_NO_RECIPES_HINT"]) }
        return
    end
    local all = Craft.Ranking(p.line, sort, nil, quantity)
    local ranking = Craft.Ranking(p.line, sort, only, quantity)
    View.state.ranked, View.state.complete = #all, 0
    local noReagent, noSale, ask, seen = 0, 0, {}, {}
    for _, e in ipairs(all) do
        if e.complete then
            View.state.complete = View.state.complete + 1
        elseif e.missing and #e.missing > 0 then
            noReagent = noReagent + 1
        else
            noSale = noSale + 1
        end
        for _, id in ipairs(e.missing or {}) do
            if not seen[id] then seen[id], ask[#ask + 1] = true, id end
        end
        if not e.sale and e.recipe.out and not seen[e.recipe.out] then seen[e.recipe.out], ask[#ask + 1] = true, e.recipe.out end
    end
    -- What the figures rest on, in one card: how many could be priced, and what is missing.
    local lines = { L["PV_PROFIT_COUNT_FMT"]:format(#all, View.state.complete) }
    if noReagent > 0 then lines[#lines + 1] = L["PV_PROFIT_NO_REAGENT_FMT"]:format(noReagent) end
    if noSale > 0 then lines[#lines + 1] = L["PV_PROFIT_NO_SALE_FMT"]:format(noSale) end
    local action, run
    if #ask > 0 then
        if Market.IsOpen() and FG.MarketSearch.Available() then
            action, run = L["PV_REFRESH_LIST"], function()
                FG.MarketSearch.Ask(ask)
                View.Refresh()
            end
        else
            lines[#lines + 1] = L["PV_OPEN_AH_HINT"]
        end
    end
    lines[#lines + 1] = L["PV_PROFIT_HOW"]
    items[#items + 1] = { kind = "card", title = L["PV_PROFIT_TITLE"], body = table.concat(lines, "\n"), action = action, run = run }
    if #ranking == 0 then
        items[#items + 1] = { kind = "card", title = L["PV_NOTHING_FILTERED"], body = L["PV_NOTHING_FILTERED_HINT"],
                              action = L["PV_CLEAR_FILTERS"], run = function()
                                  only = {}
                                  View.Remember()
                                  View.Refresh()
                              end }
        return
    end
    for _, e in ipairs(ranking) do
        local r = e.recipe
        local sub
        if e.complete then
            sub = L["PV_PROFIT_SUB_FMT"]:format(Money(e.cost), Money(math.floor(e.sale)), SureWord(e.sure))
            if e.share then sub = sub .. " \194\183 " .. L["PV_MARGIN_FMT"]:format(math.floor(e.share * 100 + 0.5)) end
            if e.upfront < e.cost then sub = sub .. " \194\183 " .. L["PV_UPFRONT_FMT"]:format(Money(e.upfront)) end
            if e.listed == 0 then sub = sub .. " \194\183 " .. L["PV_NO_SELLERS"] end
        else
            sub = Missing(e)
        end
        if e.recovery then sub = sub .. " \194\183 " .. L["PV_RECOVERY_FMT"]:format(Money(math.floor(e.recovery))) end
        local _, trend = FG.PriceHistory.Of(r.out)
        if trend then sub = sub .. " \194\183 " .. L[TREND_KEY[trend]] end
        if e.canMake > 0 then sub = sub .. " \194\183 " .. L["PV_CAN_MAKE_FMT"]:format(e.canMake) end
        local name = r.name or FG.Item.Label(r.out)
        if quantity > 1 then name = L["PV_ITEM_FMT"]:format(quantity, name) end
        items[#items + 1] = { kind = "line", icon = e.complete and (e.profit > 0 and "plus" or "close") or "warning",
                              color = e.complete and (e.profit > 0 and "good" or "danger") or "textFaint",
                              name = name, sub = sub, right = e.complete and Money(math.abs(e.profit)) or "?",
                              rightColor = e.complete and (e.profit > 0 and "good" or "danger") or "textFaint",
                              run = function() View.AddToList(r.id) end }
    end
end

-- A list's reagent in two lines: what and what it costs, then how many and from where.
local function NeedLine(row, done)
    local parts = { L["PV_NEED_FMT"]:format(row.need) }
    if row.bags > 0 or row.bank > 0 then parts[#parts + 1] = L["PV_OWN_FMT"]:format(row.bags, row.bank) end
    if not done then
        parts[#parts + 1] = L["PV_TO_BUY_FMT"]:format(row.left)
        if row.fromVendor and row.fromVendor > 0 then parts[#parts + 1] = L["PV_FROM_VENDOR_FMT"]:format(row.fromVendor) end
        if row.short and row.short > 0 then parts[#parts + 1] = L["PV_SHORT_FMT"]:format(row.short) end
        if row.status ~= "known" then parts[#parts + 1] = L["PV_NO_PRICE"] end
    end
    if row.mark then parts[#parts + 1] = L[row.mark == "bought" and "PV_MARK_BOUGHT" or "PV_MARK_HAVE"] end
    if row.alts then
        local names = {}
        for _, a in ipairs(row.alts) do names[#names + 1] = a.name or a.key end
        parts[#parts + 1] = L["PV_ALT_MAKES_FMT"]:format(table.concat(names, ", "))
    end
    return table.concat(parts, " \194\183 ")
end

local function Lists(items)
    local projects = Craft.Projects()
    local chips = {}
    for _, pr in ipairs(projects) do
        chips[#chips + 1] = { label = pr.name, selected = pr == project, run = function()
            project = pr
            View.Refresh()
        end }
    end
    chips[#chips + 1] = { label = L["PV_NEW_LIST"], run = function()
        project = Craft.NewProject(L["PV_LIST_FMT"]:format(#projects + 1))
        View.Refresh()
    end }
    items[#items + 1] = { kind = "chips", chips = chips }
    if not project then project = projects[1] end
    if not project then
        items[#items + 1] = { kind = "card", title = L["PV_LISTS_EMPTY"], body = L["PV_LISTS_HINT"] }
        return
    end
    items[#items + 1] = { kind = "section", text = project.name:upper() }
    if #project.items == 0 then
        items[#items + 1] = { kind = "card", title = L["PV_LIST_EMPTY"], body = L["PV_LISTS_HINT"] }
        return
    end
    for i, it in ipairs(project.items) do
        local r = Prof.Recipe(it.recipe)
        items[#items + 1] = { kind = "line", icon = "close", color = "textFaint", name = L["PV_ITEM_FMT"]:format(it.qty, r and r.name or "?"),
                              sub = L["PV_REMOVE"], run = function()
                                  Craft.Remove(project, i)
                                  View.Refresh()
                              end }
    end
    local shop = Craft.Shopping(project, true)
    items[#items + 1] = { kind = "section", text = L["PV_SHOPPING"] }
    local MARK_NEXT = { [false] = "bought", bought = "have", have = false }
    for _, row in ipairs(shop.rows) do
        local done = row.left == 0
        items[#items + 1] = { kind = "line", icon = done and "check" or "dot", color = done and "good" or "textDim",
                              name = FG.Item.Label(row.id), sub = NeedLine(row, done),
                              right = not done and (row.cost and Money(row.cost) or "?") or "",
                              run = function()
                                  Craft.Mark(project, row.id, MARK_NEXT[row.mark or false] or nil)
                                  View.Refresh()
                              end }
        -- Something this character can make, bought for now: make it instead.
        if row.makes then
            items[#items + 1] = { kind = "line", icon = "gear", color = "accent", name = L["PV_MAKE_INSTEAD_FMT"]:format(FG.Item.Label(row.id)),
                                  sub = row.choice == "buy" and L["PV_CHOSEN_BUY"] or L["PV_CHEAPER_BUY"], run = function()
                                      Craft.Choose(project, row.id, "craft")
                                      View.Refresh()
                                  end }
        end
    end
    -- What is made on the way, and what each batch leaves over.
    for _, c in ipairs(shop.crafts) do
        local sub = c.surplus > 0 and L["PV_SURPLUS_FMT"]:format(c.surplus) or L["PV_NO_SURPLUS"]
        sub = sub .. " \194\183 " .. (project.choose[c.id] == "craft" and L["PV_CHOSEN_CRAFT"] or L["PV_CHEAPER_CRAFT"])
        items[#items + 1] = { kind = "line", icon = "gear", color = "good",
                              name = L["PV_MAKE_FMT"]:format(c.runs, c.recipe.name or FG.Item.Label(c.id)),
                              sub = sub, run = function()
                                  Craft.Choose(project, c.id, "buy")
                                  View.Refresh()
                              end }
    end
    -- Fresh prices for what is still to buy, one search each, while the house is open.
    local ask = {}
    for _, row in ipairs(shop.rows) do
        if row.left > 0 then ask[#ask + 1] = row.id end
    end
    local searching = FG.MarketSearch.Status()
    local total = { L["PV_TOTAL_HOW"] }
    if shop.unknown > 0 then table.insert(total, 1, L["PV_TOTAL_UNKNOWN_FMT"]:format(shop.unknown)) end
    if shop.short > 0 then table.insert(total, 1, L["PV_TOTAL_SHORT_FMT"]:format(shop.short)) end
    local action, run = L["PV_GO_AUCTION"], function()
        FG.Window.Show("search")
        FG.SearchView.Query("auction house")
    end
    if #ask > 0 and Market.IsOpen() and FG.MarketSearch.Available() then
        local busy = searching.waiting > 0 or searching.current
        if busy then
            total[#total + 1] = L["PV_REFRESHING_FMT"]:format(searching.waiting + (searching.current and 1 or 0))
            action, run = nil, nil
        else
            action, run = L["PV_REFRESH_LIST"], function()
                FG.MarketSearch.Ask(ask)
                View.Refresh()
            end
        end
    end
    items[#items + 1] = { kind = "card", title = L["PV_TOTAL_FMT"]:format(Money(shop.total)), body = table.concat(total, "\n"),
                          action = action, run = run }
    items[#items + 1] = { kind = "card", title = L["PV_COPY_TITLE"], body = L["PV_COPY_HOW"], action = L["PV_COPY"], run = function()
        FG.CopyBox.Show((Craft.ShoppingText(project, true)))
    end }
end

-- Where a scan stands, in words.
local function ScanState(scan)
    if scan.state == "waiting" then return L["PV_SCAN_WAITING"] end
    if scan.state == "settling" then
        local n = C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetNumReplicateItems() or 0
        return L["PV_SCAN_SETTLING_FMT"]:format(n) .. (scan.by == "other" and ("\n" .. L["PV_SCAN_OTHER"]) or "")
    end
    if scan.state == "reading" then return L["PV_SCAN_READING_FMT"]:format(scan.at or 0, scan.total or 0) end
    if scan.state == "failed" then return scan.why or L["PV_SCAN_FAILED"] end
    return nil
end

local AGE_KEY = { fresh = "PV_AGE_fresh", recent = "PV_AGE_recent", stale = "PV_AGE_stale" }

local function MarketView(items)
    local s = Market.Summary()
    local ok, why = Market.CanScan()
    local state = ScanState(Market.Scanning())
    local age = s.at and L["PV_PRICES_AGE_FMT"]:format(Format.Duration(time() - s.at) or "?", L[AGE_KEY[s.sure] or "PV_AGE_stale"])
    local lines = { L["PV_HOUSE_FMT"]:format(s.key), age or L["PV_PRICES_HOW"] }
    if s.partial then lines[#lines + 1] = L["PV_PARTIAL"] end
    if s.searched > 0 and s.searchedAt then
        lines[#lines + 1] = L["PV_SEARCHED_FMT"]:format(s.searched, Format.Duration(time() - s.searchedAt) or "?")
    end
    lines[#lines + 1] = state or why or L["PV_SCAN_READY"]
    local auto = FG.AutoPrices.Line()
    if auto then lines[#lines + 1] = auto end
    items[#items + 1] = { kind = "card", title = s.at and L["PV_PRICES_FMT"]:format(s.count) or L["PV_PRICES_NONE"],
                          body = table.concat(lines, "\n"),
                          action = ok and L["PV_SCAN"] or nil, run = function()
                              Market.Scan()
                              View.Refresh()
                          end }
    items[#items + 1] = { kind = "card", title = L["PV_PRICES_ABOUT"], body = L["PV_PRICES_ABOUT_BODY"] }
end

local BUILD = { overview = Overview, leveling = Leveling, profit = ProfitView, lists = Lists, market = MarketView }

-- What the page has done, for /fgps report: the last error, the profit counts, the plan.
View.state = { errors = 0 }

-- A view that fails says so, with the error, rather than leaving the last view's rows.
local function Items()
    local items = {}
    local ok, err = pcall(BUILD[view], items)
    if not ok then
        View.state.errors = View.state.errors + 1
        View.state.lastError = tostring(err)
        FG.Metrics.Note("professions page failed: " .. tostring(err))
        items = { { kind = "card", title = L["PV_FAILED"], body = L["PV_FAILED_HINT"], action = L["PV_TRY_AGAIN"],
                    run = function() View.Refresh() end } }
    end
    return items
end

function View.Refresh()
    if not (f and f:IsVisible()) then return end
    for _, chip in ipairs(f.tabs) do chip:SetSelected(chip.key == view) end
    list:SetItems(Items(), true)
end

-- Many events in a moment (a bag sorting, items arriving) draw once.
local refreshWaits = false
local function RefreshSoon()
    if refreshWaits or not (f and f:IsVisible()) then return end
    refreshWaits = true
    FG.After(0.25, function()
        refreshWaits = false
        View.Refresh()
    end)
end
View.RefreshSoon = RefreshSoon

function View.Show(which)
    view = which or view
    View.Remember()
    if f then
        View.Layout()
        View.Refresh()
    end
end

function View.Current() return view end

-- The page's choices, kept per character across reloads.
function View.Remember()
    if not FG.char then return end
    FG.char.professionsPage = { view = view, sort = sort, mode = mode, coverage = coverage, chosen = chosen, quantity = quantity, only = only }
end

local function Recall()
    local saved = FG.char and FG.char.professionsPage
    if type(saved) ~= "table" then return end
    view = BUILD[saved.view] and saved.view or view
    sort = saved.sort or sort
    mode = saved.mode or mode
    coverage = saved.coverage or coverage
    chosen = saved.chosen or chosen
    quantity = saved.quantity or quantity
    only = type(saved.only) == "table" and saved.only or only
end

-- For renders and tests: the page's choices, set directly.
function View._Set(state)
    coverage = state.coverage or coverage
    mode = state.mode or mode
    sort = state.sort or sort
    quantity = state.quantity or quantity
    target = state.target or target
    if state.only then only = state.only end
    View.Refresh()
end
function View.ItemsNow() return list and list.items or {} end
function View.PlanState() return planState end

function View.AddToList(recipeID)
    project = project or Craft.Projects()[1] or Craft.NewProject(L["PV_LIST_FMT"]:format(1))
    Craft.AddToProject(project, recipeID, quantity or 1)
    local r = Prof.Recipe(recipeID)
    FG.Print(L["PV_ADDED_FMT"]:format(r and r.name or "?", project.name))
end

function View.Layout()
    local h = Kit.FlowChips(f.tabs, f, f:GetWidth(), 6, 0)
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -h - 8)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

local function Build(parent)
    f = CreateFrame("Frame", nil, parent)
    f.tabs = {}
    for _, key in ipairs(VIEWS) do
        local chip = Kit.Chip(f, L[VIEW_LABEL[key]], function(self) View.Show(self.key) end)
        chip.key = key
        f.tabs[#f.tabs + 1] = chip
    end
    list = List.New(f, {
        make = { card = MakeCard, line = MakeLine, section = MakeSection, chips = MakeChips },
        bind = Bind, height = Height,
    })
    f.list = list
    -- A window made narrower wraps the tabs: the list moves down with them.
    f:SetScript("OnSizeChanged", function()
        View.Layout()
        RefreshSoon()
    end)
    f:SetScript("OnShow", function() RefreshSoon() end)
    Recall()
    for _, topic in ipairs({ "professions:changed", "recipes:changed", "market:changed", "market:prices", "projects:changed",
                             "trainers:changed", "items:loaded" }) do
        FG.On(topic, RefreshSoon)
    end
    FG.OnEvent("BAG_UPDATE_DELAYED", RefreshSoon)
    return f
end

function View.Get(parent) return f or Build(parent) end
