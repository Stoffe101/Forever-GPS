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

local Money = Fares.Money

-- ==== rows ==================================================================

local function MakeCard(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.back = Kit.Shape(row, 7, "BACKGROUND", 1)
    Theme.Paint(function(c) row.back:SetColor(c.card) end)
    row.action = Kit.Button(row, { text = "", height = 24, width = "fit", onClick = function(self)
        local item = self:GetParent().item
        if item.run then item.run() end
    end })
    row.action:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
    row.title = Kit.Text(row, "heading", "text")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -9)
    row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -9)
    row.right = Kit.Text(row, "label", "accent")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -10)
    row.right:SetJustifyH("RIGHT")
    row.body = Kit.Text(row, "small", "textDim", 0)
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -30)
    return row
end

local function MakeLine(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp")
    row.back = Kit.Shape(row, 6, "BACKGROUND", 1)
    row.back:SetShown(false)
    Theme.Paint(function(c) row.back:SetColor(c.cardHover) end)
    row.mark = Kit.Icon(row, 12, "textDim")
    row.mark:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -9)
    row.right = Kit.Text(row, "label", "text")
    row.right:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -7)
    row.right:SetJustifyH("RIGHT")
    row.name = Kit.Text(row, "body", "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -7)
    row.name:SetPoint("TOPRIGHT", row.right, "TOPLEFT", -8, 0)
    row.sub = Kit.Text(row, "small", "textDim")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -24)
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

local function Bind(row, item)
    row.item = item
    if item.kind == "card" then
        row.title:SetText(item.title or "")
        row.body:SetText(item.body or "")
        row.action:SetShown(item.action ~= nil)
        if item.action then row.action:SetLabel(item.action) end
        -- The title stops short of a button, or of the figure on the right.
        local room = item.action and (row.action:GetWidth() + 20) or (item.right and 90 or 12)
        row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -room, -9)
        row.right:SetShown(item.action == nil and item.right ~= nil)
        row.right:SetText(item.right or "")
    elseif item.kind == "line" then
        row.mark:SetIcon(item.icon or "dot")
        row.mark:SetColorKey(item.color or "textFaint")
        row.name:SetText(item.name or "")
        row.sub:SetText(item.sub or "")
        row.right:SetText(item.right or "")
        row.right:SetColorKey(item.rightColor or "text")
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
        Kit.FlowChips(shown, row, list:Width() - 12, 6, -4)
    end
end

local function Height(item, width)
    if item.kind == "card" then
        return 34 + FG.RoutePanel.TextHeight(item.body or "", width - 24, "small") + 8
    end
    if item.kind == "line" then return item.sub and item.sub ~= "" and 44 or 30 end
    if item.kind == "section" then return 26 end
    if item.kind == "chips" then
        local w, rows, x = width - 12, 1, 0
        for _, entry in ipairs(item.chips) do
            local need = #entry.label * 7 + 26
            if x > 0 and x + need > w then rows, x = rows + 1, 0 end
            x = x + need + 6
        end
        return rows * 30 + 6
    end
    return 30
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

-- The plan on screen is worked out in slices; this keeps the last one per question.
local planKey, planShown

local SOURCE_KEY = { client = "PV_SRC_CLIENT", seen = "PV_SRC_SEEN", estimate = "PV_SRC_ESTIMATE" }

