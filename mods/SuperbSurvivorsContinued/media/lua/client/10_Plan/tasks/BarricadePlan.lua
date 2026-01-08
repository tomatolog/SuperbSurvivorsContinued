
require "10_Plan/GoapPlanExecutor"
local goap = require("09_GOAP/01_init")
local BarricadeTaskFactory = require("09_GOAP/tasks/barricade")

BarricadePlan = GoapPlanExecutor:derive("BarricadePlan")

function BarricadePlan:new(superSurvivor)
    local o = GoapPlanExecutor.new(self, superSurvivor)
    o.Name = "Barricade Plan"
    o.windowsToBarricade = 1 -- Default for now, could be dynamic
    return o
end

function BarricadePlan:setupPlanner()
    -- Initialize the planner with the domain states
    self.planner = goap.Planner(
        "hasHammer", "hasPlank", "hasNails", 
        "windowsRemaining", "hasTarget", "nearWindow", "equipped"
    )

    -- Define the actions for N windows
    local actions = BarricadeTaskFactory.create_actions(self.windowsToBarricade)
    self.planner:set_action_list(actions)
    
    -- Set the Goal: no windows left to barricade
    self.planner:set_goal_state({ windowsRemaining = 0 })
    
    -- Heuristic (optional)
    self.planner:set_heuristic("rpg_add")
end

function BarricadePlan:updateWorldState()
    local inv = self.parent.player:getInventory()
    
    -- Check Inventory
    local hasHammer = inv:containsTag("Hammer") or inv:containsType("Base.Hammer") or inv:containsType("Base.HammerStone")
    local hasPlank = inv:containsType("Base.Plank")
    local hasNails = inv:getItemCount("Base.Nails", true) >= 2 -- Need at least 2 nails per plank usually
    
    -- Check Context for ongoing state
    local hasTarget = (self.Context.TargetWindow ~= nil)
    local nearWindow = false
    local equipped = false
    
    if hasTarget then
        local dist = GetDistanceBetween(self.parent.player, self.Context.TargetWindow:getIndoorSquare())
        nearWindow = (dist <= 2) and (self.parent.player:getZ() == self.Context.TargetWindow:getZ())
    end

    if hasHammer and hasPlank then
        local primary = self.parent.player:getPrimaryHandItem()
        local secondary = self.parent.player:getSecondaryHandItem()
        -- specific check for hammer/plank equipped
        local pValid = primary and (primary:hasTag("Hammer") or primary:getType() == "Hammer" or primary:getType() == "HammerStone")
        local sValid = secondary and (secondary:getType() == "Plank")
        equipped = pValid and sValid
    end
    
    -- Set Start State
    -- windowsRemaining is a bit tricky; if we are re-planning in the middle, we need to know how many are left.
    -- For now, we assume if we lost our plan, we reset to 'windowsToBarricade' or 1.
    -- A better way is to check the context or just assume 1 if we are doing them one by one.
    local currentWindows = self.windowsToBarricade
    if self.Context.WindowsDone then
        currentWindows = self.windowsToBarricade - self.Context.WindowsDone
    end
    if currentWindows < 0 then currentWindows = 0 end

    self.planner:set_start_state({
        hasHammer = hasHammer,
        hasPlank = hasPlank,
        hasNails = hasNails,
        windowsRemaining = currentWindows,
        hasTarget = hasTarget,
        nearWindow = nearWindow,
        equipped = equipped
    })
end

------------------------------------------------------------------------
-- ACTION HANDLERS
------------------------------------------------------------------------

function BarricadePlan:action_ensureResources()
    local inv = self.parent.player:getInventory()
    
    -- Cheat/Magic logic from original BarricadeBuildingTask:
    if not inv:FindAndReturn("Hammer") then
        inv:AddItem("Base.Hammer")
    end
    if not inv:FindAndReturn("Plank") then
        inv:AddItem("Base.Plank")
    end
    if inv:getItemCount("Base.Nails", true) < 2 then
        inv:AddItem(instanceItem("Base.Nails"))
        inv:AddItem(instanceItem("Base.Nails"))
    end
    
    return self.STATUS.SUCCESS
end

function BarricadePlan:action_findWindow(n)
    local building = self.parent:getBuilding()
    if not building then
        print("BarricadePlan: No building found.")
        return self.STATUS.FAILED
    end
    
    -- Use the existing helper to find a window
    local window = self.parent:getUnBarricadedWindow(building)
    
    if window then
        self.Context.TargetWindow = window
        print("BarricadePlan: Found window at " .. window:getX() .. "," .. window:getY())
        return self.STATUS.SUCCESS
    else
        print("BarricadePlan: No unbarricaded window found.")
        return self.STATUS.FAILED
    end
end

function BarricadePlan:action_walkToWindow()
    if not self.Context.TargetWindow then
        return self.STATUS.FAILED
    end
    
    local targetSq = self.Context.TargetWindow:getIndoorSquare()
    local dist = GetDistanceBetween(self.parent.player, targetSq)
    
    if dist <= 2 and self.parent.player:getZ() == targetSq:getZ() then
        self.parent:StopWalk()
        return self.STATUS.SUCCESS
    end
    
    self.parent:walkTo(targetSq)
    return self.STATUS.RUNNING
end

function BarricadePlan:action_equipTools()
    local inv = self.parent.player:getInventory()
    local hammer = inv:FindAndReturn("Hammer")
    local plank = inv:FindAndReturn("Plank")
    
    if hammer and plank then
        self.parent.player:setPrimaryHandItem(hammer)
        self.parent.player:setSecondaryHandItem(plank)
        return self.STATUS.SUCCESS
    else
        return self.STATUS.FAILED
    end
end

function BarricadePlan:action_barricadeWindow(n)
    local window = self.Context.TargetWindow
    if not window then return self.STATUS.FAILED end
    
    -- If already barricaded, we are done
    local barricade = window:getBarricadeForCharacter(self.parent.player)
    if barricade and not barricade:canAddPlank() then
        self.Context.TargetWindow = nil -- Clear target
        self.Context.WindowsDone = (self.Context.WindowsDone or 0) + 1
        return self.STATUS.SUCCESS
    end
    
    -- Check if we are currently performing the action
    if self.parent:isInAction() then
        return self.STATUS.RUNNING
    end
    
    -- Start Action
    ISTimedActionQueue.add(ISBarricadeAction:new(self.parent.player, window, false, false, 100))
    
    -- We return RUNNING so that next update we check isInAction()
    -- However, once the action is queued, isInAction might not be true immediately in the same tick?
    -- Usually it's safer to return RUNNING and let the next tick catch the action progress.
    -- But we need a way to detect "Action Just Finished". 
    -- If we aren't in action, and we just added it, we assume it starts. 
    -- If we aren't in action and we are here again, it means it finished? 
    -- A simple check is: if the window state changed.
    
    -- Let's try: if we are NOT in action, we queue it. 
    -- But we need to know if we already queued it.
    -- A flag in Context?
    
    if not self.Context.ActionQueued then
        self.Context.ActionQueued = true
        return self.STATUS.RUNNING
    else
        -- We queued it previously. If we are not in action now, it means it finished (or failed start).
        self.Context.ActionQueued = false -- Reset
        self.Context.TargetWindow = nil -- Clear target
        self.Context.WindowsDone = (self.Context.WindowsDone or 0) + 1
        return self.STATUS.SUCCESS
    end
end

return BarricadePlan
