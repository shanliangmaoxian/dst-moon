local containers = require("containers")
local Widget = require("widgets/widget")
local assert_utils = require("moon_utils/asserts")

if not _G.Moon_IsHHEnabled() then return end

local old_castspell_fn = GLOBAL.ACTIONS.CASTSPELL.fn

local EFFECT_NAME = "lmoon_effect_quickcast"
local TAG_NAME = "lmoon_quickcast"
local STATE_NAME = "lmoon_quickcast"

local function rand_range(min_or_max, max, interval)
    local min = max ~= nil and min_or_max or 0
    max = max ~= nil and max or min_or_max
    interval = interval or 0.01

    local min_step = math.ceil(min / interval)
    local max_step = math.floor(max / interval)

    if min_step > max_step then
        return min_step * interval
    end

    return math.random(min_step, max_step) * interval	
end

-- 根据物品 Tag 决定是否导向快速施法状态
AddStategraphPostInit("wilson", function(sg)
    local function forward_to_quickcast_from(forward_action)
        local old_deststate = sg.actionhandlers[forward_action].deststate
        local function redirected_deststate(inst, action)
            if action.invobject and action.invobject:HasTag(TAG_NAME) then
                return STATE_NAME
            end
            return old_deststate(inst, action)
        end
        sg.actionhandlers[forward_action] = GLOBAL.ActionHandler(forward_action, redirected_deststate)
    end

    -- 这些都是回退到 castspell 的 action，默认都是使用相同的施法动作
    forward_to_quickcast_from(GLOBAL.ACTIONS.CASTSPELL)
    forward_to_quickcast_from(GLOBAL.ACTIONS.CASTAOE)           -- 范围施法
    forward_to_quickcast_from(GLOBAL.ACTIONS.CASTSUMMON)        -- 召唤
    forward_to_quickcast_from(GLOBAL.ACTIONS.CASTUNSUMMON)      -- 取消召唤
end)

AddStategraphPostInit("wilson", function(sg)
	local state = GLOBAL.State{
        name = STATE_NAME,
        tags = { "doing", "busy", "canrotate" },

        onenter = function(inst)
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:Enable(false)
            end
            -- inst.AnimState:PlayAnimation("staff_pre")
            -- inst.AnimState:PushAnimation("staff", false)

			inst.AnimState:PlayAnimation("staff")
			inst.AnimState:SetTime(math.random(72 / 2 - 6, 72 / 2 + 6) * FRAMES)
			inst:DoTaskInTime(6 * FRAMES, function()
				inst.AnimState:SetTime(math.random(72 - 16, 72 - 16) * FRAMES)
			end)

            inst.components.locomotor:Stop()

            --Spawn an effect on the player's location
            local staff = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            local colour = staff ~= nil and staff.fxcolour or { 1, 1, 1 }

            inst.sg.statemem.stafffx = SpawnPrefab(inst.components.rider:IsRiding() and "staffcastfx_mount" or "staffcastfx")
            inst.sg.statemem.stafffx.entity:SetParent(inst.entity)
            inst.sg.statemem.stafffx:SetUp(colour)

            inst.sg.statemem.stafflight = SpawnPrefab("staff_castinglight")
            inst.sg.statemem.stafflight.Transform:SetPosition(inst.Transform:GetWorldPosition())
            inst.sg.statemem.stafflight:SetUp(colour, 1.9, .33)

			if staff ~= nil and staff.components.aoetargeting ~= nil then
                local buffaction = inst:GetBufferedAction()
				if buffaction ~= nil then
					inst.sg.statemem.targetfx = staff.components.aoetargeting:SpawnTargetFXAt(buffaction:GetDynamicActionPoint())
                    if inst.sg.statemem.targetfx ~= nil then
                        inst.sg.statemem.targetfx:ListenForEvent("onremove", OnRemoveCleanupTargetFX, inst)
                    end
                end
            end

            if staff ~= nil then
                inst.sg.statemem.castsound = staff.skin_castsound or staff.castsound or "dontstarve/wilson/use_gemstaff"
            else
                inst.sg.statemem.castsound = "dontstarve/wilson/use_gemstaff"
            end
        end,

        timeline =
        {
            TimeEvent(1 * FRAMES, function(inst)
                inst.SoundEmitter:PlaySound(inst.sg.statemem.castsound)
            end),
            TimeEvent(3 * FRAMES, function(inst)
                if inst.sg.statemem.targetfx ~= nil then
                    if inst.sg.statemem.targetfx:IsValid() then
                        OnRemoveCleanupTargetFX(inst)
                    end
                    inst.sg.statemem.targetfx = nil
                end
                inst.sg.statemem.stafffx = nil --Can't be cancelled anymore
                inst.sg.statemem.stafflight = nil --Can't be cancelled anymore
                --V2C: NOTE! if we're teleporting ourself, we may be forced to exit state here!
                inst:PerformBufferedAction()
            end),
			TimeEvent(8 * FRAMES, function(inst)
				inst.sg:RemoveStateTag("busy")
				if inst.components.playercontroller ~= nil then
					inst.components.playercontroller:Enable(true)
				end
			end),
        },

        events =
        {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },

        onexit = function(inst)
            if inst.components.playercontroller ~= nil then
                inst.components.playercontroller:Enable(true)
            end
            if inst.sg.statemem.stafffx ~= nil and inst.sg.statemem.stafffx:IsValid() then
                inst.sg.statemem.stafffx:Remove()
            end
            if inst.sg.statemem.stafflight ~= nil and inst.sg.statemem.stafflight:IsValid() then
                inst.sg.statemem.stafflight:Remove()
            end
            if inst.sg.statemem.targetfx ~= nil and inst.sg.statemem.targetfx:IsValid() then
                OnRemoveCleanupTargetFX(inst)
            end
        end,
    }

	sg.states[state.name] = state
end)

