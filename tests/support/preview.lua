-- Renders frames from the fake UI to static HTML: the addon's real layout code,
-- its real anchors and text, drawn in a browser so a person can look at it.
-- Fonts come from EasyFind's folder, icons from tools/art_png.py. It shows layout
-- and hierarchy; the game's own rendering is the final word.
local UI = require("support.fakeui")

local Preview = {}

local function css(c)
    if not c then return "transparent" end
    return ("rgba(%d,%d,%d,%.3f)"):format(c[1] * 255, c[2] * 255, c[3] * 255, c[4] or 1)
end

local function escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function rectIn(obj, parentRect, H)
    local r = UI.rectOf(obj)
    if not r then return nil end
    return r.l - parentRect.l, parentRect.t - r.t, r.r - r.l, r.t - r.b, r
end

local function artName(path)
    return path and tostring(path):match("[\\/]Art[\\/]([%w%-]+)$")
end

-- A strip of a map line: a quad bent by its corners' offsets, which a browser can
-- only draw as a polygon.
local function strip(tex, x, y, w, h, out)
    local v, eff = tex._vertex, tex:GetEffectiveScale()
    local function Corner(i, cx, cy)
        local o = v[i] or { 0, 0 }
        return ("%.1f,%.1f"):format(x + cx + o[1] * eff, y + cy - o[2] * eff)
    end
    local c = tex._tint or { 1, 1, 1, 1 }
    local dark = tostring(tex._tex):lower():find("edge", 1, true)
    out[#out + 1] = ('<svg class="r" style="left:0;top:0;width:1px;height:1px;overflow:visible"><polygon points="%s %s %s %s" fill="%s"/></svg>')
        :format(Corner(1, 0, 0), Corner(3, w, 0), Corner(4, w, h), Corner(2, 0, h),
            css(dark and { 0, 0, 0, (c[4] or 1) * 0.55 } or c))
end

local function texture(tex, parentRect, out)
    local x, y, w, h = rectIn(tex, parentRect)
    if not (x and tex._shown) then return end
    if tex._vertex and next(tex._vertex) then return strip(tex, x, y, w, h, out) end
    if w <= 0 or h <= 0 then return end
    local style = ("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;"):format(x, y, w, h)
    if tex._rotation and tex._rotation ~= 0 then style = style .. ("transform:rotate(%.3frad);"):format(-tex._rotation) end
    local art = artName(tex._tex)
    if art then
        local c = tex._tint or { 1, 1, 1, 1 }
        local co = tex._coords or { 0, 1, 0, 1 }
        local mw, mh = w / (co[2] - co[1]), h / (co[4] - co[3])
        style = style .. ("background:%s;-webkit-mask-image:url(art/%s.png);mask-image:url(art/%s.png);"
            .. "-webkit-mask-size:%.1fpx %.1fpx;mask-size:%.1fpx %.1fpx;-webkit-mask-position:%.1fpx %.1fpx;mask-position:%.1fpx %.1fpx;"
            .. "-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;"):format(css(c), art, art, mw, mh, mw, mh, -co[1] * mw, -co[3] * mh, -co[1] * mw, -co[3] * mh)
    elseif tex._color then
        style = style .. "background:" .. css(tex._color) .. ";"
    elseif tex._tex or tex._atlas then
        style = style .. "background:#3a4656;border-radius:3px;"
    else
        return
    end
    out[#out + 1] = ('<div class="r" style="%s"></div>'):format(style)
end

local FACE = { ["Inter-Regular.ttf"] = "400", ["Inter-SemiBold.ttf"] = "600", ["Inter-Bold.ttf"] = "700" }

local function fontString(fs, parentRect, out, scale)
    local text = fs._text
    if not (text and text ~= "" and fs._shown) then return end
    local x, y, w, h = rectIn(fs, parentRect)
    if not x then return end
    local file, size = fs:GetFont()
    local weight = FACE[tostring(file):match("([^\\/]+)$") or ""] or "400"
    local eff = fs:GetEffectiveScale()
    local c = fs._color or { 1, 1, 1, 1 }
    local just = ({ LEFT = "left", CENTER = "center", RIGHT = "right" })[fs._justifyH or "LEFT"]
    -- The game breaks a line where the text does: so does the render.
    local wrap = fs._wrap == false and "white-space:nowrap;text-overflow:ellipsis;" or "white-space:pre-line;"
    -- A string sized to its own text is drawn at its true width, not the estimate's.
    if fs._wrap == false and not fs._w and #fs._points < 2 then wrap = "white-space:nowrap;overflow:visible;" end
    local clamp = fs._maxLines and fs._maxLines > 0 and ("display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:%d;"):format(fs._maxLines) or ""
    local va = fs._justifyV == "MIDDLE" and (" line-height:%.1fpx;"):format(h) or ""
    out[#out + 1] = ('<div class="t" style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;font-size:%.1fpx;font-weight:%s;color:%s;text-align:%s;%s%s%s">%s</div>')
        :format(x, y, w + 0.5, h + 1, size * eff, weight, css(c), just, wrap, clamp, va, escape(UI.stripMarkup(text)))
end

local function frameHtml(f, parentRect, out, scale)
    if not f._shown then return end
    local x, y, w, h, r = rectIn(f, parentRect)
    if not x then
        for _, child in ipairs(f._children) do frameHtml(child, parentRect, out, scale) end
        return
    end
    local clip = f._clips and "overflow:hidden;" or ""
    out[#out + 1] = ('<div class="f" style="left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;%s">'):format(x, y, w, h, clip)
    local regions = {}
    for _, region in ipairs(f._regions) do regions[#regions + 1] = region end
    for i, region in ipairs(regions) do region._order = i end
    table.sort(regions, function(a, b)
        local la, lb = LAYER[a._layer or "ARTWORK"] or 3, LAYER[b._layer or "ARTWORK"] or 3
        if la ~= lb then return la < lb end
        local sa, sb = a._sublevel or 0, b._sublevel or 0
        if sa ~= sb then return sa < sb end
        return a._order < b._order
    end)
    for _, region in ipairs(regions) do
        if region._kind == "Texture" then texture(region, r, out) else fontString(region, r, out, scale) end
    end
    if f._kind == "EditBox" and f._multi and f._text then
        out[#out + 1] = ('<div class="t" style="left:0;top:0;width:100%%;white-space:pre-wrap;font-size:%.1fpx;color:#f1f3f6">%s</div>')
            :format((f._size or 11) * f:GetEffectiveScale(), escape(f._text))
    elseif f._kind == "EditBox" and f._text and f._text ~= "" then
        out[#out + 1] = ('<div class="t" style="left:0;top:0;width:100%%;line-height:%.1fpx;font-size:%.1fpx;color:#f1f3f6">%s</div>')
            :format(h, (f._size or 13) * f:GetEffectiveScale(), escape(f._text))
    end
    for _, child in ipairs(f._children) do frameHtml(child, r, out, scale) end
    out[#out + 1] = "</div>"
end

local HEAD = [[<!doctype html><meta charset="utf-8"><title>%s</title><style>
@font-face{font-family:Inter;src:url(fonts/Inter-Regular.ttf);font-weight:400}
@font-face{font-family:Inter;src:url(fonts/Inter-SemiBold.ttf);font-weight:600}
@font-face{font-family:Inter;src:url(fonts/Inter-Bold.ttf);font-weight:700}
html,body{margin:0;background:#20252b;font-family:Inter,system-ui,sans-serif}
.screen{position:relative;overflow:hidden;background:linear-gradient(160deg,#3b5a3a,#27413f 45%%,#31403f);}
.f,.r,.t{position:absolute}.t{overflow:hidden;line-height:1.22}
</style>]]

-- Writes frames, drawn on a screen pixels wide and tall, to path.
function Preview.Write(path, title, root, frames)
    local r = root._rect
    local out = { HEAD:format(title) }
    out[#out + 1] = ('<div class="screen" style="width:%dpx;height:%dpx">'):format(r.r, r.t)
    for _, f in ipairs(frames) do frameHtml(f, r, out, 1) end
    out[#out + 1] = "</div>"
    local file = assert(io.open(path, "w"))
    file:write(table.concat(out, "\n"))
    file:close()
end

return Preview
