local QBCore = exports['qb-core']:GetCoreObject()
local impoundedVehicles = {}
local activeImpounds = {}
local OutsideVehicles = {}
local trackedJobVehicles = {}
local occupiedJobParkingSpots = {}
local jobVehicles = {}
local vehicleUpdateQueue = {}
local vehicleUpdateCooldown = {} -- Track last update time per vehicle
local vehicleUpdateProcessing = {} -- Track which plates are currently being processed (prevents concurrent updates)
local UPDATE_COOLDOWN = 90 -- Minimum seconds between updates per vehicle (increased to reduce deadlocks)
local playerVehicles = {} -- Track which vehicle each player is currently in: {source = plate}



QBCore.Functions.CreateCallback('dw-garages:server:GetPersonalVehicles', function(source, cb, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    local query = 'SELECT *, COALESCE(is_favorite, 0) as is_favorite FROM player_vehicles WHERE citizenid = ?'
    local params = {citizenid}
    
    if garageId then
        query = query .. ' AND garage = ?'
        table.insert(params, garageId)
    end
    
    MySQL.Async.fetchAll(query, params, function(result)
        if result[1] then
            cb(result)
        else
            cb({})
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetVehiclesByGarage', function(source, cb, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE garage = ?', {garageId}, function(result)
        if result and #result > 0 then
            cb(result)
        else
            cb({})
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetPlayerOutVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND state = 0', {citizenid}, function(result)
        if result and #result > 0 then
            cb(result)
        else
            cb({})
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetGangVehicles', function(source, cb, gang, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND garage = ?', {citizenid, garageId}, function(personalResult)
        MySQL.Async.fetchAll('SELECT pv.* FROM player_vehicles pv JOIN gang_vehicles gv ON pv.plate = gv.plate WHERE gv.gang = ? AND pv.citizenid != ? AND gv.stored = 1 AND pv.garage = ?', 
        {gang, citizenid, garageId}, function(gangResult)
            local allVehicles = {}
            
            for _, vehicle in ipairs(personalResult) do
                table.insert(allVehicles, vehicle)
            end
            
            for _, vehicle in ipairs(gangResult) do
                table.insert(allVehicles, vehicle)
            end
            
            cb(allVehicles)
        end)
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:CheckOwnership', function(source, cb, plate, garageType)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, false) end
    
    local citizenid = Player.PlayerData.citizenid
    local isOwner = false
    local isInGarage = false
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result[1] then
            -- Check if player owns the vehicle
            if result[1].citizenid == citizenid then
                isOwner = true
            end
            
            -- Check if vehicle is in a shared garage the player has access to
            if result[1].shared_garage_id and not isOwner then
                local sharedGarageId = result[1].shared_garage_id
                -- Check if player is a member of this shared garage
                MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
                    {sharedGarageId, citizenid}, function(memberResult)
                        if memberResult and #memberResult > 0 then
                            isInGarage = true
                            cb(isOwner, isInGarage)
                        else
                            -- Check if player is the owner of the shared garage
                            MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                                {sharedGarageId, citizenid}, function(ownerResult)
                                    if ownerResult and #ownerResult > 0 then
                                        isInGarage = true
                                    end
                                    cb(isOwner, isInGarage)
                                end
                            )
                        end
                    end
                )
                return
            end
            
            -- Check gang vehicles
            if garageType == "gang" and not isOwner then
                local gang = Player.PlayerData.gang.name
                if gang and gang ~= "none" then
                    MySQL.Async.fetchAll('SELECT * FROM gang_vehicles WHERE plate = ? AND gang = ?', {plate, gang}, function(gangResult)
                        if gangResult[1] then
                            isInGarage = true
                        end
                        cb(isOwner, isInGarage)
                    end)
                else
                    cb(isOwner, isInGarage)
                end
            else
                cb(isOwner, isInGarage)
            end
        else
            cb(isOwner, isInGarage)
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:CheckSharedAccess', function(source, cb, plate, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
    {garageId, citizenid}, function(memberResult)
        if memberResult and #memberResult > 0 then
            MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND shared_garage_id = ? AND state = 1', 
            {plate, garageId}, function(vehResult)
                if vehResult and #vehResult > 0 then
                    cb(true)
                else
                    cb(false)
                end
            end)
        else
            MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
            {garageId, citizenid}, function(ownerResult)
                if ownerResult and #ownerResult > 0 then
                    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND shared_garage_id = ? AND state = 1', 
                    {plate, garageId}, function(vehResult)
                        if vehResult and #vehResult > 0 then
                            cb(true)
                        else
                            cb(false)
                        end
                    end)
                else
                    cb(false)
                end
            end)
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetVehicleProperties', function(source, cb, plate)
    MySQL.Async.fetchAll('SELECT mods FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result[1] then
            cb(json.decode(result[1].mods))
        else
            cb(nil)
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetAllGarages', function(source, cb)
    local garages = {}
    
    for k, v in pairs(Config.Garages) do
        table.insert(garages, {id = k, name = v.label, type = "public"})
    end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if Player then
        if Player.PlayerData.job then
            for k, v in pairs(Config.JobGarages) do
                if v.job == Player.PlayerData.job.name then
                    table.insert(garages, {id = k, name = v.label, type = "job"})
                end
            end
        end
        
        if Player.PlayerData.gang and Player.PlayerData.gang.name ~= "none" then
            for k, v in pairs(Config.GangGarages) do
                if v.gang == Player.PlayerData.gang.name then
                    table.insert(garages, {id = k, name = v.label, type = "gang"})
                end
            end
        end
    end
    
    cb(garages)
end)

RegisterNetEvent('dw-garages:server:TransferVehicleToGarage', function(plate, newGarageId, cost)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "You don't own this vehicle", "error")
            TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
            return
        end
        local vehicle = result[1]
        if vehicle.state ~= 1 then
            TriggerClientEvent('QBCore:Notify', src, "Vehicle must be stored to transfer it", "error")
            TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
            return
        end
        local transferCost = cost or Config.TransferCost or 500
        if Player.PlayerData.money["cash"] < transferCost then
            TriggerClientEvent('QBCore:Notify', src, "You need $" .. transferCost .. " to transfer this vehicle", "error")
            TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
            return
        end
        Player.Functions.RemoveMoney("cash", transferCost, "vehicle-transfer-fee")
        MySQL.Async.execute('UPDATE player_vehicles SET garage = ? WHERE plate = ?', {newGarageId, plate}, function(rowsChanged)
            if rowsChanged > 0 then
                TriggerClientEvent('QBCore:Notify', src, "Vehicle transferred to " .. newGarageId .. " garage for $" .. transferCost, "success")
                TriggerClientEvent('dw-garages:client:TransferComplete', src, newGarageId, plate)
                -- Also send VehicleTransferCompleted to ensure UI closes properly
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, true, plate)
            else
                Player.Functions.AddMoney("cash", transferCost, "vehicle-transfer-refund")
                TriggerClientEvent('QBCore:Notify', src, "Transfer failed", "error")
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
            end
        end)
    end)
end)

-- Improved version of CheckJobAccess that also returns the job name
QBCore.Functions.CreateCallback('dw-garages:server:CheckJobVehicleAccess', function(source, cb, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, nil) end
    
    local jobName = Player.PlayerData.job.name
    if not jobName then return cb(false, nil) end
    
    if trackedJobVehicles[plate] then
        local vehicleJob = trackedJobVehicles[plate].job
        return cb(vehicleJob == jobName, vehicleJob)
    end
    
    return cb(false, nil)
end)

RegisterNetEvent('dw-garages:server:TrackJobVehicle', function(plate, jobName, props, spotIndex)
    local src = source
    
    if not plate or not jobName then return end
    
    jobVehicles[plate] = {
        job = jobName,
        props = props,
        spotIndex = spotIndex,
        lastUpdated = os.time()
    }
end)

