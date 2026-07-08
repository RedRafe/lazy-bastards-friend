--- Balanced distribution math (DESIGN.md §1.3). Reimplemented from scratch;
--- reference: reference/even-distribution.lua (get_balanced_distribution).
---
--- Unlike the reference, passes 3-5 never withdraw from machines, so this is a
--- water-fill: raise the emptiest holders first until the budget runs out or
--- everyone reaches `cap`. Holders already at/above `cap` receive nothing.

local Distribution = {}

--- Compute how much to give each holder so final counts are as even as possible.
--- @param counts integer[] current per-holder item counts
--- @param available integer total the giver can spare (post-reserve)
--- @param cap integer max total per holder after filling (e.g. one stack)
--- @return integer[] gives per-holder amounts, same order as `counts`
--- @return integer used sum of gives (<= available)
function Distribution.balanced_fill(counts, available, cap)
    local n = #counts
    local gives = {}
    for i = 1, n do
        gives[i] = 0
    end
    if n == 0 or available <= 0 or cap <= 0 then
        return gives, 0
    end

    -- Clamp to cap so over-full holders drop out of the fill math entirely.
    local clamped = {}
    for i = 1, n do
        clamped[i] = math.min(counts[i], cap)
    end

    local order = {}
    for i = 1, n do
        order[i] = i
    end
    table.sort(order, function(a, b)
        if clamped[a] == clamped[b] then
            return a < b -- stable tiebreak: remainder goes to the first-listed holders
        end
        return clamped[a] < clamped[b]
    end)

    -- Find the highest common water level (<= cap) the budget can afford:
    -- sweep breakpoints (each next-higher holder count), paying to raise all
    -- holders below the current level in lockstep.
    local remaining = available
    local level = clamped[order[1]]
    local idx = 1
    while level < cap do
        while idx <= n and clamped[order[idx]] <= level do
            idx = idx + 1
        end
        local below = idx - 1
        local next_level = cap
        if idx <= n and clamped[order[idx]] < cap then
            next_level = clamped[order[idx]]
        end
        local cost = (next_level - level) * below
        if cost > remaining then
            level = level + math.floor(remaining / below)
            break
        end
        remaining = remaining - cost
        level = next_level
        if idx > n then
            break
        end
    end

    local used = 0
    for i = 1, n do
        local give = level - clamped[i]
        if give > 0 then
            gives[i] = give
            used = used + give
        end
    end

    -- Remainder spread: one extra each to the emptiest holders still under cap.
    local leftover = available - used
    if leftover > 0 then
        for _, i in ipairs(order) do
            if leftover == 0 then
                break
            end
            if clamped[i] + gives[i] < cap then
                gives[i] = gives[i] + 1
                used = used + 1
                leftover = leftover - 1
            end
        end
    end

    return gives, used
end

return Distribution