local function Leveling(items)
    local p = Chosen()
    if not p then
        items[#items + 1] = { kind = "card", title = L["PV_NO_CRAFT"], body = L["PV_NO_CRAFT_HINT"] }
        return
    end
    ProfessionChips(items)
    local next = Prof.NextRank(p)
    target = target or math.min(next and next.cap or p.max, p.skill + 25)
    local chips = {}
    for _, t in ipairs({ p.skill + 10, p.skill + 25, p.max, next and next.cap or nil }) do
        if t and t > p.skill then
            chips[#chips + 1] = { label = L["PV_TO_FMT"]:format(t), selected = t == target, run = function()
                target = t
                View.Refresh()
            end }
        end
    end
    for _, m in ipairs(Craft.MODES) do
        chips[#chips + 1] = { label = L[MODE_LABEL[m]], selected = m == mode, run = function()
            mode = m
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = chips }
    local cover = {}
    for _, cv in ipairs(Craft.COVERAGE) do
        cover[#cover + 1] = { label = L[COVER_LABEL[cv]], selected = cv == coverage, run = function()
            coverage = cv
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = cover }
    if coverage == "known" and #Prof.Recipes(p.line) == 0 then
        items[#items + 1] = { kind = "card", title = L["PV_NO_RECIPES"], body = L["PV_NO_RECIPES_HINT"] }
        return
    end
    local key = table.concat({ p.line, p.skill, target, mode, coverage, Market.Summary().at or 0 }, ":")
    if planKey ~= key then
        planKey, planShown = key, nil
        Craft.PlanAsync(p.line, p.skill, target, mode, { coverage = coverage, learnUnknownFree = coverage == "obtainable" }, function(plan)
            if planKey == key then
                planShown = plan or false
                View.Refresh()
            end
        end)
    end
    if planShown == nil then
        items[#items + 1] = { kind = "card", title = L["PV_PLAN_FMT"]:format(p.name, p.skill, target), body = L["PV_PLANNING"] }
        return
    end
    local plan = planShown
    if not plan then
        items[#items + 1] = { kind = "card", title = L["PV_PLAN_FMT"]:format(p.name, p.skill, target), body = L["PV_PLAN_FAILED"] }
        return
    end
    local body = { plan.unsure and L["PV_PLAN_UNSURE"] or L["PV_PLAN_SEEN"], L["PV_PLAN_HOW"] }
    if plan.learnUnknown then body[#body + 1] = L["PV_LEARN_UNKNOWN"] end
    if plan.incomplete then body[#body + 1] = L["PV_PLAN_INCOMPLETE"] end
    items[#items + 1] = { kind = "card", title = L["PV_PLAN_FMT"]:format(p.name, p.skill, target),
                          body = table.concat(body, "\n"), right = plan.total and Money(plan.total) or "?" }
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
        items[#items + 1] = { kind = "card", title = L["PV_STUCK_FMT"]:format(plan.stuck),
                              body = L[plan.stuckWhy == "rank" and "PV_STUCK_RANK" or plan.stuckWhy == "prices" and "PV_STUCK_PRICES" or "PV_STUCK_HINT"] }
    end
    if #plan.shopping > 0 then
        items[#items + 1] = { kind = "section", text = L["PV_PLAN_BUY"] }
        for _, row in ipairs(plan.shopping) do
            local name = GetItemInfo(row.id) or ("#" .. row.id)
            local sub = L["PV_BUY_SAFE_FMT"]:format(row.expected, row.safe)
            if row.have > 0 then sub = sub .. " \194\183 " .. L["PV_IN_BAGS_FMT"]:format(row.have) end
            if row.short and row.short > 0 then sub = sub .. " \194\183 " .. L["PV_SHORT_FMT"]:format(row.short) end
            items[#items + 1] = { kind = "line", icon = "dot", color = "textDim", name = name, sub = sub,
                                  right = row.status == "known" and Money(row.cost) or "?" }
        end
    end
end

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
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = chips }
    local filters = {}
    for _, key in ipairs(Craft.FILTERS) do
        filters[#filters + 1] = { label = L[FILTER_LABEL[key]], selected = only[key] and true or false, run = function()
            only[key] = not only[key] or nil
            View.Refresh()
        end }
    end
    items[#items + 1] = { kind = "chips", chips = filters }
    local ranking = Craft.Ranking(p.line, sort, only)
    if #ranking == 0 then
        local any = next(only) ~= nil
        items[#items + 1] = { kind = "card", title = any and L["PV_NOTHING_FILTERED"] or L["PV_NO_RECIPES"],
                              body = any and L["PV_NOTHING_FILTERED_HINT"] or L["PV_NO_RECIPES_HINT"] }
        return
    end
    items[#items + 1] = { kind = "card", title = L["PV_PROFIT_TITLE"], body = L["PV_PROFIT_HOW"] }
    for _, e in ipairs(ranking) do
        local r = e.recipe
        local sub
        if e.complete then
            sub = L["PV_PROFIT_SUB_FMT"]:format(Money(e.cost), Money(math.floor(e.sale)), SureWord(e.sure))
            if e.upfront < e.cost then sub = sub .. " \194\183 " .. L["PV_UPFRONT_FMT"]:format(Money(e.upfront)) end
            if e.listed == 0 then sub = sub .. " \194\183 " .. L["PV_NO_SELLERS"] end
        else
            sub = L["PV_INCOMPLETE"]
        end
        if e.recovery then sub = sub .. " \194\183 " .. L["PV_RECOVERY_FMT"]:format(Money(math.floor(e.recovery))) end
        local _, trend = FG.PriceHistory.Of(r.out)
        if trend then sub = sub .. " \194\183 " .. L[TREND_KEY[trend]] end
        if e.canMake > 0 then sub = sub .. " \194\183 " .. L["PV_CAN_MAKE_FMT"]:format(e.canMake) end
        items[#items + 1] = { kind = "line", icon = e.complete and (e.profit > 0 and "plus" or "close") or "warning",
                              color = e.complete and (e.profit > 0 and "good" or "danger") or "textFaint",
                              name = r.name, sub = sub, right = e.complete and Money(math.abs(e.profit)) or "?",
                              rightColor = e.complete and (e.profit > 0 and "good" or "danger") or "textFaint",
                              run = function() View.AddToList(r.id) end }
    end
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
        local name = GetItemInfo(row.id) or ("#" .. row.id)
        local done = row.left == 0
        local sub = L["PV_HAVE_FMT"]:format(row.need, row.bags, row.bank)
        if row.mark then sub = sub .. " \194\183 " .. L[row.mark == "bought" and "PV_MARK_BOUGHT" or "PV_MARK_HAVE"] end
        if row.short and row.short > 0 and not done then sub = sub .. " \194\183 " .. L["PV_SHORT_FMT"]:format(row.short) end
        if row.fromVendor and row.fromVendor > 0 and not done then sub = sub .. " \194\183 " .. L["PV_FROM_VENDOR_FMT"]:format(row.fromVendor) end
        if row.alts then
            local names = {}
            for _, a in ipairs(row.alts) do names[#names + 1] = a.name or a.key end
            sub = sub .. " \194\183 " .. L["PV_ALT_MAKES_FMT"]:format(table.concat(names, ", "))
        end
        items[#items + 1] = { kind = "line", icon = done and "check" or "dot", color = done and "good" or "textDim",
                              name = done and name or L["PV_ITEM_FMT"]:format(row.left, name), sub = sub,
                              right = row.left > 0 and (row.cost and Money(row.cost) or "?") or "",
                              run = function()
                                  Craft.Mark(project, row.id, MARK_NEXT[row.mark or false] or nil)
                                  View.Refresh()
                              end }
        -- Something this character can make, bought for now: make it instead.
        if row.makes then
            items[#items + 1] = { kind = "line", icon = "gear", color = "accent", name = L["PV_MAKE_INSTEAD_FMT"]:format(name),
                                  sub = row.choice == "buy" and L["PV_CHOSEN_BUY"] or L["PV_CHEAPER_BUY"], run = function()
                                      Craft.Choose(project, row.id, "craft")
                                      View.Refresh()
                                  end }
        end
    end
    -- What is made on the way, and what each batch leaves over.
    for _, c in ipairs(shop.crafts) do
        local name = GetItemInfo(c.id) or ("#" .. c.id)
        local sub = c.surplus > 0 and L["PV_SURPLUS_FMT"]:format(c.surplus) or L["PV_NO_SURPLUS"]
        sub = sub .. " \194\183 " .. (project.choose[c.id] == "craft" and L["PV_CHOSEN_CRAFT"] or L["PV_CHEAPER_CRAFT"])
        items[#items + 1] = { kind = "line", icon = "gear", color = "good", name = L["PV_MAKE_FMT"]:format(c.runs, c.recipe.name or name),
                              sub = sub, run = function()
                                  Craft.Choose(project, c.id, "buy")
                                  View.Refresh()
                              end }
    end
    items[#items + 1] = { kind = "card", title = L["PV_COPY_TITLE"], body = L["PV_COPY_HOW"], action = L["PV_COPY"], run = function()
        FG.CopyBox.Show((Craft.ShoppingText(project, true)))
    end }
    -- Fresh prices for what is still to buy, one search each, while the house is open.
    local ask = {}
    for _, row in ipairs(shop.rows) do
        if row.left > 0 then ask[#ask + 1] = row.id end
    end
    local searching = FG.MarketSearch.Status()
    if #ask > 0 and Market.IsOpen() and FG.MarketSearch.Available() then
        local busy = searching.waiting > 0 or searching.current
        items[#items + 1] = { kind = "card", title = L["PV_REFRESH_LIST"],
                              body = busy and L["PV_REFRESHING_FMT"]:format(searching.waiting + (searching.current and 1 or 0)) or L["PV_TOTAL_HOW"],
                              action = not busy and L["PV_REFRESH_LIST"] or nil, run = function()
                                  FG.MarketSearch.Ask(ask)
                                  View.Refresh()
                              end }
    end
    items[#items + 1] = { kind = "card", title = L["PV_TOTAL_FMT"]:format(Money(shop.total)),
                          body = shop.unknown > 0 and L["PV_TOTAL_UNKNOWN_FMT"]:format(shop.unknown) or L["PV_TOTAL_HOW"],
                          action = L["PV_GO_AUCTION"], run = function()
                              FG.Window.Show("search")
                              FG.SearchView.Query("auction house")
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
    lines[#lines + 1] = state or why or L["PV_SCAN_READY"]
    items[#items + 1] = { kind = "card", title = s.at and L["PV_PRICES_FMT"]:format(s.count) or L["PV_PRICES_NONE"],
                          body = table.concat(lines, "\n"),
                          action = ok and L["PV_SCAN"] or nil, run = function()
                              Market.Scan()
                              View.Refresh()
                          end }
    items[#items + 1] = { kind = "card", title = L["PV_PRICES_ABOUT"], body = L["PV_PRICES_ABOUT_BODY"] }
end

local BUILD = { overview = Overview, leveling = Leveling, profit = ProfitView, lists = Lists, market = MarketView }

local function Items()
    local items = {}
    BUILD[view](items)
    return items
end

function View.Refresh()
    if not (f and f:IsVisible()) then return end
    for _, chip in ipairs(f.tabs) do chip:SetSelected(chip.key == view) end
    list:SetItems(Items(), true)
end

function View.Show(which)
    view = which or view
    if f then
        View.Layout()
        View.Refresh()
    end
end

function View.Current() return view end
function View.ItemsNow() return list and list.items or {} end

function View.AddToList(recipeID)
    project = project or Craft.Projects()[1] or Craft.NewProject(L["PV_LIST_FMT"]:format(1))
    Craft.AddToProject(project, recipeID, 1)
    FG.Print(L["PV_ADDED_FMT"]:format(Prof.Recipe(recipeID).name or "?", project.name))
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
    for _, topic in ipairs({ "professions:changed", "recipes:changed", "market:changed", "projects:changed", "trainers:changed" }) do
        FG.On(topic, function() View.Refresh() end)
    end
    return f
end

function View.Get(parent) return f or Build(parent) end
