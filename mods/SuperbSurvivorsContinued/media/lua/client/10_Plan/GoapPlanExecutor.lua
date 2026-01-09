
require "04_DataManagement/SuperSurvivorsMod" -- For logging and globals if needed
require "00_SuperbSurviorModVariables/LoggingFunctions"

GoapPlanExecutor = {}
GoapPlanExecutor.__index = GoapPlanExecutor

-- Execution Status Enums
GoapPlanExecutor.STATUS = {
    RUNNING = 0,
    SUCCESS = 1,
    FAILED = 2
}

function GoapPlanExecutor:derive(typeName)
    local class = {}
    setmetatable(class, self)
    class.__index = class
    class.Type = typeName
    return class
end

function GoapPlanExecutor:new(superSurvivor)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.parent = superSurvivor
    o.Name = "Goap Plan" -- Should be overridden
    o.Complete = false
    
    o.planner = nil 
    o.currentPlan = nil
    o.currentStepIndex = 1
    o.currentActionName = nil
    
    o.Context = {} -- Blackboard for passing data between actions (e.g. found targets)
    
    return o
end

function GoapPlanExecutor:isComplete()
    return self.Complete
end

function GoapPlanExecutor:isValid()
    return self.parent ~= nil
end

function GoapPlanExecutor:ForceComplete()
    self.Complete = true
end

function GoapPlanExecutor:OnComplete()
    -- Cleanup if needed
end

-- Main update loop called by TaskManager
function GoapPlanExecutor:update()
    if not self:isValid() then return false end
    if self.Complete then return true end

    -- 1. Initialize Planner / Re-plan if needed
    if not self.planner then
        self:setupPlanner() -- Abstract method, must be implemented by subclass
        if not self.planner then
            logDebug("GoapPlanExecutor: No planner setup. Completing.")
            self.Complete = true
            return false
        end
    end

    if not self.currentPlan then
        self:updateWorldState() -- Sync planner state with game reality
        logDebug(self.Name .. ": Calculating plan...")
        self.currentPlan = self.planner:calculate()
        
        if self.currentPlan == nil then
            logDebug(self.Name .. ": No plan found. Task Failed.")
            logDebug("Start State:", self.planner.start_state)
            logDebug("Goal State:", self.planner.goal_state)
            self.Complete = true
            return false
        elseif #self.currentPlan == 0 then
            logDebug(self.Name .. ": Goal already satisfied (Empty Plan).")
            self.Complete = true
            return true
        else
            local planSteps = {}
            for i, node in ipairs(self.currentPlan) do
                table.insert(planSteps, i .. ": " .. node.name)
            end
            logDebug(self.Name .. ": Plan found: ", planSteps)
            self.currentStepIndex = 1
        end
    end

    -- 2. Execute current step
    local planNode = self.currentPlan[self.currentStepIndex]
    if not planNode then
        logDebug(self.Name .. ": All plan steps completed.")
        self.Complete = true
        return true
    end

    if self.currentActionName ~= planNode.name then
        logDebug(self.Name .. ": Switching to Action [" .. self.currentStepIndex .. "/" .. #self.currentPlan .. "]: " .. planNode.name)
        self.currentActionName = planNode.name
    end
    
    -- Dispatch to specific handler
    local status = self:dispatchAction(self.currentActionName)

    -- 3. Handle Status
    if status == self.STATUS.SUCCESS then
        logDebug(self.Name .. ": Action '" .. self.currentActionName .. "' returned SUCCESS.")
        self.currentStepIndex = self.currentStepIndex + 1
    elseif status == self.STATUS.FAILED then
        logDebug(self.Name .. ": Action '" .. self.currentActionName .. "' returned FAILED. Triggering re-plan.")
        self.currentPlan = nil -- Force re-plan
        self.Context = {} -- Optionally clear context
    elseif status == self.STATUS.RUNNING then
        -- Optional: uncomment for extremely verbose per-tick execution logs
        -- logDebug(self.Name .. ": Action '" .. self.currentActionName .. "' is RUNNING...")
    end
end

function GoapPlanExecutor:dispatchAction(actionName)
    -- Try exact match first: e.g. "ensureResources" -> self:action_ensureResources()
    local func = self["action_" .. actionName]
    if func then
        return func(self)
    end

    -- Try prefix match for numbered actions: e.g. "findWindow1" -> self:action_findWindow(1)
    -- We assume the number is at the end
    local prefix, num = actionName:match("^(%a+)(%d+)$")
    if prefix and num then
        func = self["action_" .. prefix]
        if func then
            return func(self, tonumber(num))
        end
    end

    logDebug("GoapPlanExecutor: No handler found for action: " .. actionName)
    return self.STATUS.FAILED
end

-- Abstract methods to be implemented by concrete classes
function GoapPlanExecutor:setupPlanner()
    error("setupPlanner not implemented")
end

function GoapPlanExecutor:updateWorldState()
    error("updateWorldState not implemented")
end

return GoapPlanExecutor
