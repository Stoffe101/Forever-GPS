-- One rule for our text's shadow (ns.ShadeText: flat, but over a Classic
-- talent tree). 2026-10-27: the filter dropdown flattened its labels again
-- on every fill and the tree's shadow never reached it. No code sets a
-- text's shadow to none by hand; the world beacon's plate, on its own dark
-- fill outside every window, is the one exception.
local H = require("Harness")

local KNOWN = { ["WorldPin.lua"] = true }

local tests = {}

function tests.noTextFlattenedByHand()
    local bad, checked = {}, 0
    for _, toc in ipairs(H.TOCS) do
        for _, rel in ipairs((H.TocFiles(toc))) do
            local fh = io.open(H.Path(rel), "r")
            if fh then
                checked = checked + 1
                local n = 0
                for line in fh:lines() do
                    n = n + 1
                    if not KNOWN[rel] and line:find("SetShadowColor%(0, 0, 0, 0%)") then bad[#bad + 1] = rel .. ":" .. n end
                end
                fh:close()
            end
        end
    end
    H.assertTrue(checked > 50, "expected the full file set, read " .. checked)
    H.assertEq(#bad, 0, "use ns.ShadeText:\n  " .. table.concat(bad, "\n  "))
end


local pass, fail, failures = H.runSuite("OneShadowRule", tests)
return { pass = pass, fail = fail, failures = failures }
