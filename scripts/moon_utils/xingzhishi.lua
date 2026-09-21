local M = { EFFECT_ID = "Moon_XINGZHISHI", PRODUCT = "lmoon_effect_stone_xingzhishi" }

function M.HasEffect(box)
    local hh = box and box.components and box.components.hh_equip
    return box and box.prefab == "ccs_card_box" and hh
        and hh:HasEffectByName(M.EFFECT_ID) or false
end

function M.IsActive(player)
    if not player or player.prefab ~= "ccs" or player:HasTag("playerghost") then return false end
    local inventory = TheWorld.ismastersim and player.components.inventory or player.replica.inventory
    if not inventory then return false end
    for _, slot in pairs(EQUIPSLOTS) do
        local box = inventory:GetEquippedItem(slot)
        if box and box.prefab == "ccs_card_box" then
            if TheWorld.ismastersim then
                if M.HasEffect(box) then return true end
            elseif box._lmoon_xingzhishi and box._lmoon_xingzhishi:value() then
                return true
            end
        end
    end
    return false
end

function M.Refill(player)
    if M.IsActive(player) and player.components.ccs_magic then
        local magic = player.components.ccs_magic
        magic:DoDelta(math.max(0, magic.max - magic.current), "xingzhishi")
    end
end

function M.InstallSealState(sg)
    if sg.states.lmoon_xingzhishi_seal then return end
    local original = sg.states.ccs_seal_magic
    local handler = ACTIONS.CCS_SEAL and sg.actionhandlers[ACTIONS.CCS_SEAL]
    if not original or not handler then return end
    local state = setmetatable({}, getmetatable(original))
    for key, value in pairs(original) do state[key] = value end
    state.name = "lmoon_xingzhishi_seal"
    if sg.name == "wilson_client" then
        state.server_states = { [hash(state.name)] = true }
    end
    state.timeline = {}
    local action_time = 2 * FRAMES
    local end_time = action_time
    for _, event in ipairs(original.timeline or {}) do
        local copy = setmetatable({}, getmetatable(event))
        for key, value in pairs(event) do copy[key] = value end
        if copy.time > action_time then
            copy.time = action_time + (copy.time - action_time) / 100
        end
        end_time = math.max(end_time, copy.time)
        state.timeline[#state.timeline + 1] = copy
    end
    state.onenter = function(inst, ...)
        original.onenter(inst, ...)
        inst.sg:SetTimeout(end_time + FRAMES)
    end
    state.onexit = function(inst, ...)
        if original.onexit then original.onexit(inst, ...) end
        inst.AnimState:Resume()
        inst.AnimState:SetDeltaTimeMultiplier(1)
    end
    sg.states[state.name] = state
    local destination = handler.deststate
    handler.deststate = function(inst, action, ...)
        local result = destination
        if type(destination) == "function" then result = destination(inst, action, ...) end
        if result == "ccs_seal_magic" and M.IsActive(inst) then return state.name end
        return result
    end
end

return M