RegisterNetEvent('dw-garages:server:FreeJobParkingSpot', function(jobName, spotIndex)
    if not jobName or not spotIndex then return end
    
    TriggerClientEvent('dw-garages:client:FreeJobParkingSpot', -1, jobName, spotIndex)
end)
-- Check if player has job access to a vehicle
QBCore.Functions.CreateCallback('dw-garages:server:CheckJobAccess', function(source, cb, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    
    local playerJob = Player.PlayerData.job.name
    
    if jobVehicles[plate] and jobVehicles[plate].job == playerJob then
        return cb(true)
    end
    
    return cb(false)
end)


-- Get job vehicle data
QBCore.Functions.CreateCallback('dw-garages:server:GetJobVehicleData', function(source, cb, plate)
    if trackedJobVehicles[plate] then
        cb(trackedJobVehicles[plate])
    else
        cb(nil)
    end
end)



RegisterNetEvent('dw-garages:server:StoreVehicle', function(plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local citizenid = Player.PlayerData.citizenid
    
    -- First check if player has permission to store this vehicle
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(vehicleResult)
        if not vehicleResult or #vehicleResult == 0 then
            TriggerClientEvent('QBCore:Notify', src, "Vehicle not found", "error")
            return
        end
        
        local vehicle = vehicleResult[1]
        local hasPermission = false
        
        -- Check if player owns the vehicle
        if vehicle.citizenid == citizenid then
            hasPermission = true
        else
            -- Check if vehicle is in a shared garage the player has access to
            if vehicle.shared_garage_id then
                local sharedGarageId = vehicle.shared_garage_id
                -- Check if player is a member or owner of this shared garage
                MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
                    {sharedGarageId, citizenid}, function(memberResult)
                        if memberResult and #memberResult > 0 then
                            hasPermission = true
                        else
                            MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                                {sharedGarageId, citizenid}, function(ownerResult)
                                    if ownerResult and #ownerResult > 0 then
                                        hasPermission = true
                                    end
                                    
                                    if not hasPermission then
                                        TriggerClientEvent('QBCore:Notify', src, "You don't have permission to store this vehicle", "error")
                                        return
                                    end
                                    
                                    -- Proceed with storage
                                    storeVehicleInDatabase(src, plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
                                end
                            )
                            return
                        end
                        
                        if hasPermission then
                            -- Proceed with storage
                            storeVehicleInDatabase(src, plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
                        end
                    end
                )
                return
            end
        end
        
        if not hasPermission then
            TriggerClientEvent('QBCore:Notify', src, "You don't have permission to store this vehicle", "error")
            return
        end
        
        -- Proceed with storage
        storeVehicleInDatabase(src, plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
    end)
end)

function storeVehicleInDatabase(src, plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- For house garages, convert propertyId to garage name format
    if garageType == "house" then
        garageId = 'housegarage-' .. garageId
    end
    
    MySQL.Async.fetchAll('SHOW COLUMNS FROM player_vehicles LIKE "stored"', {}, function(storedColumn)
        local hasStoredColumn = #storedColumn > 0
        MySQL.Async.fetchAll('SHOW COLUMNS FROM player_vehicles LIKE "state"', {}, function(stateColumn)
            local hasStateColumn = #stateColumn > 0
            
            -- FIXED QUERY: Don't clear shared_garage_id automatically
            local query = 'UPDATE player_vehicles SET garage = ?, mods = ?, fuel = ?, engine = ?, body = ?'
            local params = {garageId, json.encode(props), fuel, engineHealth, bodyHealth}
            if hasStoredColumn then
                query = query .. ', stored = 1'
            end
            if hasStateColumn then
                query = query .. ', state = 1'
            end
            query = query .. ' WHERE plate = ?'
            table.insert(params, plate)
            
            MySQL.Async.execute(query, params, function(rowsChanged)
                if rowsChanged > 0 then
                    OutsideVehicles[plate] = nil
                    
                    if garageType == "gang" then
                        local gang = Player.PlayerData.gang.name
                        if gang and gang ~= "none" then
                            MySQL.Async.execute('UPDATE gang_vehicles SET stored = 1 WHERE plate = ? AND gang = ?', {plate, gang})
                        end
                    end
                    
                    -- Trigger refresh events
                    TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                else
                    TriggerClientEvent('QBCore:Notify', src, "Failed to store vehicle", "error")
                end
            end)
        end)
    end)
end


RegisterNetEvent('dw-garages:server:UpdateGangVehicleState', function(plate, state)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local gang = Player.PlayerData.gang.name
    if gang and gang ~= "none" then
        MySQL.Async.execute('UPDATE gang_vehicles SET stored = ? WHERE plate = ? AND gang = ?', {state, plate, gang})
    end
end)

RegisterNetEvent('dw-garages:server:UpdateVehicleName', function(plate, newName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if result[1] then
            MySQL.Async.execute('UPDATE player_vehicles SET custom_name = ? WHERE plate = ? AND citizenid = ?', {newName, plate, citizenid}, function(rowsChanged)
                if rowsChanged > 0 then
                    TriggerClientEvent('QBCore:Notify', src, 'Vehicle name updated', 'success')
                else
                    TriggerClientEvent('QBCore:Notify', src, 'Failed to update vehicle name', 'error')
                end
            end)
        else
            TriggerClientEvent('QBCore:Notify', src, 'You do not own this vehicle', 'error')
        end
    end)
end)

RegisterNetEvent('dw-garages:server:ToggleFavorite', function(plate, isFavorite)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    local favoriteValue = isFavorite and 1 or 0
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if result[1] then
            -- Update favorite status
            MySQL.Async.execute('UPDATE player_vehicles SET is_favorite = ? WHERE plate = ? AND citizenid = ?', {favoriteValue, plate, citizenid}, function(rowsChanged)
                if rowsChanged > 0 then
                    if isFavorite then
                        TriggerClientEvent('QBCore:Notify', src, 'Added to favorites', 'success')
                    else
                        TriggerClientEvent('QBCore:Notify', src, 'Removed from favorites', 'error')
                    end
                else
                    TriggerClientEvent('QBCore:Notify', src, 'Failed to update favorite status', 'error')
                end
            end)
        else
            TriggerClientEvent('QBCore:Notify', src, 'You do not own this vehicle', 'error')
        end
    end)
end)

RegisterNetEvent('qb-garage:server:ToggleFavorite', function(plate, isFavorite)
    TriggerEvent('dw-garages:server:ToggleFavorite', plate, isFavorite)
end)

RegisterNetEvent('dw-garages:server:StoreVehicleInGang', function(plate, gangName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Verify ownership first
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if result[1] then
            MySQL.Async.fetchAll('SELECT * FROM gang_vehicles WHERE plate = ? AND gang = ? AND owner = ?', {plate, gangName, citizenid}, function(gangResult)
                if gangResult[1] then
                    TriggerClientEvent('QBCore:Notify', src, 'Vehicle is already shared with your gang', 'error')
                else
                    MySQL.Async.execute('INSERT INTO gang_vehicles (plate, gang, owner, vehicle, stored) VALUES (?, ?, ?, ?, 1)', 
                        {plate, gangName, citizenid, result[1].vehicle}, 
                        function(rowsChanged)
                            if rowsChanged > 0 then
                                MySQL.Async.execute('UPDATE player_vehicles SET stored_in_gang = ? WHERE plate = ? AND citizenid = ?', 
                                    {gangName, plate, citizenid})
                                
                                TriggerClientEvent('QBCore:Notify', src, 'Vehicle shared with your gang', 'success')
                                TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                            else
                                TriggerClientEvent('QBCore:Notify', src, 'Failed to share vehicle with gang', 'error')
                            end
                        end
                    )
                end
            end)
        else
            TriggerClientEvent('QBCore:Notify', src, 'You do not own this vehicle', 'error')
        end
    end)
end)

RegisterNetEvent('qb-garage:server:StoreVehicleInGang', function(plate, gangName)
    TriggerEvent('dw-garages:server:StoreVehicleInGang', plate, gangName)
end)

RegisterNetEvent('qb-garage:server:UpdateVehicleState', function(plate, state)
    MySQL.Async.execute('UPDATE player_vehicles SET state = ?, stored = ? WHERE plate = ?', {state, state, plate})
end)

RegisterNetEvent('qb-garage:server:UpdateGangVehicleState', function(plate, state)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local gang = Player.PlayerData.gang.name
    if gang and gang ~= "none" then
        MySQL.Async.execute('UPDATE gang_vehicles SET stored = ? WHERE plate = ? AND gang = ?', {state, plate, gang})
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    MySQL.Async.fetchAll('SHOW COLUMNS FROM player_vehicles LIKE "impoundedtime"', {}, function(result)
        if result and #result == 0 then
            Wait(100)
        end
    end)
    
    -- Initialize the OutsideVehicles table when server starts
    MySQL.Async.fetchAll('SELECT plate FROM player_vehicles WHERE state = 0', {}, function(result)
        if result and #result > 0 then
            for _, v in ipairs(result) do
                OutsideVehicles[v.plate] = true
            end
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:IsVehicleOut', function(source, cb, plate)
    MySQL.Async.fetchAll('SELECT state FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result and #result > 0 then
            cb(result[1].state == 0)
        else
            cb(false)
        end
    end)
end)


QBCore.Functions.CreateCallback('dw-garages:server:CreateSharedGarage', function(source, cb, garageName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return cb(false, "Player not found") end
    
    local citizenid = Player.PlayerData.citizenid
    
    local code = tostring(math.random(1000, 9999))
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE owner_citizenid = ?', {citizenid}, function(result)
        if result and #result > 0 then
            cb(false, "You already own a shared garage")
            return
        end
        
        MySQL.Async.insert('INSERT INTO shared_garages (name, owner_citizenid, access_code) VALUES (?, ?, ?)', 
            {garageName, citizenid, code}, 
            function(garageId)
                if garageId > 0 then
                    MySQL.Async.insert('INSERT INTO shared_garage_members (garage_id, member_citizenid) VALUES (?, ?)', 
                        {garageId, citizenid})
                    
                    cb(true, {id = garageId, code = code, name = garageName})
                else
                    cb(false, "Failed to create shared garage")
                end
            end
        )
    end)
end)

RegisterNetEvent('dw-garages:server:RequestJoinSharedGarage', function(accessCode)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE access_code = ?', {accessCode}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "Invalid access code", "error")
            return
        end
        
        local garageData = result[1]
        
        MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
            {garageData.id, citizenid}, function(memberResult)
                if memberResult and #memberResult > 0 then
                    TriggerClientEvent('QBCore:Notify', src, "You are already a member of this garage", "error")
                    return
                end
                
                MySQL.Async.fetchAll('SELECT COUNT(*) as count FROM shared_garage_members WHERE garage_id = ?', 
                    {garageData.id}, function(countResult)
                        if countResult[1].count >= Config.MaxSharedGarageMembers then
                            TriggerClientEvent('QBCore:Notify', src, "This garage has reached its member limit", "error")
                            return
                        end
                        
                        local ownerPlayer = QBCore.Functions.GetPlayerByCitizenId(garageData.owner_citizenid)
                        if not ownerPlayer then
                            TriggerClientEvent('QBCore:Notify', src, "Garage owner is not online", "error")
                            return
                        end
                        
                        TriggerClientEvent('dw-garages:client:ReceiveJoinRequest', ownerPlayer.PlayerData.source, {
                            requesterId = citizenid,
                            requesterName = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
                            garageId = garageData.id,
                            garageName = garageData.name
                        })
                        
                        TriggerClientEvent('QBCore:Notify', src, "Join request sent to garage owner", "success")
                    end
                )
            end
        )
    end)
end)

RegisterNetEvent('dw-garages:server:ApproveJoinRequest', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local ownerCitizenid = Player.PlayerData.citizenid
    local requesterId = data.requesterId
    local garageId = data.garageId
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
        {garageId, ownerCitizenid}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "You don't own this garage", "error")
                return
            end
            
            MySQL.Async.insert('INSERT INTO shared_garage_members (garage_id, member_citizenid) VALUES (?, ?)', 
                {garageId, requesterId}, function(memberId)
                    if memberId > 0 then
                        local requesterPlayer = QBCore.Functions.GetPlayerByCitizenId(requesterId)
                        if requesterPlayer then
                            TriggerClientEvent('QBCore:Notify', requesterPlayer.PlayerData.source, 
                                "Your request to join " .. result[1].name .. " garage has been approved", "success")
                        end
                        
                        TriggerClientEvent('QBCore:Notify', src, "Approved garage membership request", "success")
                    else
                        TriggerClientEvent('QBCore:Notify', src, "Failed to add member", "error")
                    end
                end
            )
        end
    )
