--- Shortcut + hotkey handling. The shortcut is the player's own on/off switch — same per-player master as the relative panel's switch (data.settings.mod), kept in sync both ways through State.set_player_master. Global (everyone) control lives in the admin panel only; in singleplayer, switching on also re-arms the global masters. Blocked by admin control (global "Everyone" off or a per-player lock) the same way relative.lua's checkboxes are — see admin_blocked.

local State = require('__lazy-bastards-friend__.scripts.state')

local Shortcut = {}

--- Keep the toggle indicator and clickability in sync with the player's master switch and any admin-side block. Registered as a State refresh handler; unavailable disables the toolbar button, but the hotkey still reaches Shortcut.toggle, which re-checks and blocks it there.
--- @param player LuaPlayer
function Shortcut.sync(player)
    local data = State.get_player_data(player.index)
    player.set_shortcut_toggled('lbf-toggle', data.settings.mod.enabled)
    local _, reason = State.tree:admin_blocked(storage.settings, data.settings, 'mod')
    player.set_shortcut_available('lbf-toggle', reason == nil)
end

--- @param player LuaPlayer
function Shortcut.toggle(player)
    -- Mirrors the greyed-out master switch: blocked by the global "Everyone" switch or a per-player admin lock.
    local data = State.get_player_data(player.index)
    local _, reason = State.tree:admin_blocked(storage.settings, data.settings, 'mod')
    if reason then
        player.create_local_flying_text({
            text = reason == 'global' and { 'lbf-gui.master-off' } or { 'lbf-gui.locked-by-admin' },
            create_at_cursor = true,
        })
        return
    end
    State.set_player_master(player, not data.settings.mod.enabled)
    State.refresh(player)
end

return Shortcut
