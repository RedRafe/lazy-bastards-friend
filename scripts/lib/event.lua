--- Additive `script.X` wiring: lets multiple modules subscribe to the same
--- event — including the lifecycle events — without clobbering each other's
--- registration. Every `script.on_event` / `on_init` / `on_load` /
--- `on_configuration_changed` call *replaces* whatever handler was previously
--- registered, so two independent modules calling the same one directly
--- silently drop the first; only the last registrant wins. Every event
--- registration in this mod (control.lua, test-bench levels) goes through
--- `Event` instead of calling `script.X` directly — one real `script.X` call
--- per event, fanning out to every handler added, in registration order —
--- so ordering between modules never matters and nothing gets dropped.
--- Same idea covers `script.on_nth_tick`: scheduler.lua and watchdog.lua each
--- pick their own interval today (601 vs. up to 600, deliberately disjoint —
--- see watchdog.lua), but that's an invariant someone has to remember, not a
--- guarantee. Registering nth-tick handlers through `Event` as well removes
--- the need for it: two handlers on the same interval fan out instead of the
--- second clobbering the first.
---
--- Modeled after the dispatcher pattern in reference/event.lua and
--- data/core/lualib/event_handler.lua, trimmed to what this mod needs: no
--- tokens; removal is by handler reference, not by token.

local Event = {}

--- @type table<uint|string, fun(event)[]>
local handlers = {}

--- Register `handler` to run whenever `event_id` fires, without replacing any
--- handler already registered for that event by this or another module.
--- @param event_id defines.events|string
--- @param handler fun(event)
function Event.add(event_id, handler)
    local list = handlers[event_id]
    if not list then
        list = {}
        handlers[event_id] = list
        script.on_event(event_id, function(event)
            for i = 1, #list do
                list[i](event)
            end
        end)
    end
    list[#list + 1] = handler
end

--- @type table<uint, fun(event: NthTickEventData)[]>
local nth_tick_handlers = {}

--- Register `handler` to run every `interval` ticks, without replacing any
--- handler already registered for that interval by this or another module.
--- @param interval uint
--- @param handler fun(event: NthTickEventData)
function Event.on_nth_tick(interval, handler)
    local list = nth_tick_handlers[interval]
    if not list then
        list = {}
        nth_tick_handlers[interval] = list
        script.on_nth_tick(interval, function(event)
            for i = 1, #list do
                list[i](event)
            end
        end)
    end
    list[#list + 1] = handler
end

--- Unregister `handler` from `interval`. Once the last handler for an
--- interval is removed, the real `script.on_nth_tick` registration is torn
--- down too (so an idle interval costs nothing, per scheduler.lua/watchdog.lua).
--- @param interval uint
--- @param handler fun(event: NthTickEventData)
function Event.remove_nth_tick(interval, handler)
    local list = nth_tick_handlers[interval]
    if not list then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        script.on_nth_tick(interval, nil)
        nth_tick_handlers[interval] = nil
    end
end

--- Builds an additive registrar for a lifecycle slot (on_init/on_load/
--- on_configuration_changed): one real `script_fn` call, fanning out to every
--- handler added, in registration order.
--- @param script_fn fun(handler: fun(event: table?))
--- @return fun(handler: fun(event: table?))
local function make_lifecycle(script_fn)
    local list = {}
    local registered = false
    return function(handler)
        list[#list + 1] = handler
        if not registered then
            registered = true
            script_fn(function(event)
                for i = 1, #list do
                    list[i](event)
                end
            end)
        end
    end
end

--- Register a handler to run on `script.on_init`, without replacing any
--- handler already registered by another module.
--- @param handler fun()
Event.on_init = make_lifecycle(script.on_init)

--- Register a handler to run on `script.on_load`, without replacing any
--- handler already registered by another module.
--- @param handler fun()
Event.on_load = make_lifecycle(script.on_load)

--- Register a handler to run on `script.on_configuration_changed`, without
--- replacing any handler already registered by another module.
--- @param handler fun(data: ConfigurationChangedData)
Event.on_configuration_changed = make_lifecycle(script.on_configuration_changed)

return Event