end)

RegisterNetEvent('dw-garages:server:DenyJoinRequest', function(data)
    local src = source
    local requesterId = data.requesterId
    
    local requesterPlayer = QBCore.Functions.GetPlayerByCitizenId(requesterId)
    if requesterPlayer then
        TriggerClientEvent('QBCore:Notify', requesterPlayer.PlayerData.source, 
            "Your request to join the shared garage has been denied", "error")
    end
    
    TriggerClientEvent('QBCore:Notify', src, "Denied garage membership request", "success")
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetSharedGarages', function(source, cb)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then 
        return cb({}) 
    end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll("SHOW TABLES LIKE 'shared_garages'", {}, function(tableExists)
        if not tableExists or #tableExists == 0 then
            CreateSharedGaragesTables(src, function()
                cb({})
            end)
            return
        end
        
        MySQL.Async.fetchAll('SELECT DISTINCT sg.* FROM shared_garages sg LEFT JOIN shared_garage_members sgm ON sg.id = sgm.garage_id WHERE sgm.member_citizenid = ? OR sg.owner_citizenid = ?', 
            {citizenid, citizenid}, function(result)
                if result and #result > 0 then
                    for i, garage in ipairs(result) do
                        result[i].isOwner = (garage.owner_citizenid == citizenid)
                    end
                    cb(result)
                else
                    cb({})
                end
            end
        )
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetSharedGarageVehicles', function(source, cb, garageId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    MySQL.Async.fetchAll('SELECT pv.*, p.charinfo FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE pv.shared_garage_id = ? AND pv.state = 1', 
        {garageId}, function(vehicles)
            if vehicles and #vehicles > 0 then
                for i, vehicle in ipairs(vehicles) do
                    if vehicle.charinfo then
                        local charinfo = json.decode(vehicle.charinfo)
                        if charinfo then
                            vehicles[i].owner_name = charinfo.firstname .. ' ' .. charinfo.lastname
                        else
                            vehicles[i].owner_name = "Unknown"
                        end
                    else
                        vehicles[i].owner_name = "Unknown"
                    end
                end
                cb(vehicles)
            else
                cb({})
            end
        end
    )
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetHouseGarageVehicles', function(source, cb, propertyId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Check if player has access to this property
    local function checkAccessAndGetVehicles()
        local hasAccess = false
        
        -- Try to use ps-housing export first
        if GetResourceState('ps-housing') == 'started' then
            local success, result = pcall(function()
                return exports['ps-housing']:IsOwner(source, propertyId)
            end)
            if success and result then
                hasAccess = true
            end
        end
        
        -- If export didn't work or returned false, check database
        if not hasAccess then
            MySQL.Async.fetchAll('SELECT owner, has_access FROM properties WHERE property_id = ?', 
                {propertyId}, function(property)
                    if property and property[1] then
                        if property[1].owner == citizenid then
                            hasAccess = true
                        else
                            local hasAccessList = json.decode(property[1].has_access or '[]')
                            if hasAccessList and type(hasAccessList) == 'table' then
                                for _, accessCitizenid in ipairs(hasAccessList) do
                                    if accessCitizenid == citizenid then
                                        hasAccess = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    if hasAccess then
                        -- Get vehicles stored in this house garage
                        local garageName = 'housegarage-' .. propertyId
                        MySQL.Async.fetchAll('SELECT *, COALESCE(is_favorite, 0) as is_favorite FROM player_vehicles WHERE garage = ? AND state = 1', 
                            {garageName}, function(vehicles)
                                cb(vehicles or {})
                            end)
                    else
                        cb({})
                    end
                end)
        else
            -- Has access via export, get vehicles
            local garageName = 'housegarage-' .. propertyId
            MySQL.Async.fetchAll('SELECT *, COALESCE(is_favorite, 0) as is_favorite FROM player_vehicles WHERE garage = ? AND state = 1', 
                {garageName}, function(vehicles)
                    cb(vehicles or {})
                end)
        end
    end
    
    checkAccessAndGetVehicles()
end)

function getSharedGarageVehicles(garageId, citizenid, cb)
    MySQL.Async.fetchAll('SELECT pv.*, p.charinfo FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE pv.shared_garage_id = ?', 
        {garageId}, function(vehicles)
            if vehicles and #vehicles > 0 then
                for i, vehicle in ipairs(vehicles) do
                    local charinfo = json.decode(vehicle.charinfo)
                    if charinfo then
                        vehicles[i].owner_name = charinfo.firstname .. ' ' .. charinfo.lastname
                    else
                        vehicles[i].owner_name = "Unknown"
                    end
                end
                cb(vehicles)
            else
                cb({})
            end
        end
    ) 
end


RegisterNetEvent('dw-garages:server:StoreVehicleInSharedGarage', function(plate, garageId, props, fuel, engineHealth, bodyHealth)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
        {garageId, citizenid}, function(memberResult)
            if not memberResult or #memberResult == 0 then
                MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                    {garageId, citizenid}, function(ownerResult)
                        if not ownerResult or #ownerResult == 0 then
                            TriggerClientEvent('QBCore:Notify', src, "You don't have access to this shared garage", "error")
                            return
                        end
                        
                        storeVehicleInSharedGarage(src, plate, garageId, props, fuel, engineHealth, bodyHealth)
                    end
                )
            else
                storeVehicleInSharedGarage(src, plate, garageId, props, fuel, engineHealth, bodyHealth)
            end
        end
    )
end)

