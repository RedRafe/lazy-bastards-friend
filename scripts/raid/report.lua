--- Reporting (DESIGN.md §4.4, §10.5): pumps a cycle's tally into the
--- production-graph statistics and the optional flying-text summary.

local Report = {}

local SUMMARY_INTERVAL_TICKS = 600 -- de-noise the flying text vs. the ~1s-per-player raid cycle

--- Pump the cycle's tally into the production graphs (collected = input,
--- fed = output on the lbf-items-moved item) and the global counter every
--- cycle; the optional flying-text summary is accumulated across cycles and
--- only actually shown every SUMMARY_INTERVAL_TICKS — at the default ~1s
--- per-player cycle a per-cycle flying text would be constant noise.
--- @param player LuaPlayer
--- @param surface LuaSurface where the transfers happened (the character's surface)
--- @param data LbfPlayerData
--- @param report LbfReport
--- @param summary_effective boolean `appearance_summary`'s effective state — a
---   tree child of `appearance` now (DESIGN.md §12), so an admin/parent-off
---   silences the summary the same way it silences every other render
function Report.flush(player, surface, data, report, summary_effective)
    local collected_total, fed_total = 0, 0
    for _, count in pairs(report.collected) do
        collected_total = collected_total + count
    end
    for _, count in pairs(report.fed) do
        fed_total = fed_total + count
    end
    if collected_total == 0 and fed_total == 0 then
        return
    end

    storage.items_moved = (storage.items_moved or 0) + collected_total + fed_total
    local stats = player.force.get_item_production_statistics(surface)
    if collected_total > 0 then
        stats.on_flow('lbf-items-moved', collected_total)
    end
    if fed_total > 0 then
        stats.on_flow('lbf-items-moved', -fed_total)
    end

    if not summary_effective then
        return
    end
    local summary = data.summary
    for name, count in pairs(report.collected) do
        summary.collected[name] = (summary.collected[name] or 0) + count
    end
    for name, count in pairs(report.fed) do
        summary.fed[name] = (summary.fed[name] or 0) + count
    end
    if game.tick < summary.next_flush then
        return
    end
    summary.next_flush = game.tick + SUMMARY_INTERVAL_TICKS

    local parts = {}
    for name, count in pairs(summary.collected) do
        parts[#parts + 1] = '[color=150,255,150]+' .. count .. '[/color] [item=' .. name .. ']'
    end
    for name, count in pairs(summary.fed) do
        parts[#parts + 1] = '[color=255,150,150]-' .. count .. '[/color] [item=' .. name .. ']'
    end
    summary.collected = {}
    summary.fed = {}
    if #parts > 0 then
        player.create_local_flying_text({
            text = table.concat(parts, '  '),
            position = player.position,
        })
    end
end

return Report
