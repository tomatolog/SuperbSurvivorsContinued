local goap = require("09_GOAP/01_init")
require "10_Plan/tasks/BarricadePlan"
require "04_Group.SuperSurvivorManager"

local goap_test = {}

function goap_test.UI_test()
    logPretty("function: goap_test.UI_test() called");
    -- Existing test code preserved...
    logPretty('[goap] work!!!')        
    local World = goap.World
    local Planner = goap.Planner
    local Action = goap.Action
    local world = Planner('hungry', 'has_food', 'in_kitchen', 'tired', 'in_bed')
    world:set_start_state({hungry=true, has_food=false, in_kitchen=false, tired=true, in_bed=false})
    world:set_goal_state({tired=false,has_food=true})
    local actions = Action()
    actions:add_condition('eat', {hungry=true, has_food=true, in_kitchen=false})
    actions:add_reaction('eat', {hungry=false,has_food=false})

    actions:add_condition('cook', {hungry=true, has_food=false, in_kitchen=true})
    actions:add_reaction('cook', {has_food=true})
    actions:add_condition('sleep', {tired=true, in_bed=true})
    actions:add_reaction('sleep', {tired=false})
    actions:add_condition('go_to_bed', {in_bed=false, hungry=false})
    actions:add_reaction('go_to_bed', {in_bed=true})
    actions:add_condition('go_to_kitchen', {in_bed=false,in_kitchen=false})
    actions:add_reaction('go_to_kitchen', {in_kitchen=true})
    actions:add_condition('leave_kitchen', {in_kitchen=true})
    actions:add_reaction('leave_kitchen', {in_kitchen=false})
    actions:add_condition('order_pizza', {has_food=false, hungry=true})
    actions:add_reaction('order_pizza', {has_food=true})
    actions:add_condition("sleep_up",{in_bed=true})
    actions:add_reaction("sleep_up",{in_bed=false,hungry=true})
    actions:set_weight('go_to_kitchen', 2)
    actions:set_weight('order_pizza', 20)
    actions:set_weight('eat', 1)
    actions:set_weight('cook', 1)
    actions:set_weight('sleep', 1)
    actions:set_weight('go_to_bed', 1)
    actions:set_weight('leave_kitchen', 1)
    actions:set_weight('sleep_up', 1)

    world:set_action_list(actions)

    local tmStart = getTimestampMs()
    local path = world:calculate()
    local took_time = getTimestampMs() - tmStart 

    for k,_p in pairs(path) do 
        logPretty(k, _p['name'])
    end 

    logPretty ('[goap] Took: %d ms', took_time)
end

function goap_test.GiveBarricadeOrder(member_index)
    local group_id = SSM:Get(0):getGroupID()
    local group_members = SSGM:GetGroupById(group_id):getMembers()
    local member = group_members[member_index]
    
    if member then
        getSpecificPlayer(0):Say("Ordering " .. member:getName() .. " to Barricade (GOAP)")
        
        -- Create the new plan task
        local task = BarricadePlan:new(member)
        
        -- Add to task manager
        member:getTaskManager():AddToTop(task)
        
        -- Set Role (Optional, but good for UI)
        member:setGroupRole("Worker")
    end
end

return goap_test