function storeVehicleInSharedGarage(src, plate, garageId, props, fuel, engineHealth, bodyHealth)
    local Player = QBCore.Functions.GetPlayer(src)
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "You don't own this vehicle", "error")
            return
        end
        
        MySQL.Async.fetchAll('SELECT COUNT(*) as count FROM player_vehicles WHERE shared_garage_id = ?', 
            {garageId}, function(countResult)
                if countResult[1].count >= Config.MaxSharedVehicles then
                    TriggerClientEvent('QBCore:Notify', src, "Shared garage is full", "error")
                    return
                end
                
                MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = ?, mods = ?, fuel = ?, engine = ?, body = ?, state = 1, stored = 1 WHERE plate = ?', 
                    {garageId, json.encode(props), fuel, engineHealth, bodyHealth, plate}, function(rowsChanged)
                        if rowsChanged > 0 then
                            TriggerClientEvent('QBCore:Notify', src, "Vehicle stored in shared garage", "success")
                            
                            TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                        else
                            TriggerClientEvent('QBCore:Notify', src, "Failed to store vehicle", "error")
                        end
                    end
                )
            end
        )
    end)
end

RegisterNetEvent('dw-garages:server:UpdateVehicleState', function(plate, state)
    if not plate then return end
    plate = plate:gsub("%s+", "")
    
    -- Throttle updates: only update if enough time has passed
    local currentTime = os.time()
    local lastUpdate = vehicleUpdateCooldown[plate] or 0
    
    if (currentTime - lastUpdate) < UPDATE_COOLDOWN then
        -- Too soon, skip this update
        return
    end
    
    vehicleUpdateCooldown[plate] = currentTime
    
    -- Optimized query: use plate only (primary key) instead of plate + state
    local query = 'UPDATE player_vehicles SET state = ?, last_update = ? WHERE plate = ?'
    local params = {state, currentTime, plate}
    
    MySQL.Async.execute(query, params, function(rowsChanged)
        if rowsChanged > 0 then
            -- Update OutsideVehicles tracking table
            if state == 0 then
                OutsideVehicles[plate] = true
            else
                OutsideVehicles[plate] = nil
            end
        end
    end)
end)

-- Process vehicle update queue to serialize updates and prevent deadlocks
function ProcessVehicleUpdateQueue(plate)
    -- Check if already processing this plate
    if vehicleUpdateProcessing[plate] then
        return -- Already processing, skip
    end
    
    if not vehicleUpdateQueue[plate] or #vehicleUpdateQueue[plate] == 0 then
        vehicleUpdateQueue[plate] = nil
        vehicleUpdateProcessing[plate] = nil
        return
    end
    
    -- Mark as processing
    vehicleUpdateProcessing[plate] = true
    
    -- Get the latest update from queue (discard older ones)
    local latestUpdate = vehicleUpdateQueue[plate][#vehicleUpdateQueue[plate]]
    vehicleUpdateQueue[plate] = {} -- Clear queue but keep structure until update completes
    
    local vehicleData = latestUpdate.vehicleData
    local currentTime = latestUpdate.currentTime
    
    -- Fetch current mods, then update (serialized to prevent deadlocks)
    MySQL.Async.fetchAll('SELECT mods, state FROM player_vehicles WHERE plate = ? LIMIT 1', {plate}, function(result)
        if result and #result > 0 and result[1].state == 0 then
            local mods = {}
            
            -- Decode existing mods
            if result[1].mods then
                mods = json.decode(result[1].mods) or {}
            end
            
            -- Update lastPosition
            mods.lastPosition = vehicleData
            local modsJson = json.encode(mods)
            
            -- Single UPDATE query (serialized per plate to prevent deadlocks)
            -- Add a small delay before executing to reduce concurrent lock contention
            Wait(200)
            
            MySQL.Async.execute('UPDATE player_vehicles SET mods = ?, last_update = ? WHERE plate = ? AND state = 0',
                {modsJson, currentTime, plate},
                function(rowsChanged)
                    -- Update completed successfully
                    vehicleUpdateProcessing[plate] = nil
                    
                    if rowsChanged > 0 then
                        OutsideVehicles[plate] = true
                    end
                    
                    -- Process next item in queue if any (with delay to prevent rapid-fire updates)
                    if vehicleUpdateQueue[plate] and #vehicleUpdateQueue[plate] > 0 then
                        Wait(1000) -- Increased delay between updates to reduce lock contention
                        ProcessVehicleUpdateQueue(plate)
                    else
                        vehicleUpdateQueue[plate] = nil
                    end
                end
            )
        else
            -- Vehicle not found or not out, clear queue
            vehicleUpdateProcessing[plate] = nil
            vehicleUpdateQueue[plate] = nil
        end
    end)
    
    -- Add timeout protection: if processing takes too long, clear the lock
    Citizen.SetTimeout(30000, function() -- 30 second timeout
        if vehicleUpdateProcessing[plate] then
            print(string.format("[dw-garages] Timeout clearing processing lock for vehicle %s", plate))
            vehicleUpdateProcessing[plate] = nil
            if vehicleUpdateQueue[plate] and #vehicleUpdateQueue[plate] == 0 then
                vehicleUpdateQueue[plate] = nil
            end
        end
    end)
end

RegisterNetEvent('dw-garages:server:SaveVehiclePosition', function(plate, vehicleData, updateMods)
    if not plate or not vehicleData then return end
    
    plate = plate:gsub("%s+", "")
    updateMods = updateMods ~= false -- Default to true if not specified
    
    -- Throttle updates: only update if enough time has passed
    local currentTime = os.time()
    local lastUpdate = vehicleUpdateCooldown[plate] or 0
    
    if (currentTime - lastUpdate) < UPDATE_COOLDOWN then
        -- Too soon, skip this update
        return
    end
    
    vehicleUpdateCooldown[plate] = currentTime
    
    -- If only updating last_update (position hasn't changed), do a lightweight update
    if not updateMods then
        -- Optimized: use plate only (primary key) - faster and less lock contention
        MySQL.Async.execute('UPDATE player_vehicles SET last_update = ? WHERE plate = ? AND state = 0', 
            {currentTime, plate}, 
            function(rowsChanged)
                if rowsChanged > 0 then
                    OutsideVehicles[plate] = true
                end
            end
        )
        return
    end
    
    -- Save vehicle position to database
    -- Use a queue system to serialize updates per plate and prevent deadlocks
    if not vehicleUpdateQueue[plate] then
        vehicleUpdateQueue[plate] = {}
    end
            
    -- Add update to queue
    table.insert(vehicleUpdateQueue[plate], {
        vehicleData = vehicleData,
        currentTime = currentTime
    })
    
    -- Process queue if not already processing
    if not vehicleUpdateProcessing[plate] then
        ProcessVehicleUpdateQueue(plate)
    end
end)

RegisterNetEvent('dw-garages:server:RespawnPlayerVehicles', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Get all vehicles that should be out (state = 0) for this player
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND state = 0', {citizenid}, function(result)
        if result and #result > 0 then
            for _, vehicle in ipairs(result) do
                -- Check if vehicle has a saved position
                local mods = {}
                if vehicle.mods then
                    mods = json.decode(vehicle.mods) or {}
                end
                
                if mods.lastPosition then
                    -- Ask client to verify if vehicle exists, then respawn if needed
                    TriggerClientEvent('dw-garages:client:CheckAndRespawnVehicle', src, vehicle, mods.lastPosition)
                    Wait(500) -- Small delay between respawns
                end
            end
        end
    end)
end)

RegisterNetEvent('dw-garages:server:RemoveVehicleFromSharedGarage', function(plate)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid    
    -- qb-menu can pass event args as a table: { plate = "ABC123" }
    if type(plate) == "table" then
        plate = plate.plate
    end
    if not plate then
        TriggerClientEvent('QBCore:Notify', src, "Invalid plate", "error")
        TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, nil)
        return
    end
    plate = tostring(plate):gsub("%s+", "")

    -- Allow removal if:
    -- - player owns the vehicle OR
    -- - player owns the shared garage the vehicle is currently stored in
    MySQL.Async.fetchAll('SELECT plate, citizenid, shared_garage_id FROM player_vehicles WHERE plate = ? LIMIT 1',
        {plate}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "Vehicle not found", "error")
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                return
            end
            
            local vehicle = result[1]
            local sharedGarageId = vehicle.shared_garage_id
            local isVehicleOwner = vehicle.citizenid == citizenid

            if not sharedGarageId then
                TriggerClientEvent('QBCore:Notify', src, "Vehicle is not in a shared garage", "error")
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                return
            end

            if isVehicleOwner then
            MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = NULL WHERE plate = ?', 
                {plate}, function(rowsChanged)
                    if rowsChanged > 0 then
                        TriggerClientEvent('QBCore:Notify', src, "Vehicle removed from shared garage", "success")
                        TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, true, plate)
                            TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                        else
                            TriggerClientEvent('QBCore:Notify', src, "Failed to remove vehicle", "error")
                            TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                        end
                    end
                )
                return
            end

            -- Not vehicle owner: check if player owns the shared garage
            MySQL.Async.fetchAll('SELECT id FROM shared_garages WHERE id = ? AND owner_citizenid = ? LIMIT 1',
                {sharedGarageId, citizenid}, function(ownerResult)
                    if not ownerResult or #ownerResult == 0 then
                        TriggerClientEvent('QBCore:Notify', src, "You don't have permission to remove this vehicle", "error")
                        TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                        return
                    end

                    MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = NULL WHERE plate = ?',
                        {plate}, function(rowsChanged)
                            if rowsChanged > 0 then
                                TriggerClientEvent('QBCore:Notify', src, "Vehicle removed from shared garage", "success")
                                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, true, plate)
                        TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                    else
                        TriggerClientEvent('QBCore:Notify', src, "Failed to remove vehicle", "error")
                        TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                    end
                        end
                    )
                end
            )
        end
    )
