
require "04_DataManagement/SuperSurvivorsMod" -- For logging and globals if needed

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
            print("GoapPlanExecutor: No planner setup. Completing.")
            self.Complete = true
            return false
        end
    end

    if not self.currentPlan then
        self:updateWorldState() -- Sync planner state with game reality
        print(self.Name .. ": Calculating plan...")
        self.currentPlan = self.planner:calculate()
        
        if not self.currentPlan or #self.currentPlan == 0 then
            print(self.Name .. ": No plan found. Task Failed.")
            self.Complete = true
            return false
        else
            print(self.Name .. ": Plan found with " .. #self.currentPlan .. " steps.")
            self.currentStepIndex = 1
        end
    end

    -- 2. Execute current step
    local planNode = self.currentPlan[self.currentStepIndex]
    if not planNode then
        print(self.Name .. ": Plan finished successfully.")
        self.Complete = true
        return true
    end

    self.currentActionName = planNode.name
    
    -- Dispatch to specific handler
    -- We match action names to function names. 
    -- E.g. "findWindow1" matches handler "action_findWindow" (stripping numbers) or exact match
    local status = self:dispatchAction(self.currentActionName)

    -- 3. Handle Status
    if status == self.STATUS.SUCCESS then
        -- print(self.Name .. ": Action '" .. self.currentActionName .. "' SUCCESS.")
        self.currentStepIndex = self.currentStepIndex + 1
    elseif status == self.STATUS.FAILED then
        print(self.Name .. ": Action '" .. self.currentActionName .. "' FAILED. Triggering re-plan.")
        self.currentPlan = nil -- Force re-plan
        self.Context = {} -- Optionally clear context
    elseif status == self.STATUS.RUNNING then
        -- Continue next tick
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

    print("GoapPlanExecutor: No handler found for action: " .. actionName)
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