-- 修改后的状态动画用于适配快速施法，目前动画还有一些小问题，人物动画过早的进入结束状态，应该和服务器同步有关，不影响使用
local TIMEOUT = 1
AddStategraphPostInit("wilson_client", function (sg)
	local state = GLOBAL.State{
        name = STATE_NAME,
        tags = { "doing", "busy", "canrotate" },
		server_states = { "castspell" },

        onenter = function(inst)
            inst.components.locomotor:Stop()
            inst:PerformPreviewBufferedAction()
			
			inst.AnimState:PlayAnimation("staff")
			inst.AnimState:SetTime(math.random(72 / 2 - 6, 72 / 2 + 6) * FRAMES)
			inst:DoTaskInTime(6 * FRAMES, function()
				inst.AnimState:SetTime(math.random(72 - 16, 72 - 16) * FRAMES)
			end)

            inst.sg:SetTimeout(TIMEOUT)
        end,

        onupdate = function(inst)
			if inst.sg:ServerStateMatches() then
                if inst.entity:FlattenMovementPrediction() then
                    inst.sg:GoToState("idle", "noanim")
                end
            elseif inst.bufferedaction == nil then
                inst.sg:GoToState("idle")
            end
        end,

        ontimeout = function(inst)
            inst:ClearBufferedAction()
            inst.sg:GoToState("idle")
        end,
    }

	sg.states[state.name] = state
end)

AddPrefabPostInit("world", function(inst)
    -- 调试用的
    -- GLOBAL.TheInput:AddKeyDownHandler(GLOBAL.KEY_C, function()
    --     -- 1. 获取当前玩家实体
    --     local player = GLOBAL.ThePlayer
    --     if not player then
    --         return -- 没有玩家（如在主菜单）
    --     end

    --     -- 2. 确保当前处于游戏界面（避免在聊天、设置等界面误触）
    --     local activeScreen = GLOBAL.TheFrontEnd and
    --                              GLOBAL.TheFrontEnd:GetActiveScreen()
    --     if not activeScreen or activeScreen.name ~= "HUD" then return end

	-- 	if player and player.sg then
	-- 		if not player.sg:HasStateTag("busy") then
	-- 			player.sg:GoToState(STATE_NAME)
	-- 		end
	-- 	end
    -- end)

    GLOBAL.AddSpecialEquipEffect(EFFECT_NAME, {
        name = "快速施法",
        client_text = "速\n施法",
        desc = "快速施法",
        check_desc = "能施法的装备",
        recipes = {"lmoon_effect_stone_quickcast"},
        can_add = false,
        obtain_desc = "合成",
        obtains = {}, -- 空表表示无法随机掉落、附魔卷轴以及合成出来
        only_one = true,
        is_special = false,
        client_color = {0.8, 0, 0.8, 1},
        check_equip_can_add = function(inst)
            if assert_utils.is_spellcaster(inst) then
                return true, "满足条件"
            end
            return false, "仅能附魔在能施法的装备中"
        end,
        on_equip_fn = function(inst, owner, value)
			inst:AddTag(TAG_NAME)
		end,
        un_equip_fn = function(inst, owner, value)
			inst:RemoveTag(TAG_NAME)
		end,
    })

    _G.Moon_RegisterEnchantDrop(EFFECT_NAME, 0)
end)