end)

RegisterNetEvent('dw-garages:server:TakeOutSharedVehicle', function(plate, garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
        {garageId, citizenid}, function(memberResult)
            if not memberResult or #memberResult == 0 then
                MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                    {garageId, citizenid}, function(ownerResult)
                        if not ownerResult or #ownerResult == 0 then
                            TriggerClientEvent('QBCore:Notify', src, "You don't have access to this shared garage", "error")
                            return
                        end
                        
                        takeOutSharedVehicle(src, plate, garageId)
                    end
                )
            else
                takeOutSharedVehicle(src, plate, garageId)
            end
        end
    )
end)

-- Modify in server.lua
function CheckForLostVehicles()
    local currentTime = os.time()
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE state = 0', {}, function(vehicles)
        if not vehicles or #vehicles == 0 then return end
        
        for _, vehicle in ipairs(vehicles) do
            local lastUpdate = vehicle.last_update or 0
            
            -- If vehicle has been out for more than the configured timeout (3 hours)
            if (currentTime - lastUpdate) > Config.LostVehicleTimeout then
                local timeSinceLastUpdate = currentTime - lastUpdate
                local hoursOut = math.floor(timeSinceLastUpdate / 3600)
                
                MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
                    {
                        currentTime, 
                        "Vehicle abandoned or lost (auto-impounded after 3 hours)", 
                        "Automated System", 
                        "police", 
                        Config.ImpoundFee, 
                        vehicle.plate
                    },
                    function(rowsChanged)
                        if rowsChanged > 0 then
                            print(string.format("[dw-garages] Auto-impounded vehicle %s after %d hours (last_update: %d, current: %d)", 
                                vehicle.plate, hoursOut, lastUpdate, currentTime))
                        end
                    end
                )
                if OutsideVehicles[vehicle.plate] then
                    OutsideVehicles[vehicle.plate] = nil
                end
            end
        end
    end)
end

RegisterNetEvent('vehiclemod:server:syncDeletion', function(netId, plate)
    if plate then
        -- Clean the plate (remove spaces)
        plate = plate:gsub("%s+", "")
        
        -- Check if this is a player-owned vehicle
        MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
            if result and #result > 0 then
                local currentTime = os.time()
                
                -- Update vehicle to impound state
                MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
                    {
                        currentTime, 
                        "Vehicle was towed", 
                        "City Towing", 
                        "police", 
                        Config.ImpoundFee, 
                        plate
                    }
                )
                if OutsideVehicles[plate] then
                    OutsideVehicles[plate] = nil
                end
            end
        end)
    end
end)


CreateThread(function()
    Wait(60000) -- Wait 1 minute after resource start
    
    while true do
        CheckForLostVehicles()
        Wait(300000) -- Check every 5 minutes
    end
end)

function takeOutSharedVehicle(src, plate, garageId)
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND shared_garage_id = ? AND state = 1', 
        {plate, garageId}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "Vehicle not found or already taken out", "error")
                return
            end
            
            -- Just update state without removing shared_garage_id association
            MySQL.Async.execute('UPDATE player_vehicles SET state = 0, stored = 0 WHERE plate = ?', 
                {plate}, function(rowsChanged)
                    if rowsChanged > 0 then
                        TriggerClientEvent('QBCore:Notify', src, "Vehicle taken out from shared garage", "success")
                        TriggerClientEvent('dw-garages:client:TakeOutSharedVehicle', src, plate, result[1])
                    else
                        TriggerClientEvent('QBCore:Notify', src, "Failed to take out vehicle", "error")
                    end
                end
            )
        end
    )
end


QBCore.Functions.CreateCallback('dw-garages:server:CheckVehicleStatus', function(source, cb, plate)
    MySQL.Async.fetchAll('SELECT state FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result and #result > 0 then
            -- Return true if state is 1 (in garage), false otherwise
            cb(result[1].state == 1)
        else
            cb(false)
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetSharedGarageMembers', function(source, cb, garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
        {garageId, citizenid}, function(result)
            if not result or #result == 0 then
                cb({})
                return
            end
            
            -- Get members
            MySQL.Async.fetchAll('SELECT sgm.*, p.charinfo FROM shared_garage_members sgm LEFT JOIN players p ON sgm.member_citizenid = p.citizenid WHERE sgm.garage_id = ?', 
                {garageId}, function(members)
                    if members and #members > 0 then
                        local formattedMembers = {}
                        for i, member in ipairs(members) do
                            local charinfo = json.decode(member.charinfo)
                            local memberData = {
                                id = member.id,
                                citizenid = member.member_citizenid,
                                name = "Unknown"
                            }
                            
                            if charinfo then
                                memberData.name = charinfo.firstname .. ' ' .. charinfo.lastname
                            end
                            
                            if member.member_citizenid ~= citizenid then
                                table.insert(formattedMembers, memberData)
                            end
                        end
                        cb(formattedMembers)
                    else
                        cb({})
                    end
                end
            )
        end
    )
end)

RegisterNetEvent('dw-garages:server:HandleDeletedVehicle', function(plate)
    if not plate then return end
    
    plate = plate:gsub("%s+", "")
    
    -- Only mark as impounded if vehicle is actually deleted, not just on disconnect
    -- This allows vehicles to persist when players disconnect
    -- Optimized: throttle check before query to avoid unnecessary database calls
    local currentTime = os.time()
    local lastUpdate = vehicleUpdateCooldown[plate] or 0
    if (currentTime - lastUpdate) < UPDATE_COOLDOWN then
        return -- Too soon, skip update
    end
    
    -- Optimized: only select state column to check, not all columns
    MySQL.Async.fetchAll('SELECT state FROM player_vehicles WHERE plate = ? LIMIT 1', {plate}, function(result)
        if result and #result > 0 and result[1].state == 0 then
            vehicleUpdateCooldown[plate] = currentTime
            -- Optimized: use plate only (primary key) for faster update
            MySQL.Async.execute('UPDATE player_vehicles SET last_update = ? WHERE plate = ?', 
                {currentTime, plate}, 
                function(rowsChanged)
                        -- Vehicle stays in world, just update timestamp
                end
            )
        end
    end)
end)

RegisterNetEvent('QBCore:Server:DeleteVehicle', function(netId)
    -- This event is triggered from the client when a vehicle is deleted
    -- Don't move player vehicles to impound on deletion - let them persist
    -- Only update timestamp for LostVehicleTimeout
    if netId then
        local vehicle = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(vehicle) then
            local plate = QBCore.Functions.GetPlate(vehicle)
            if plate then
                plate = plate:gsub("%s+", "") -- Remove spaces
                
                -- For player vehicles, just update last_update, don't move to impound
                -- This allows vehicles to persist when players disconnect
                -- Optimized: throttle updates to prevent spam
                local currentTime = os.time()
                local lastUpdate = vehicleUpdateCooldown[plate] or 0
                if (currentTime - lastUpdate) >= UPDATE_COOLDOWN then
                    vehicleUpdateCooldown[plate] = currentTime
                MySQL.Async.execute('UPDATE player_vehicles SET last_update = ? WHERE plate = ? AND state = 0', 
                        {currentTime, plate}, 
                    function(rowsChanged)
                            -- Vehicle stays in world, LostVehicleTimeout will handle cleanup
                    end
                )
                end
            end
        end
    end
end)

