
require "10_Plan/GoapPlanExecutor"
require "00_SuperbSurviorModVariables/LoggingFunctions"
local goap = require("09_GOAP/01_init")
local BarricadeTaskFactory = require("09_GOAP/tasks/barricade")

BarricadeAllPlan = GoapPlanExecutor:derive("BarricadeAllPlan")

function BarricadeAllPlan:new(superSurvivor)
    local o = GoapPlanExecutor.new(self, superSurvivor)
    o.Name = "Barricade All Plan"
    return o
end

function BarricadeAllPlan:setupPlanner()
    -- Initialize the planner with the domain states
    self.planner = goap.Planner(
        "hasHammer", "hasPlank", "hasNails", 
        "is_building_secured", "hasTarget", "nearWindow", "equipped"
    )

    -- Define the actions for the "Iterative" strategy (looping)
    local actions = BarricadeTaskFactory.create_iterative_actions()
    self.planner:set_action_list(actions)
    
    -- Set the Goal: Building must be secured
    self.planner:set_goal_state({ is_building_secured = true })
    
    -- Heuristic
    self.planner:set_heuristic("rpg_add")
end

function BarricadeAllPlan:update()
    -- 1. Standard Update (Runs one plan cycle: Find -> Barricade)
    local result = GoapPlanExecutor.update(self)
    
    -- 2. Intercept Completion
    if self.Complete then
        -- Check if we are truly done
        self:updateWorldState() -- Update planner start_state from reality
        local state = self.planner.start_state
        
        if state.is_building_secured == false then
            -- We are not done. Reset for the next loop.
            logDebug("BarricadeAllPlan: One window done (or plan failed), but building not secured. Re-planning.")
            self.Complete = false
            self.currentPlan = nil
            self.currentStepIndex = 1
            
            -- If the previous plan failed, we might need to be careful not to infinite loop on an impossible task.
            -- But for now, we assume the planner will fail gracefully if no actions are possible (e.g. out of wood).
            
            return false -- Keep running
        end
    end
    
    return result
end

function BarricadeAllPlan:updateWorldState()
    local inv = self.parent.player:getInventory()
    
    -- Check Inventory
    local hasHammer = inv:containsTag("Hammer") or inv:containsType("Base.Hammer") or inv:containsType("Base.HammerStone")
    local hasPlank = inv:containsType("Base.Plank")
    local hasNails = inv:getItemCount("Base.Nails", true) >= 2
    
    -- Check Context
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
        local pValid = primary and (primary:hasTag("Hammer") or primary:getType() == "Hammer" or primary:getType() == "HammerStone")
        local sValid = secondary and (secondary:getType() == "Plank")
        equipped = (pValid and sValid) and true or false
    end
    
    -- Check Building Security (The "Iterative" Logic)
    local is_secured = true
    local building = self.parent:getBuilding()
    
    if building then
        -- If we already have a target, we are obviously not secured yet (we are working on it)
        -- But for the sake of the Loop check, we need to know if there are *other* windows or if this is the last one.
        -- Actually, updateWorldState is called *before* planning.
        -- If we have no target, we scan.
        if not hasTarget then
            local nextWindow = self.parent:getUnBarricadedWindow(building)
            if nextWindow then
                is_secured = false
            else
                is_secured = true
            end
        else
            -- We have a target, so we are not secured yet (this window is open)
            is_secured = false
        end
    else
        -- No building? We consider it "secured" (nothing to do) to stop the loop.
        is_secured = true
    end

    self.planner:set_start_state({
        hasHammer = hasHammer,
        hasPlank = hasPlank,
        hasNails = hasNails,
        is_building_secured = is_secured,
        hasTarget = hasTarget,
        nearWindow = nearWindow,
        equipped = equipped
    })
end

------------------------------------------------------------------------
-- ACTION HANDLERS
------------------------------------------------------------------------

function BarricadeAllPlan:action_ensureResources()
    local inv = self.parent.player:getInventory()
    
    -- Cheat/Magic logic (reused from BarricadePlan)
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

function BarricadeAllPlan:action_findWindow()
    local building = self.parent:getBuilding()
    if not building then
        return self.STATUS.FAILED
    end
    
    local window = self.parent:getUnBarricadedWindow(building)
    
    if window then
        self.Context.TargetWindow = window
        logDebug("BarricadeAllPlan: Found window at " .. window:getX() .. "," .. window:getY())
        return self.STATUS.SUCCESS
    else
        return self.STATUS.FAILED
    end
end

function BarricadeAllPlan:action_walkToWindow()
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

function BarricadeAllPlan:action_equipTools()
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

function BarricadeAllPlan:action_barricadeWindow()
    local window = self.Context.TargetWindow
    if not window then return self.STATUS.FAILED end
    
    local barricade = window:getBarricadeForCharacter(self.parent.player)
    if barricade and not barricade:canAddPlank() then
        -- Fully barricaded, job done for this window
        self.Context.TargetWindow = nil 
        return self.STATUS.SUCCESS
    end

    local inv = self.parent.player:getInventory()
    local hasPlank = inv:containsType("Base.Plank")
    local hasNails = inv:getItemCount("Base.Nails", true) >= 2
    local hasHammer = inv:containsTag("Hammer") or inv:containsType("Base.Hammer") or inv:containsType("Base.HammerStone")

    if not (hasPlank and hasNails and hasHammer) then
        return self.STATUS.FAILED
    end

    if self.parent:isInAction() then
        return self.STATUS.RUNNING
    end
    
    ISTimedActionQueue.add(ISBarricadeAction:new(self.parent.player, window, false, false, 100))
    return self.STATUS.RUNNING
end

return BarricadeAllPlan