RegisterNetEvent('QBCore:Server:OnVehicleDelete', function(plate)
    if not plate then return end
    
    -- Clean the plate (remove spaces)
    plate = plate:gsub("%s+", "")
    
    -- Check if this is a player-owned vehicle
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result and #result > 0 then
            local currentTime = os.time()
            
            -- Update vehicle to impound state
            MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
                {
                    currentTime, 
                    "Vehicle was towed", 
                    "City Towing", 
                    "police", 
                    Config.ImpoundFee, 
                    plate
                }
            )
            if OutsideVehicles[plate] then
                OutsideVehicles[plate] = nil
            end
        end
    end)
end)



RegisterNetEvent('qb-garage:server:UpdateOutsideVehicles', function(plate, state)
    if plate and state == 2 then
        -- Vehicle was deleted/impounded by some external script
        MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
            if result and #result > 0 then
                local currentTime = os.time()
                
                -- Update vehicle to impound state
                MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
                    {
                        currentTime, 
                        "Vehicle was towed", 
                        "City Towing", 
                        "police", 
                        Config.ImpoundFee, 
                        plate
                    }
                )
                if OutsideVehicles[plate] then
                    OutsideVehicles[plate] = nil
                end
            end
        end)
    end
end)

RegisterNetEvent('dw-garages:server:RemoveMemberFromSharedGarage', function(memberId, garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
        {garageId, citizenid}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "You don't own this garage", "error")
                return
            end
            
            MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE id = ? AND garage_id = ?', 
                {memberId, garageId}, function(memberResult)
                    if not memberResult or #memberResult == 0 then
                        TriggerClientEvent('QBCore:Notify', src, "Member not found", "error")
                        return
                    end
                    
                    MySQL.Async.execute('DELETE FROM shared_garage_members WHERE id = ?', 
                        {memberId}, function(rowsChanged)
                            if rowsChanged > 0 then
                                TriggerClientEvent('QBCore:Notify', src, "Member removed from shared garage", "success")
                                
                                local memberCitizenid = memberResult[1].member_citizenid
                                local memberPlayer = QBCore.Functions.GetPlayerByCitizenId(memberCitizenid)
                                if memberPlayer then
                                    TriggerClientEvent('QBCore:Notify', memberPlayer.PlayerData.source, 
                                        "You have been removed from " .. result[1].name .. " shared garage", "error")
                                end
                            else
                                TriggerClientEvent('QBCore:Notify', src, "Failed to remove member", "error")
                            end
                        end
                    )
                end
            )
        end
    )
end)

RegisterNetEvent('dw-garages:server:DeleteSharedGarage', function(garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid
    MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
        {garageId, citizenid}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "You don't own this garage", "error")
                return
            end
            
            MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = NULL WHERE shared_garage_id = ?', 
                {garageId}, function()
                    MySQL.Async.execute('DELETE FROM shared_garage_members WHERE garage_id = ?', {garageId})
                    
                    MySQL.Async.execute('DELETE FROM shared_garages WHERE id = ?', {garageId}, function(rowsChanged)
                        if rowsChanged > 0 then
                            TriggerClientEvent('QBCore:Notify', src, "Shared garage deleted", "success")
                        else
                            TriggerClientEvent('QBCore:Notify', src, "Failed to delete shared garage", "error")
                        end
                    end)
                end
            )
        end
    )
end)

QBCore.Functions.CreateCallback('dw-garages:server:StoreInSelectedSharedGarage', function(source, cb, plate, garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return cb({status = "error", message = "Player not found"}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', {plate, citizenid}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "You don't own this vehicle", "error")
            return cb({status = "error", message = "Vehicle ownership verification failed"})
        end
        
        if result[1].state ~= 1 then
            TriggerClientEvent('QBCore:Notify', src, "Vehicle must be stored to share it", "error")
            return cb({status = "error", message = "Vehicle must be stored"})
        end
        
        MySQL.Async.fetchAll('SELECT COUNT(*) as count FROM player_vehicles WHERE shared_garage_id = ?', {garageId}, function(countResult)
            if countResult[1].count >= Config.MaxSharedVehicles then
                TriggerClientEvent('QBCore:Notify', src, "Shared garage is full", "error")
                return cb({status = "error", message = "Shared garage is full"})
            end
            
            MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = ? WHERE plate = ?', {garageId, plate}, function(rowsChanged)
                if rowsChanged > 0 then
                    TriggerClientEvent('QBCore:Notify', src, "Vehicle stored in shared garage", "success")
                    TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                    return cb({status = "success"})
                else
                    TriggerClientEvent('QBCore:Notify', src, "Failed to store vehicle in shared garage", "error")
                    return cb({status = "error", message = "Database update failed"})
                end
            end)
        end)
    end)
end)

RegisterNetEvent('dw-garages:server:TransferVehicleToSharedGarage', function(plate, garageId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local citizenid = Player.PlayerData.citizenid    
    MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
        {garageId, citizenid}, function(memberResult)
            local hasAccess = false
            
            if memberResult and #memberResult > 0 then
                hasAccess = true
            else
                MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                    {garageId, citizenid}, function(ownerResult)
                        if ownerResult and #ownerResult > 0 then
                            hasAccess = true
                        end
                        
                        if hasAccess then
                            TransferVehicleToSharedGarage(src, plate, garageId, citizenid)
                        else
                            TriggerClientEvent('QBCore:Notify', src, "You don't have access to this shared garage", "error")
                            TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                        end
                    end
                )
                return 
            end
            
            if hasAccess then
                TransferVehicleToSharedGarage(src, plate, garageId, citizenid)
            end
        end
    )
end)

function TransferVehicleToSharedGarage(src, plate, garageId, citizenid)
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND citizenid = ?', 
        {plate, citizenid}, function(result)
            if not result or #result == 0 then
                TriggerClientEvent('QBCore:Notify', src, "You don't own this vehicle", "error")
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                return
            end
            
            if result[1].state ~= 1 then
                TriggerClientEvent('QBCore:Notify', src, "Vehicle must be stored in a garage to transfer it", "error")
                -- Notify client that transfer failed
                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                return
            end
            
            MySQL.Async.fetchAll('SELECT COUNT(*) as count FROM player_vehicles WHERE shared_garage_id = ?', 
                {garageId}, function(countResult)
                    if countResult[1].count >= Config.MaxSharedVehicles then
                        TriggerClientEvent('QBCore:Notify', src, "Shared garage is full", "error")
                        TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                        return
                    end
                    
                    MySQL.Async.execute('UPDATE player_vehicles SET shared_garage_id = ? WHERE plate = ?', 
                        {garageId, plate}, function(rowsChanged)
                            if rowsChanged > 0 then
                                TriggerClientEvent('QBCore:Notify', src, "Vehicle transferred to shared garage", "success")
                                
                                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, true, plate)
                                
                                TriggerClientEvent('dw-garages:client:RefreshVehicleList', src)
                            else
                                TriggerClientEvent('QBCore:Notify', src, "Failed to transfer vehicle", "error")
                                TriggerClientEvent('dw-garages:client:VehicleTransferCompleted', src, false, plate)
                            end
                        end
                    )
                end
            )
        end
    )
end

QBCore.Functions.CreateCallback('dw-garages:server:CheckIfVehicleOwned', function(source, cb, plate)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    
    local citizenid = Player.PlayerData.citizenid
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
        if result and #result > 0 then
            local vehicle = result[1]
            
            -- Check if player owns the vehicle directly
            if vehicle.citizenid == citizenid then
                cb(true)
                return
            end
            
            -- Check if vehicle is in a shared garage the player has access to
            if vehicle.shared_garage_id then
                local sharedGarageId = vehicle.shared_garage_id
                
                -- Check if player is a member of this shared garage
                MySQL.Async.fetchAll('SELECT * FROM shared_garage_members WHERE garage_id = ? AND member_citizenid = ?', 
                    {sharedGarageId, citizenid}, function(memberResult)
                        if memberResult and #memberResult > 0 then
                            cb(true)
                        else
                            -- Check if player is the owner of the shared garage
                            MySQL.Async.fetchAll('SELECT * FROM shared_garages WHERE id = ? AND owner_citizenid = ?', 
                                {sharedGarageId, citizenid}, function(ownerResult)
                                    if ownerResult and #ownerResult > 0 then
                                        cb(true)
                                    else
                                        -- Check gang vehicles as fallback
                                        if Player.PlayerData.gang and Player.PlayerData.gang.name ~= "none" then
                                            MySQL.Async.fetchAll('SELECT * FROM gang_vehicles WHERE plate = ? AND gang = ?', {plate, Player.PlayerData.gang.name}, function(gangResult)
                                                cb(gangResult and #gangResult > 0)
                                            end)
                                        else
                                            cb(false)
                                        end
                                    end
                                end
                            )
                        end
                    end
                )
            else
                -- Check gang vehicles if not in shared garage
                if Player.PlayerData.gang and Player.PlayerData.gang.name ~= "none" then
                    MySQL.Async.fetchAll('SELECT * FROM gang_vehicles WHERE plate = ? AND gang = ?', {plate, Player.PlayerData.gang.name}, function(gangResult)
                        cb(gangResult and #gangResult > 0)
                    end)
                else
                    cb(false)
                end
            end
        else
            cb(false)
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetVehicleInfo', function(source, cb, plate)
    if not plate then return cb(nil) end
    
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end
    
    MySQL.Async.fetchAll('SELECT pv.*, p.charinfo FROM player_vehicles pv LEFT JOIN players p ON pv.citizenid = p.citizenid WHERE pv.plate = ?', {plate}, function(result)
        if result and #result > 0 then
            local vehicleInfo = result[1]
            local ownerName = "Unknown"
            
            if vehicleInfo.charinfo then
                local charinfo = json.decode(vehicleInfo.charinfo)
                if charinfo then
                    ownerName = charinfo.firstname .. ' ' .. charinfo.lastname
                end
            end
            
            if vehicleInfo.citizenid == Player.PlayerData.citizenid then
                ownerName = "You"
            end
            
            local formattedInfo = {
                name = vehicleInfo.custom_name or nil,
                ownerName = ownerName,
                garage = vehicleInfo.garage or "Unknown",
                state = vehicleInfo.state or 1,
                storedInGang = vehicleInfo.stored_in_gang ~= nil,
                storedInShared = vehicleInfo.shared_garage_id ~= nil,
                isOwner = vehicleInfo.citizenid == Player.PlayerData.citizenid
            }
            
            cb(formattedInfo)
        else
            cb(nil)
        end
    end)
end)

RegisterNetEvent('dw-garages:server:CreateSharedGaragesTables')
AddEventHandler('dw-garages:server:CreateSharedGaragesTables', function()
    local src = source
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS shared_garages (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            owner_citizenid VARCHAR(50) NOT NULL,
            access_code VARCHAR(10) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {}, function()
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS shared_garage_members (
                id INT AUTO_INCREMENT PRIMARY KEY,
                garage_id INT NOT NULL,
                member_citizenid VARCHAR(50) NOT NULL,
                joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (garage_id) REFERENCES shared_garages(id) ON DELETE CASCADE
            )
        ]], {}, function()
            MySQL.Async.execute([[
                ALTER TABLE player_vehicles ADD COLUMN IF NOT EXISTS shared_garage_id INT NULL;
                ALTER TABLE player_vehicles ADD COLUMN IF NOT EXISTS is_favorite INT DEFAULT 0;
            ]], {}, function()
                TriggerClientEvent('QBCore:Notify', src, "Shared garages feature initialized", "success")
            end)
        end)
    end)
end)

function CreateSharedGaragesTables(src, callback)    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS shared_garages (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            owner_citizenid VARCHAR(50) NOT NULL,
            access_code VARCHAR(10) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ]], {}, function()
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS shared_garage_members (
                id INT AUTO_INCREMENT PRIMARY KEY,
                garage_id INT NOT NULL,
                member_citizenid VARCHAR(50) NOT NULL,
                joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (garage_id) REFERENCES shared_garages(id) ON DELETE CASCADE
            )
        ]], {}, function()
            MySQL.Async.execute([[
                ALTER TABLE player_vehicles ADD COLUMN IF NOT EXISTS shared_garage_id INT NULL
            ]], {}, function()
                QBCore.Functions.Notify(src, "Shared garages feature initialized", "success")
                callback()
            end)
        end)
    end)
end

QBCore.Functions.CreateCallback('dw-garages:server:CheckSharedGaragesTables', function(source, cb)
    MySQL.Async.fetchAll("SHOW TABLES LIKE 'shared_garages'", {}, function(result)
        cb(result and #result > 0)
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:CanPayImpoundFee', function(source, cb, fee)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false) end
    
    if Player.PlayerData.money["cash"] >= fee then
        cb(true)
    elseif Player.PlayerData.money["bank"] >= fee then
        cb(true)
    else
        cb(false)
    end
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetVehicleByPlate', function(source, cb, plate)
    if not plate then
        cb(nil, false) -- No plate provided
        return
    end
    
    -- Clean the plate (remove spaces and ensure proper format)
    plate = plate:gsub("%s+", "")
    
    -- First check for impounded vehicles (state = 2) - these should always be returned
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND state = 2', {plate}, function(impoundResult)
        if impoundResult and #impoundResult > 0 then
            -- Found impounded vehicle - return it
            cb(impoundResult[1], false)
            return
        end
        
        -- Not impounded, check if it's already outside
        if OutsideVehicles[plate] then
            cb(nil, true) -- Vehicle is already outside
            return
        end
        
        -- Check for vehicles in garage or out
        MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plate}, function(result)
            if result and #result > 0 then
                local vehicle = result[1]
                if vehicle.state == 0 then
                    cb(nil, true) -- Vehicle is already out according to DB
                else
                    cb(vehicle, false) -- Vehicle is available (in garage)
                end
            else
                -- Try with spaces in plate (some databases might store with spaces)
                local plateWithSpaces = plate:gsub("(.%d%d%d%d)", "%1 ")
                if plateWithSpaces ~= plate then
                    -- Try impounded first with spaces
                    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND state = 2', {plateWithSpaces}, function(impoundResult2)
                        if impoundResult2 and #impoundResult2 > 0 then
                            cb(impoundResult2[1], false)
                            return
                        end
                        
                        -- Try all states with spaces
                        MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ?', {plateWithSpaces}, function(result2)
                            if result2 and #result2 > 0 then
                                local vehicle = result2[1]
                                if vehicle.state == 0 then
                                    cb(nil, true)
                                elseif vehicle.state == 2 then
                                    cb(vehicle, false)
                                else
                                    cb(vehicle, false)
                                end
                            else
                                cb(nil, false) -- Vehicle not found
                            end
                        end)
                    end)
                else
                    cb(nil, false) -- Vehicle not found
                end
            end
        end)
    end)
end)
-- Pay impound fee and release vehicle
RegisterNetEvent('dw-garages:server:PayImpoundFee', function(plate, fee)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND state = 2', {plate}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "Vehicle not found or already released", "error")
            return
        end
        local vehicle = result[1]
        local actualFee = Config.ImpoundFee  -- Default fee
        if vehicle.impoundfee ~= nil then
            local customFee = tonumber(vehicle.impoundfee)
            if customFee and customFee > 0 then
                actualFee = customFee
            end
        end
        
        
        if Player.PlayerData.money["cash"] >= actualFee then
            Player.Functions.RemoveMoney("cash", actualFee, "impound-fee")
        else
            Player.Functions.RemoveMoney("bank", actualFee, "impound-fee")
        end
        MySQL.Async.execute('UPDATE player_vehicles SET state = 0, garage = NULL, impoundedtime = NULL, impoundreason = NULL, impoundedby = NULL, impoundtype = NULL, impoundfee = NULL, impoundtime = NULL, last_update = ? WHERE plate = ? AND state = 2', {os.time(), plate}, function(rowsChanged)
            if rowsChanged > 0 then
                -- Update OutsideVehicles tracking for LostVehicleTimeout
                OutsideVehicles[plate] = true
                TriggerClientEvent('QBCore:Notify', src, "You paid $" .. actualFee .. " to release your vehicle", "success")
            end
        end)
    end)
end)

RegisterNetEvent('dw-garages:server:ImpoundVehicle', function(plate, props, reason, impoundType, jobName, officerName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not Config.ImpoundJobs[Player.PlayerData.job.name] then
        TriggerClientEvent('QBCore:Notify', src, "You are not authorized to impound vehicles", "error")
        return
    end
    MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ? WHERE plate = ?', 
        {os.time(), reason, officerName, impoundType, plate}, 
        function(rowsChanged)
            if rowsChanged > 0 then
                -- Trigger vehicle deletion on all clients
                TriggerClientEvent('dw-garages:client:DeleteImpoundedVehicle', -1, plate)
                TriggerClientEvent('QBCore:Notify', src, "Vehicle impounded successfully", "success")
                
                local logData = {
                    plate = plate,
                    impoundedBy = officerName,
                    job = jobName,
                    reason = reason,
                    type = impoundType,
                    timestamp = os.time()
                }
                                
                MySQL.Async.fetchAll('SELECT citizenid FROM player_vehicles WHERE plate = ?', {plate}, function(result)
                    if result and #result > 0 then
                        local ownerCitizenId = result[1].citizenid
                        local ownerPlayer = QBCore.Functions.GetPlayerByCitizenId(ownerCitizenId)
                        
                        if ownerPlayer then
                            TriggerClientEvent('QBCore:Notify', ownerPlayer.PlayerData.source, "Your vehicle with plate " .. plate .. " has been impounded", "error")
                        end
                    end
                end)
            else
                TriggerClientEvent('QBCore:Notify', src, "Failed to impound vehicle - Vehicle not found in database", "error")
            end
        end
    )
end)


RegisterNetEvent('dw-garages:server:ImpoundVehicleWithParams', function(plate, props, reason, impoundType, jobName, officerName, impoundFee)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not Config.ImpoundJobs[Player.PlayerData.job.name] then
        TriggerClientEvent('QBCore:Notify', src, "You are not authorized to impound vehicles", "error")
        return
    end
    local fee = tonumber(impoundFee)
    MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
        {os.time(), reason, officerName, impoundType, fee, plate}, 
        function(rowsChanged)
            if rowsChanged > 0 then
                -- Trigger vehicle deletion on all clients
                TriggerClientEvent('dw-garages:client:DeleteImpoundedVehicle', -1, plate)
                TriggerClientEvent('QBCore:Notify', src, "Vehicle impounded with $" .. fee .. " fine", "success")
                
                local logData = {
                    plate = plate,
                    impoundedBy = officerName,
                    job = jobName,
                    reason = reason,
                    type = impoundType,
                    fee = fee,
                    timestamp = os.time()
                }
                            
                MySQL.Async.fetchAll('SELECT citizenid FROM player_vehicles WHERE plate = ?', {plate}, function(result)
                    if result and #result > 0 then
                        local ownerCitizenId = result[1].citizenid
                        local ownerPlayer = QBCore.Functions.GetPlayerByCitizenId(ownerCitizenId)
                        
                        if ownerPlayer then
                            TriggerClientEvent('QBCore:Notify', ownerPlayer.PlayerData.source, 
                                "Your vehicle with plate " .. plate .. " has been impounded", "error")
                        end
                    end
                end)
            else
                TriggerClientEvent('QBCore:Notify', src, "Failed to impound vehicle - Vehicle not found in database", "error")
            end
        end
    )
end)


MySQL.Async.execute([[
    SHOW COLUMNS FROM player_vehicles LIKE 'impoundedtime';
]], {}, function(result)
    if result and #result == 0 then
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundedtime INT NULL;", {})
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundreason VARCHAR(255) NULL;", {})
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundedby VARCHAR(255) NULL;", {})
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundtype VARCHAR(50) NULL;", {})
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundfee INT NULL;", {})
        MySQL.Async.execute("ALTER TABLE player_vehicles ADD COLUMN impoundtime INT NULL;", {})
    else
        Wait (100)
    end
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetImpoundedVehicles', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end
    
    local citizenid = Player.PlayerData.citizenid
    
    -- Make sure we're properly selecting impounded vehicles (state = 2)
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE citizenid = ? AND state = 2', {citizenid}, function(result)
        if result and #result > 0 then
            cb(result)
        else
            cb({})
        end
    end)
end)

QBCore.Functions.CreateCallback('dw-garages:server:GetJobGarageVehicles', function(source, cb, garageId)
    
    MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE garage = ? AND state = 1', {garageId}, function(result)
        if result and #result > 0 then
            cb(result)
        else
            cb({})
        end
    end)
end)

-- Admin command to release all impounded vehicles to legion garage
RegisterCommand('releaseallimpounds', function(source, args)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Check if player has admin permission
    if not QBCore.Functions.HasPermission(src, 'admin') and not QBCore.Functions.HasPermission(src, 'god') then
        TriggerClientEvent('QBCore:Notify', src, "You don't have permission to use this command", "error")
        return
    end
    
    -- Get all impounded vehicles (state = 2)
    MySQL.Async.fetchAll('SELECT plate FROM player_vehicles WHERE state = 2', {}, function(result)
        if not result or #result == 0 then
            TriggerClientEvent('QBCore:Notify', src, "No impounded vehicles found", "info")
            return
        end
        
        local count = #result
        local plates = {}
        for i = 1, count do
            table.insert(plates, result[i].plate)
        end
        
        -- Update all impounded vehicles to legion garage with state = 1 and clear impound fields
        MySQL.Async.execute('UPDATE player_vehicles SET state = 1, garage = ?, impoundedtime = NULL, impoundreason = NULL, impoundedby = NULL, impoundtype = NULL, impoundfee = NULL, impoundtime = NULL, last_update = ? WHERE state = 2', 
            {'legion', os.time()}, 
            function(rowsChanged)
                if rowsChanged > 0 then
                    TriggerClientEvent('QBCore:Notify', src, "Released " .. rowsChanged .. " impounded vehicle(s) to Legion Square Garage", "success")
                    print(string.format("[dw-garages] Admin %s (%s) released %d impounded vehicles to legion garage", Player.PlayerData.name, Player.PlayerData.citizenid, rowsChanged))
                else
                    TriggerClientEvent('QBCore:Notify', src, "Failed to release impounded vehicles", "error")
                end
            end
        )
    end)
end, false)

-- Track player's current vehicle for crash/disconnect handling
RegisterNetEvent('dw-garages:server:UpdatePlayerVehicle', function(plate)
    local src = source
    
    if plate then
        plate = plate:gsub("%s+", "") -- Remove spaces
        playerVehicles[src] = plate
    else
        playerVehicles[src] = nil
    end
end)

-- Handle player disconnect - move their vehicle to impound or legion garage
AddEventHandler('playerDropped', function(reason)
    local src = source
    local plate = playerVehicles[src]
    
    if plate then
        -- Clear tracking
        playerVehicles[src] = nil
        
        -- Check if vehicle exists in database and is currently out
        MySQL.Async.fetchAll('SELECT * FROM player_vehicles WHERE plate = ? AND state = 0', {plate}, function(result)
            if result and #result > 0 then
                local vehicle = result[1]
                local currentTime = os.time()
                
                -- Move vehicle to impound or legion garage
                -- Using "legion" garage as default (you can change to "impound" if preferred)
                local targetGarage = "legion"
                local targetState = 1 -- 1 = in garage, 2 = impounded
                
                -- Uncomment the line below if you want vehicles to go to impound instead
                -- targetGarage = "impound"
                -- targetState = 2
                
                if targetState == 2 then
                    -- Move to impound
                    MySQL.Async.execute('UPDATE player_vehicles SET state = 2, garage = "impound", impoundedtime = ?, impoundreason = ?, impoundedby = ?, impoundtype = ?, impoundfee = ? WHERE plate = ?', 
                        {
                            currentTime, 
                            "Vehicle recovered after crash/disconnect", 
                            "Automated System", 
                            "police", 
                            Config.ImpoundFee, 
                            plate
                        },
                        function(rowsChanged)
                            if rowsChanged > 0 then
                                if OutsideVehicles[plate] then
                                    OutsideVehicles[plate] = nil
                                end
                                print(string.format("[dw-garages] Player %s disconnected while in vehicle %s - moved to impound", src, plate))
                            end
                        end
                    )
                else
                    -- Move to legion garage
                    MySQL.Async.execute('UPDATE player_vehicles SET state = 1, garage = ? WHERE plate = ?', 
                        {targetGarage, plate},
                        function(rowsChanged)
                            if rowsChanged > 0 then
                                if OutsideVehicles[plate] then
                                    OutsideVehicles[plate] = nil
                                end
                                print(string.format("[dw-garages] Player %s disconnected while in vehicle %s - moved to %s garage", src, plate, targetGarage))
                            end
                        end
                    )
                end
            end
        end)
    end
end)

-- Event to set impound timer for newly purchased vehicles from dealership
RegisterNetEvent('dw-garages:server:SetImpoundTimer', function(plate)
    local src = source
    if not plate then return end
    
    plate = plate:gsub("%s+", "")
    
    -- Set impoundtime to current timestamp for newly purchased vehicle
    -- This allows the impound system to track when the vehicle was purchased
    MySQL.Async.execute('UPDATE player_vehicles SET impoundtime = ? WHERE plate = ?', 
        {os.time(), plate}, 
        function(rowsChanged)
            if rowsChanged > 0 then
                print(string.format("[dw-garages] Set impound timer for newly purchased vehicle: %s", plate))
            end
        end
    )
end)

-- Export function for other resources to call
exports('SetImpoundTimer', function(plate)
    if not plate then return end
    
    plate = plate:gsub("%s+", "")
    
    MySQL.Async.execute('UPDATE player_vehicles SET impoundtime = ? WHERE plate = ?', 
        {os.time(), plate}, 
        function(rowsChanged)
            if rowsChanged > 0 then
                print(string.format("[dw-garages] Set impound timer for newly purchased vehicle: %s", plate))
            end
        end
    )
end)