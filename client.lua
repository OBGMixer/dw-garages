local QBCore = exports['qb-core']:GetCoreObject()
local PlayerData = {}
local currentGarage = nil
local inGarageStation = false
local isMenuOpen = false
local currentVehicleData = nil
local isPlayerLoaded = false
local sharedGaragesData = {}
local houseGaragesData = {} -- Store house garage data: {propertyId = {coords, label, spawnPoint}}
local pendingJoinRequests = {}
local isHoveringVehicle = false
local hoveredVehicle = nil
local lastHoveredVehicle = nil
local vehicleHoverInfo = nil
local hoveredNetId = nil
local isGarageMenuOpen = false
local isVehicleFaded = false
local fadedVehicle = nil
local canStoreVehicle = false
local isStorageInProgress = false
local vehicleOwnershipCache = {}
local optimalParkingDistance = 12.0
local isTransferringVehicle = false
local transferAnimationActive = false
local currentTransferVehicle = nil
local isAtImpoundLot = false
local currentImpoundLot = nil
local impoundBlips = {}
local jobGarageBlips = {} -- Store job garage blips
local gangGarageBlips = {} -- Store gang garage blips
local lastGarageCheckTime = nil
local lastGarageId = nil
local lastGarageType = nil
local lastGarageCoords = nil
local lastGarageDist = nil
local activeConfirmation = nil
local activeAnimations = {}
local parkedJobVehicles = {}
local occupiedParkingSpots = {}
local jobParkingSpots = {}
local vehicleTargetZones = {} -- Track ox_target zones for vehicles: {vehicle = optionName}
local garageTargetZones = {} -- Track ox_target zones for garages: {garageKey = zoneId}

local function ApplyGarageLock(veh)
    if not DoesEntityExist(veh) then return end
    local lockState = 2
    local vehicleClass = GetVehicleClass(veh)
    if vehicleClass == 8 or vehicleClass == 13 then
        lockState = 1 -- Bikes need to stay unlocked to allow mounting
    end
    SetVehicleDoorsLocked(veh, lockState)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    if lockState == 2 then
        Wait(50)
        SetVehicleDoorsLocked(veh, lockState)
    end
end


RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    isPlayerLoaded = true
    
    -- Wait a bit for player to fully spawn
    Wait(5000)
    
    -- Update job/gang blips now that player is loaded
    UpdateJobGangBlips()
    
    -- Clean up any duplicate vehicles
    CleanupDuplicateVehicles()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    Wait(1000)
    
    if LocalPlayer.state.isLoggedIn then
        PlayerData = QBCore.Functions.GetPlayerData()
        isPlayerLoaded = true
        -- Update job/gang blips if player is already logged in
        Wait(2000)
        UpdateJobGangBlips()
        -- Wait a bit before cleanup to ensure all vehicles are loaded
        Wait(3000)
        -- Clean up any duplicate vehicles (only on resource start)
        CleanupDuplicateVehicles()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Clean up all ox_target zones
    if vehicleTargetZones then
        for vehicle, zoneId in pairs(vehicleTargetZones) do
            if zoneId then
                exports.ox_target:removeZone(zoneId)
            end
        end
        vehicleTargetZones = {}
    end
    
    if garageTargetZones then
        for garageKey, zoneId in pairs(garageTargetZones) do
            if zoneId then
                exports.ox_target:removeZone(zoneId)
            end
        end
        garageTargetZones = {}
    end
end)

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    PlayerData = data
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
    -- Update job garage blips when job changes
    UpdateJobGangBlips()
end)

RegisterNetEvent('QBCore:Client:OnGangUpdate', function(GangInfo)
    PlayerData.gang = GangInfo
    -- Update gang garage blips when gang changes
    UpdateJobGangBlips()
end)

-- Function to remove all job/gang blips
local function RemoveJobGangBlips()
    -- Remove all job garage blips
    for garageId, blip in pairs(jobGarageBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        jobGarageBlips[garageId] = nil
    end
    
    -- Remove all gang garage blips
    for garageId, blip in pairs(gangGarageBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
        gangGarageBlips[garageId] = nil
    end
end

-- Function to update job and gang garage blips based on player's current job/gang
function UpdateJobGangBlips()
    if not Config.GarageBlip.Enable then return end
    
    -- Remove existing job/gang blips
    RemoveJobGangBlips()
    
    -- Wait for player data to be available
    if not PlayerData or not isPlayerLoaded then return end
    
    -- Create job garage blips only for player's current job
    if PlayerData.job and PlayerData.job.name then
        local playerJob = PlayerData.job.name
        for k, v in pairs(Config.JobGarages) do
            if v.job == playerJob then
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
                SetBlipColour(blip, 38)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
                jobGarageBlips[k] = blip
            end
        end
    end
    
    -- Create gang garage blips only for player's current gang
    if PlayerData.gang and PlayerData.gang.name and PlayerData.gang.name ~= "none" then
        local playerGang = PlayerData.gang.name
        for k, v in pairs(Config.GangGarages) do
            if v.gang == playerGang then
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
                SetBlipColour(blip, 59)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
                gangGarageBlips[k] = blip
            end
        end
    end
        end
        
CreateThread(function()
    if Config.GarageBlip.Enable then
        -- Create public garage blips (always visible)
        for k, v in pairs(Config.Garages) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, Config.GarageBlip.Sprite)
            SetBlipDisplay(blip, Config.GarageBlip.Display)
            SetBlipScale(blip, Config.GarageBlip.Scale)
            SetBlipAsShortRange(blip, Config.GarageBlip.ShortRange)
            SetBlipColour(blip, Config.GarageBlip.Color)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
        end
        
        -- Wait for player to load before creating job/gang blips
        Wait(2000)
        UpdateJobGangBlips()
    end
end)

function FindJobParkingSpot(jobName)
    local spotsList = nil
    
    if Config.JobParkingSpots[jobName] then
        spotsList = Config.JobParkingSpots[jobName]
    else
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName then
                if v.spawnPoints then
                    spotsList = v.spawnPoints
                elseif v.spawnPoint then
                    spotsList = {v.spawnPoint}
                end
                break
            end
        end
    end
    
    if not spotsList or #spotsList == 0 then
        return nil
    end
    
    if not occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName] = {}
        
        local vehicles = GetGamePool('CVehicle')
        for _, veh in ipairs(vehicles) do
            local vehCoords = GetEntityCoords(veh)
            
            for i, spot in ipairs(spotsList) do
                local spotCoords = vector3(spot.x, spot.y, spot.z)
                if #(vehCoords - spotCoords) < 3.0 then
                    occupiedParkingSpots[jobName][i] = true
                    break
                end
            end
        end
    end
    
    for i, spot in ipairs(spotsList) do
        if not occupiedParkingSpots[jobName][i] then
            return i, spot
        end
    end
    
    return nil
end

function SetParkingSpotState(jobName, spotIndex, isOccupied)
    if not occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName] = {}
    end
    
    occupiedParkingSpots[jobName][spotIndex] = isOccupied
end

function ParkJobVehicle(vehicle, jobName)
    if not DoesEntityExist(vehicle) then return false end
    if not jobName then return false end
    
    -- Job vehicles should be put away (despawned), not parked in-world.
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then
        QBCore.Functions.Notify("Couldn't read vehicle plate", "error")
        return false
    end
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    
    -- Explicitly capture and save livery to props
    if DoesEntityExist(vehicle) then
        local livery = GetVehicleLivery(vehicle)
        if livery ~= nil and livery >= 0 then
            props.modLivery = livery
        end
    end
    
    local engineHealth = GetVehicleEngineHealth(vehicle) or 1000.0
    local bodyHealth = GetVehicleBodyHealth(vehicle) or 1000.0
    local fuelLevel = GetVehicleFuelLevel(vehicle)
    
    SetEntityAsMissionEntity(vehicle, true, true)
    
    QBCore.Functions.Notify("Storing vehicle...", "primary")
    
    -- Save/track job vehicle state server-side, then delete the entity client-side
        TriggerServerEvent('dw-garages:server:TrackJobVehicle', plate, jobName, props)
    FadeOutVehicle(vehicle, function()
        QBCore.Functions.Notify("Vehicle stored", "success")
    end)
    
    return true
end

function Lerp(a, b, t)
    return a + (b - a) * t
end

function GetClosestRoad(x, y, z, radius, oneSideOfRoad, allowJunctions)
    local outPosition = vector3(0.0, 0.0, 0.0)
    local outHeading = 0.0
    
    if GetClosestVehicleNode(x, y, z, outPosition, outHeading, 1, 3.0, 0) then
        return outPosition
    end
    
    return nil
end

function ShowConfirmDialog(title, message, onYes, onNo)
    activeConfirmation = {
        yesCallback = onYes,
        noCallback = onNo
    }
    
    local scaleform = RequestScaleformMovie("mp_big_message_freemode")
    while not HasScaleformMovieLoaded(scaleform) do
        Wait(0)
    end
    
    BeginScaleformMovieMethod(scaleform, "SHOW_SHARD_WASTED_MP_MESSAGE")
    ScaleformMovieMethodAddParamTextureNameString(title)
    ScaleformMovieMethodAddParamTextureNameString(message)
    ScaleformMovieMethodAddParamInt(5)
    EndScaleformMovieMethod()
    
    local key_Y = 246 
    local key_N = 306 
    
    CreateThread(function()
        local startTime = GetGameTimer()
        local showing = true
        
        while showing do
            Wait(0)
            
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
            
            BeginTextCommandDisplayHelp("STRING")
            AddTextComponentSubstringPlayerName("Press ~INPUT_REPLAY_START_STOP_RECORDING~ for YES or ~INPUT_REPLAY_SCREENSHOT~ for NO")
            EndTextCommandDisplayHelp(0, false, true, -1)
            
            if IsControlJustPressed(0, key_Y) then
                showing = false
                if activeConfirmation and activeConfirmation.yesCallback then
                    activeConfirmation.yesCallback()
                end
            elseif IsControlJustPressed(0, key_N) then
                showing = false
                if activeConfirmation and activeConfirmation.noCallback then
                    activeConfirmation.noCallback()
                end
            end
            
            if GetGameTimer() - startTime > 15000 then
                showing = false
                if activeConfirmation and activeConfirmation.noCallback then
                    activeConfirmation.noCallback()
                end
            end
        end
        
        SetScaleformMovieAsNoLongerNeeded(scaleform)
        activeConfirmation = nil
    end)
end

RegisterNetEvent('dw-garages:client:DeleteGarage')
AddEventHandler('dw-garages:client:DeleteGarage', function(garageId)
    TriggerServerEvent('dw-garages:server:DeleteSharedGarage', garageId)
end)

RegisterNUICallback('confirmRemoveVehicle', function(data, cb)
    local plate = data.plate
    
    SetNuiFocus(false, false)
    
    Wait(100)
    
    local removeMenu = {
        {
            header = "Remove Vehicle",
            isMenuHeader = true
        },
        {
            header = "Are you sure?",
            txt = "Remove this vehicle from the shared garage?",
            isMenuHeader = true
        },
        {
            header = "Yes, remove vehicle",
            txt = "The vehicle will be returned to your main garage",
            params = {
                isServer = true,
                event = "dw-garages:server:RemoveVehicleFromSharedGarage",
                args = {
                    plate = plate
                }
            }
        },
        {
            header = "No, cancel",
            txt = "Keep vehicle in shared garage",
            params = {
                event = "dw-garages:client:RestoreGarageFocus"
            }
        },
    }
    
    exports['qb-menu']:openMenu(removeMenu)
    
    cb({status = "success"})
end)

-- Restore NUI focus after qb-menu confirmations/cancels
RegisterNetEvent('dw-garages:client:RestoreGarageFocus', function()
    if isMenuOpen then
        SetNuiFocus(true, true)
    end
end)

RegisterNetEvent('dw-garages:client:ConfirmDeleteGarage', function(data)
    TriggerServerEvent('dw-garages:server:DeleteSharedGarage', data.garageId)
    
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](true)
        callbackRegistry[data.callback] = nil
    end
    
    SetNuiFocus(false, false)
end)

RegisterNetEvent('dw-garages:client:CancelDeleteGarage')
AddEventHandler('dw-garages:client:CancelDeleteGarage', function()
end)


RegisterNetEvent('dw-garages:client:ConfirmRemoveVehicle', function(data)
    TriggerServerEvent('dw-garages:server:RemoveVehicleFromSharedGarage', data.plate)
    
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](true)
        callbackRegistry[data.callback] = nil
    end
    
    -- Keep the garage UI interactive while server handles removal
    if isMenuOpen then
        SetNuiFocus(true, true)
    end
end)

RegisterNetEvent('dw-garages:client:CancelRemoveVehicle', function(data)
    if callbackRegistry[data.callback] then
        callbackRegistry[data.callback](false)
        callbackRegistry[data.callback] = nil
    end
    
    if isMenuOpen then
        SetNuiFocus(true, true)
    end
end)

callbackRegistry = {}

RegisterNUICallback('confirmDeleteGarage', function(data, cb)
    local garageId = data.garageId
    
    exports['qb-menu']:openMenu({
        {
            header = "Confirm Deletion",
            isMenuHeader = true
        },
        {
            header = "Delete Garage",
            txt = "All vehicles will be returned to owners",
            params = {
                event = "dw-garages:client:ConfirmDeleteSharedGarage",
                args = {
                    garageId = garageId
                }
            }
        },
        {
            header = "Cancel",
            txt = "Keep this garage",
            params = {
                event = "dw-garages:client:CancelDeleteGarage"
            }
        }
    })
    
    cb({status = "success"})
end)

RegisterNetEvent('dw-garages:client:ConfirmDeleteSharedGarage')
AddEventHandler('dw-garages:client:ConfirmDeleteSharedGarage', function(data)
    local garageId = data.garageId
    
    TriggerServerEvent('dw-garages:server:DeleteSharedGarage', garageId)
    
    SendNUIMessage({
        action = "garageDeleted",
        garageId = garageId
    })
end)

RegisterNUICallback('closeSharedGarageMenu', function(data, cb)
    SetNuiFocus(false, false)
    cb({status = "success"})
end)

function AnimateVehicleFade(vehicle, fromAlpha, toAlpha, duration, callback)
    if not DoesEntityExist(vehicle) then 
        if callback then callback() end
        return 
    end
    
    if not Config.EnableVehicleFade then
        if callback then callback() end
        return 
    end
    
    if activeAnimations[vehicle] then
        activeAnimations[vehicle] = nil
    end
    
    local startTime = GetGameTimer()
    local endTime = startTime + duration
    local animationId = math.random(1, 100000) 
    
    activeAnimations[vehicle] = animationId
    
    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId do
            Wait(10) 
        end
        
        if DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId then
            activeAnimations[vehicle] = nil
            
            if callback then callback() end
        end
    end)
end

function AnimateVehicleMove(vehicle, toCoords, toHeading, duration, callback)
    if not DoesEntityExist(vehicle) then 
        if callback then callback() end
        return 
    end
    
    local startCoords = GetEntityCoords(vehicle)
    local startHeading = GetEntityHeading(vehicle)
    local startTime = GetGameTimer()
    local endTime = startTime + duration
    local animationId = math.random(1, 100000) 
    activeAnimations[vehicle] = animationId
    NetworkRequestControlOfEntity(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetEntityInvincible(vehicle, true)
    SetVehicleDoorsLocked(vehicle, 4) 
    FreezeEntityPosition(vehicle, false)
    
    CreateThread(function()
        while GetGameTimer() < endTime and DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId do
            local progress = (GetGameTimer() - startTime) / duration
            local currentX = startCoords.x + (toCoords.x - startCoords.x) * progress
            local currentY = startCoords.y + (toCoords.y - startCoords.y) * progress
            local currentZ = startCoords.z + (toCoords.z - startCoords.z) * progress
            local currentHeading = startHeading + (toHeading - startHeading) * progress
            
            SetEntityCoordsNoOffset(vehicle, currentX, currentY, currentZ, false, false, false)
            SetEntityHeading(vehicle, currentHeading)
            
            Wait(0) 
        end
        
        if DoesEntityExist(vehicle) and activeAnimations[vehicle] == animationId then
            SetEntityCoordsNoOffset(vehicle, toCoords.x, toCoords.y, toCoords.z, false, false, false)
            SetEntityHeading(vehicle, toHeading)
            
            activeAnimations[vehicle] = nil
            
            SetEntityInvincible(vehicle, false)
            SetVehicleDoorsLocked(vehicle, 1) 
            
            if callback then callback() end
        end
    end)
end

function InitializeJobParkingSpots()
    for garageId, garageConfig in pairs(Config.JobGarages) do
        local jobName = garageConfig.job
        
        if not jobParkingSpots[jobName] then
            jobParkingSpots[jobName] = {}
            
            if garageConfig.spawnPoints and #garageConfig.spawnPoints > 0 then
                for _, spot in ipairs(garageConfig.spawnPoints) do
                    table.insert(jobParkingSpots[jobName], spot)
                end
            elseif garageConfig.spawnPoint then
                table.insert(jobParkingSpots[jobName], garageConfig.spawnPoint)
            end
        end
    end
end

Citizen.CreateThread(function()
    Wait(1000) 
    InitializeJobParkingSpots()
end)

function FindAvailableParkingSpot(jobName, currentVehicle)
    if not jobName then return nil end
    
    local parkingSpots = nil
    if Config.JobParkingSpots[jobName] then
        parkingSpots = Config.JobParkingSpots[jobName]
    else
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName then
                if v.spawnPoints then
                    parkingSpots = v.spawnPoints
                elseif v.spawnPoint then
                    parkingSpots = {v.spawnPoint}
                end
                break
            end
        end
    end
    
    if not parkingSpots or #parkingSpots == 0 then return nil end
    
    local allVehicles = GetGamePool('CVehicle')
    local occupiedSpots = {}
    
    for _, veh in ipairs(allVehicles) do
        if veh ~= currentVehicle and DoesEntityExist(veh) then
            local vehCoords = GetEntityCoords(veh)
            
            for spotIndex, spot in ipairs(parkingSpots) do
                local spotCoords = vector3(spot.x, spot.y, spot.z)
                if #(vehCoords - spotCoords) < 3.0 then
                    occupiedSpots[spotIndex] = true
                    break
                end
            end
        end
    end
    
    for spotIndex, spot in ipairs(parkingSpots) do
        if not occupiedSpots[spotIndex] then
            local spotCoords = vector3(spot.x, spot.y, spot.z)
            local _, _, _, _, entityHit = GetShapeTestResult(
                StartShapeTestBox(
                    spotCoords.x, spotCoords.y, spotCoords.z,
                    5.0, 2.5, 2.5,
                    0.0, 0.0, 0.0,
                    0, 2, currentVehicle, 4
                )
            )
            
            if not entityHit or entityHit == 0 then
                return spot
            end
        end
    end
    
    return nil
end


function IsJobVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then return false end
    
    if string.sub(plate, 1, 3) == "JOB" then
        return true
    end
    
    local model = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
    
    for jobName, jobGarage in pairs(Config.JobGarages) do
        if jobGarage.vehicles then
            for vehicleModel, vehicleInfo in pairs(jobGarage.vehicles) do
                if string.lower(vehicleModel) == modelName then
                    return true, jobName
                end
            end
        end
    end
    
    return false
end

function DoesPlayerJobMatchVehicleJob(vehicle)
    if not DoesEntityExist(vehicle) then return false end
    if not PlayerData.job then return false end
    
    local jobName = PlayerData.job.name
    if not jobName then return false end
    
    local isJobVehicle, vehicleJobName = IsJobVehicle(vehicle)
    if not isJobVehicle then return false end
    
    if not vehicleJobName then
        local model = GetEntityModel(vehicle)
        local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
        
        for k, v in pairs(Config.JobGarages) do
            if v.job == jobName and v.vehicles then
                for vehModel, _ in pairs(v.vehicles) do
                    if string.lower(vehModel) == modelName then
                        return true
                    end
                end
            end
        end
        return false
    end
    
    return vehicleJobName == jobName
end

function FindJobVehicleParkingSpot(jobName)
    if not jobName then return nil end
    
    local jobGarage = nil
    for k, v in pairs(Config.JobGarages) do
        if v.job == jobName then
            jobGarage = v
            break
        end
    end
    
    if not jobGarage then return nil end
    
    local parkingSpots = nil
    if jobGarage.spawnPoints then
        parkingSpots = jobGarage.spawnPoints
    else
        parkingSpots = {jobGarage.spawnPoint}
    end
    
    for _, spot in ipairs(parkingSpots) do
        local spotCoords = vector3(spot.x, spot.y, spot.z)
        local heading = spot.w
        local clear = true
        
        local radius = 2.5
        local vehicles = GetGamePool('CVehicle')
        for i = 1, #vehicles do
            local vehCoords = GetEntityCoords(vehicles[i])
            if #(vehCoords - spotCoords) < radius then
                clear = false
                break
            end
        end
        
        if clear then
            return spotCoords, heading
        end
    end
    
    return nil
end


RegisterNUICallback('getJobVehicles', function(data, cb)
    local job = data.job
    if not job then
        cb({ jobVehicles = {} })
        return
    end
    
    local jobVehicles = {}
    
    for k, garage in pairs(Config.JobGarages) do
        if garage.job == job then
            local i = 1
            for model, vehicle in pairs(garage.vehicles) do
                table.insert(jobVehicles, {
                    id = i,
                    model = model,
                    name = vehicle.label,
                    fuel = 100,
                    engine = 100,
                    body = 100,
                    state = 1,
                    stored = true,
                    isJobVehicle = true,
                    icon = vehicle.icon or "🚗"
                })
                i = i + 1
            end
            break
        end
    end
    
    cb({ jobVehicles = jobVehicles })
end)

RegisterNUICallback('takeOutJobVehicle', function(data, cb)
    local model = data.model
    
    if not model then
        cb({status = "error", message = "Invalid model"})
        return
    end
    
    local job = PlayerData.job.name
    if not job then
        cb({status = "error", message = "No job found"})
        return
    end
    
    local garageInfo = nil
    for k, v in pairs(Config.JobGarages) do
        if v.job == job then
            garageInfo = v
            break
        end
    end
    
    if not garageInfo then
        cb({status = "error", message = "Job garage not found"})
        return
    end
    
    local spawnPoints = nil
    if garageInfo.spawnPoints then
        spawnPoints = garageInfo.spawnPoints
    else
        spawnPoints = {garageInfo.spawnPoint}
    end
    
    local clearPoint = FindClearSpawnPoint(spawnPoints)
    if not clearPoint then
        cb({status = "error", message = "All spawn locations are blocked!"})
        return
    end
    
    local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
    QBCore.Functions.SpawnVehicle(model, function(veh)
        if not veh or veh == 0 then
            QBCore.Functions.Notify("Error creating job vehicle. Please try again.", "error")
            cb({status = "error", message = "Failed to spawn vehicle"})
            return
        end
        
        -- Make vehicle persist when player disconnects
        SetEntityAsMissionEntity(veh, true, true)
        SetEntityCanBeDamaged(veh, true)
        SetEntityInvincible(veh, false)
        if NetworkGetEntityIsNetworked(veh) then
            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
        end
        
        SetEntityHeading(veh, clearPoint.w)
        FadeInVehicle(veh)
        
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleDirtLevel(veh, 0.0) 
        SetVehicleUndriveable(veh, false)
        SetVehicleEngineOn(veh, false, true, false)
        
        FixEngineSmoke(veh)
        
        -- Lock vehicle doors (after all properties are set)
        Wait(100) -- Additional wait to ensure everything is set
        ApplyGarageLock(veh)
        
        -- Set fuel after vehicle is fully initialized (use fuel export if available)
        Wait(200) -- Wait for fuel system to initialize
        local fuelSet = false
        if GetResourceState('LegacyFuel') ~= 'missing' then
            local success, result = pcall(function() return exports['LegacyFuel']:SetFuel(veh, 100.0) end)
            if success then fuelSet = true end
        end
        if not fuelSet and GetResourceState('ps-fuel') ~= 'missing' then
            local success, result = pcall(function() return exports['ps-fuel']:SetFuel(veh, 100.0) end)
            if success then fuelSet = true end
        end
        if not fuelSet and GetResourceState('qb-fuel') ~= 'missing' then
            local success, result = pcall(function() return exports['qb-fuel']:SetFuel(veh, 100.0) end)
            if success then fuelSet = true end
        end
        if not fuelSet then
            SetVehicleFuelLevel(veh, 100.0)
        end
        
        -- Give keys to player
        local plate = QBCore.Functions.GetPlate(veh)
        if plate then
            TriggerEvent("vehiclekeys:client:SetOwner", plate)
        end
        
        QBCore.Functions.Notify("Job vehicle taken out", "success")
        cb({status = "success"})
    end, spawnCoords, true)
    
    SetNuiFocus(false, false)
    isMenuOpen = false
end)

RegisterNUICallback('refreshVehicles', function(data, cb)
    local garageId = data.garageId
    local garageType = data.garageType
    
    if garageType == "public" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "gang" then
        local gang = PlayerData.gang.name
        QBCore.Functions.TriggerCallback('dw-garages:server:GetGangVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, gang, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarageVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "house" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetHouseGarageVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "impound" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetImpoundedVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end)
    end
    
    cb({status = "refreshing"})
end)

function FormatVehiclesForNUI(vehicles)
    local formattedVehicles = {}
    local currentGarageId = currentGarage and currentGarage.id or nil    
    for i, vehicle in ipairs(vehicles) do
        local vehicleInfo = QBCore.Shared.Vehicles[vehicle.vehicle]
        if vehicleInfo then
            local enginePercent = round(vehicle.engine / 10, 1)
            local bodyPercent = round(vehicle.body / 10, 1)
            local fuelPercent = vehicle.fuel or 100
            
            local displayName = vehicleInfo.name
            if vehicle.custom_name and vehicle.custom_name ~= "" then
                displayName = vehicle.custom_name
            end
            
            local isInCurrentGarage = false
            if currentGarage and currentGarage.type == "job" then
                isInCurrentGarage = true
            else
                if vehicle.garage and currentGarageId then
                    isInCurrentGarage = (vehicle.garage == currentGarageId)
                end
            end
            
            local impoundFee = nil
            local impoundReason = nil
            local impoundedBy = nil
            local daysImpounded = nil
            
            if vehicle.state == 2 then
                impoundFee = Config.ImpoundFee  
                
                if vehicle.impoundfee ~= nil then
                    local customFee = tonumber(vehicle.impoundfee)
                    if customFee and customFee > 0 then
                        impoundFee = customFee
                    end
                end
                
                impoundReason = vehicle.impoundreason or "No reason specified"
                impoundedBy = vehicle.impoundedby or "Unknown Officer"
                daysImpounded = 1
            end
            
            local isStored = vehicle.state == 1
            local isOut = vehicle.state == 0
            
            table.insert(formattedVehicles, {
                id = i,
                plate = vehicle.plate,
                model = vehicle.vehicle,
                name = displayName,
                fuel = fuelPercent,
                engine = enginePercent,
                body = bodyPercent,
                state = vehicle.state,
                garage = vehicle.garage or "Unknown", 
                stored = isStored,
                isOut = isOut,
                inCurrentGarage = isInCurrentGarage,
                isFavorite = vehicle.is_favorite == 1,
                owner = vehicle.citizenid,
                ownerName = vehicle.owner_name,
                storedInGang = vehicle.stored_in_gang,
                storedInShared = vehicle.shared_garage_id ~= nil,
                sharedGarageId = vehicle.shared_garage_id,
                currentGarage = currentGarageId,
                impoundFee = impoundFee,
                impoundReason = impoundReason,
                impoundedBy = impoundedBy,
                daysImpounded = daysImpounded,
                impoundType = vehicle.impoundtype
            })
        end
    end
    
    return formattedVehicles
end

Citizen.CreateThread(function()
    while QBCore == nil do
        Wait(0)
    end
    
    local originalDeleteVehicle = QBCore.Functions.DeleteVehicle
    
    QBCore.Functions.DeleteVehicle = function(vehicle)
        if DoesEntityExist(vehicle) then
            local plate = QBCore.Functions.GetPlate(vehicle)
            -- For player-owned vehicles, don't delete - let them persist when players disconnect
            if plate then
                -- Check if it's a player vehicle by checking if it's a mission entity
                -- Player vehicles are set as mission entities, so they persist
                if IsEntityAMissionEntity(vehicle) then
                    -- Player vehicle - don't delete, don't update state
                    -- Vehicle stays in world and LostVehicleTimeout will handle cleanup
                    return -- Don't delete, don't call original
                end
            end
            -- Not a player vehicle or no plate - safe to delete normally
            local netId = nil
            if NetworkGetEntityIsNetworked(vehicle) then
                netId = NetworkGetNetworkIdFromEntity(vehicle)
            end
            if netId then
                TriggerServerEvent('QBCore:Server:DeleteVehicle', netId)
            end
            return originalDeleteVehicle(vehicle)
        end
    end
end)

-- Global tracking for vehicle positions (moved outside thread for access from other functions)
local lastSavedPositions = {} -- Track last saved position to avoid unnecessary updates

Citizen.CreateThread(function()
    local trackedVehicles = {}
    
    while true do
        Wait(30000) -- Check every 30 seconds (reduced frequency to prevent spam)
        local vehicles = GetGamePool('CVehicle')
        local currentVehicles = {}
        
        for _, vehicle in pairs(vehicles) do
            if DoesEntityExist(vehicle) then
                local plate = QBCore.Functions.GetPlate(vehicle)
                if plate then
                    -- Normalize plate (remove spaces) for consistent tracking
                    local normalizedPlate = plate:gsub("%s+", "")
                    -- Only track player vehicles (mission entities)
                    if IsEntityAMissionEntity(vehicle) then
                        currentVehicles[normalizedPlate] = true
                        currentVehicles[plate] = true -- Also track with original format for compatibility
                        
                        -- Ensure vehicle remains as mission entity (prevent despawn on teleport/MLO)
                        SetEntityAsMissionEntity(vehicle, true, true)
                        if NetworkGetEntityIsNetworked(vehicle) then
                            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(vehicle), false)
                        end
                        
                        local coords = GetEntityCoords(vehicle)
                        local heading = GetEntityHeading(vehicle)
                        local fuel = GetVehicleFuelLevel(vehicle)
                        
                        -- Check if position changed significantly (more than 10 meters to reduce updates)
                        -- Use normalized plate for consistent tracking
                        local lastPos = lastSavedPositions[normalizedPlate] or lastSavedPositions[plate]
                        local positionChanged = true
                        local distanceChanged = 10.0 -- Only update if moved more than 10 meters (increased to reduce spam)
                        
                        if lastPos then
                            local distance = #(vector3(coords.x, coords.y, coords.z) - vector3(lastPos.x, lastPos.y, lastPos.z))
                            positionChanged = distance > distanceChanged
                        end
                        
                        if positionChanged then
                            -- Position changed significantly, save full position data
                            local vehicleData = {
                                x = coords.x,
                                y = coords.y,
                                z = coords.z,
                                heading = heading,
                                fuel = fuel
                            }
                            -- Store with normalized plate for consistency
                            lastSavedPositions[normalizedPlate] = vehicleData
                            -- Also keep old format if different for compatibility
                            if normalizedPlate ~= plate then
                                lastSavedPositions[plate] = nil -- Remove old format
                            end
                            TriggerServerEvent('dw-garages:server:SaveVehiclePosition', normalizedPlate, vehicleData, true)
                        else
                            -- Position hasn't changed much, just update last_update for LostVehicleTimeout
                            -- This avoids expensive JSON encoding/decoding and mods column update
                            -- Only update if it's been a while (throttled on server side)
                            TriggerServerEvent('dw-garages:server:UpdateVehicleState', normalizedPlate, 0)
                        end
                    end
                end
            end
        end
        
        -- Clean up positions for vehicles that are no longer tracked
        -- But verify vehicle is actually gone before removing (might just be out of range)
        -- IMPORTANT: Normalize plates consistently to prevent mismatches
        for plate, _ in pairs(lastSavedPositions) do
            local normalizedPlate = plate:gsub("%s+", "")
            if not currentVehicles[normalizedPlate] and not currentVehicles[plate] then
                -- Double-check: vehicle might still exist but not be a mission entity yet
                -- Only remove if we're certain it's gone (don't remove too aggressively)
                local vehicleStillExists = false
                for _, veh in pairs(vehicles) do
                    if DoesEntityExist(veh) then
                        local vehPlate = QBCore.Functions.GetPlate(veh)
                        if vehPlate then
                            vehPlate = vehPlate:gsub("%s+", "")
                            if vehPlate == normalizedPlate or vehPlate == plate then
                                vehicleStillExists = true
                                -- Re-apply mission entity status if vehicle exists but lost it
                                if not IsEntityAMissionEntity(veh) then
                                    SetEntityAsMissionEntity(veh, true, true)
                                    if NetworkGetEntityIsNetworked(veh) then
                                        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                                    end
                                end
                                -- Re-add to currentVehicles with normalized plate
                                currentVehicles[normalizedPlate] = true
                                break
                            end
                        end
                    end
                end
                
                -- Only remove from tracking if vehicle truly doesn't exist
                -- Don't remove if vehicle might just be temporarily out of range
                if not vehicleStillExists then
                    -- Only remove if we're very confident the vehicle is gone
                    -- Keep tracking for a bit longer to prevent false removals
                    lastSavedPositions[plate] = nil
                end
            end
        end
        
        -- Don't mark vehicles as deleted when they disappear - let them persist
        -- LostVehicleTimeout will handle moving abandoned vehicles to impound
        trackedVehicles = currentVehicles
    end
end)

-- Maintenance thread: Ensure all player vehicles remain persistent (prevent despawn on teleport/MLO/disconnect)
Citizen.CreateThread(function()
    while true do
        Wait(30000) -- Check every 30 seconds
        
        if PlayerData and PlayerData.citizenid then
            -- Get all vehicles that should be out (state = 0) for this player
            QBCore.Functions.TriggerCallback('dw-garages:server:GetPlayerOutVehicles', function(outVehicles)
                if outVehicles and #outVehicles > 0 then
                    local vehicles = GetGamePool('CVehicle')
                    
                    -- Ensure all player vehicles maintain persistence settings
                    for _, veh in pairs(vehicles) do
                        if DoesEntityExist(veh) then
                            local vehPlate = QBCore.Functions.GetPlate(veh)
                            if vehPlate then
                                -- Check if this is a player vehicle (mission entity)
                                if IsEntityAMissionEntity(veh) then
                                    -- Ensure mission entity status is maintained (prevents despawn on disconnect/teleport)
                                    SetEntityAsMissionEntity(veh, true, true)
                                    if NetworkGetEntityIsNetworked(veh) then
                                        SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        else
            Wait(30000) -- Wait longer if player not loaded
        end
    end
end)

RegisterNetEvent('QBCore:Command:DeleteVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh ~= 0 then
        local plate = QBCore.Functions.GetPlate(veh)
        if plate then
            TriggerServerEvent('dw-garages:server:HandleDeletedVehicle', plate)
        end
    else
        local coords = GetEntityCoords(ped)
        local vehicles = GetGamePool('CVehicle')
        for _, v in pairs(vehicles) do
            if #(coords - GetEntityCoords(v)) <= 5.0 then
                local plate = QBCore.Functions.GetPlate(v)
                if plate then
                    TriggerServerEvent('dw-garages:server:HandleDeletedVehicle', plate)
                end
            end
        end
    end
end)

-- Flag to prevent cleanup during active gameplay (only run on initial load)
local cleanupPerformed = false

-- Clean up duplicate vehicles (same plate) - keep only the first one found
-- Only cleans up vehicles that are mission entities (player-owned) to avoid deleting other players' vehicles
-- Only runs once on initial load to prevent interfering with active gameplay
function CleanupDuplicateVehicles()
    if cleanupPerformed then return end -- Only run once
    if not PlayerData or not PlayerData.citizenid then return end
    
    local vehicles = GetGamePool('CVehicle')
    local plateCounts = {}
    local vehiclesByPlate = {}
    
    -- Count vehicles by plate (only mission entities - player-owned vehicles)
    for _, veh in pairs(vehicles) do
        if DoesEntityExist(veh) and IsEntityAMissionEntity(veh) then
            local vehPlate = QBCore.Functions.GetPlate(veh)
            if vehPlate then
                vehPlate = vehPlate:gsub("%s+", "")
                if not plateCounts[vehPlate] then
                    plateCounts[vehPlate] = 0
                    vehiclesByPlate[vehPlate] = {}
                end
                plateCounts[vehPlate] = plateCounts[vehPlate] + 1
                table.insert(vehiclesByPlate[vehPlate], veh)
            end
        end
    end
    
    -- Delete duplicates (keep first, delete rest) - but verify they're still mission entities
    for plate, count in pairs(plateCounts) do
        if count > 1 and vehiclesByPlate[plate] then
            -- Keep the first vehicle that still exists and is a mission entity
            local keptVehicle = nil
            for i = 1, #vehiclesByPlate[plate] do
                local veh = vehiclesByPlate[plate][i]
                if DoesEntityExist(veh) and IsEntityAMissionEntity(veh) then
                    if not keptVehicle then
                        keptVehicle = veh
                    else
                        -- This is a duplicate, delete it
                        SetEntityAsMissionEntity(veh, false, true)
                        DeleteEntity(veh)
                    end
                end
            end
        end
    end
    
    cleanupPerformed = true -- Mark as performed to prevent running again
end

-- Respawn functionality removed - vehicles will persist when left out or player disconnects

RegisterNUICallback('checkVehicleState', function(data, cb)
    local plate = data.plate
    
    if not plate then
        cb({state = 1}) 
        return
    end
    QBCore.Functions.TriggerCallback('dw-garages:server:CheckVehicleStatus', function(isStored)
        if isStored then
            cb({state = 1}) 
        else
            cb({state = 0}) 
        end
    end, plate)
end)

RegisterNUICallback('refreshImpoundVehicles', function(data, cb)
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetImpoundedVehicles', function(vehicles)
        if vehicles then            
            for i, vehicle in ipairs(vehicles) do
                Wait (100)
            end
            
            local formattedVehicles = FormatVehiclesForNUI(vehicles)            
            SendNUIMessage({
                action = "refreshVehicles",
                vehicles = formattedVehicles
            })
        else
            SendNUIMessage({
                action = "refreshVehicles",
                vehicles = {}
            })
        end
    end)
    
    cb({status = "refreshing"})
end)

RegisterCommand('debuggarage', function(source, args)
    local garageId = args[1] or (currentGarage and currentGarage.id or "unknown")
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetJobGarageVehicles', function(vehicles)        
        for i, v in ipairs(vehicles) do
            Wait (100)
        end
        local formatted = FormatVehiclesForNUI(vehicles)
        
        local currentGarageTest = currentGarage
        currentGarage = {id = garageId, type = "job"}
        QBCore.Functions.Notify("Found " .. #vehicles .. " vehicles in " .. garageId .. " garage", "primary", 5000)
        
        currentGarage = currentGarageTest
    end, garageId)
end, false)

function GetClosestVehicleInGarage(garageCoords, maxDistance)
    local ped = PlayerPedId()
    local pedCoords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local closestVehicle = 0
    local closestDistance = maxDistance
    
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        local vehicleCoords = GetEntityCoords(vehicle)
        
        local distToGarage = #(vehicleCoords - garageCoords)
        
        if distToGarage <= maxDistance then
            local distToPlayer = #(vehicleCoords - pedCoords)
            
            if distToPlayer < closestDistance then
                closestVehicle = vehicle
                closestDistance = distToPlayer
            end
        end
    end
    
    if DoesEntityExist(closestVehicle) then
        Wait (100)
    end
    
    return closestVehicle
end

function FadeOutVehicle(vehicle, callback)
    if not Config.EnableVehicleFade then
        -- When storing in garage, allow deletion even if it's a mission entity
        -- Remove mission entity status temporarily to allow deletion
        if DoesEntityExist(vehicle) then
            local plate = QBCore.Functions.GetPlate(vehicle)
            
            if IsEntityAMissionEntity(vehicle) then
                SetEntityAsMissionEntity(vehicle, false, true)
            end
            -- Allow network migration temporarily for deletion
            local netId = nil
            if NetworkGetEntityIsNetworked(vehicle) then
                netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId then
                    SetNetworkIdCanMigrate(netId, true)
                end
            end
            -- Delete the vehicle
            DeleteEntity(vehicle)
            
            -- Remove from tracking immediately to prevent tracking thread from affecting other vehicles
            if plate then
                plate = plate:gsub("%s+", "")
                lastSavedPositions[plate] = nil
            end
        end
        
        if callback then callback() end
        return
end
    
    CreateThread(function()
        -- When storing in garage, allow deletion even if it's a mission entity
        -- Remove mission entity status temporarily to allow deletion
        if DoesEntityExist(vehicle) then
            local plate = QBCore.Functions.GetPlate(vehicle)
            
            if IsEntityAMissionEntity(vehicle) then
                SetEntityAsMissionEntity(vehicle, false, true)
            end
            -- Allow network migration temporarily for deletion
            local netId = nil
            if NetworkGetEntityIsNetworked(vehicle) then
                netId = NetworkGetNetworkIdFromEntity(vehicle)
                if netId then
                    SetNetworkIdCanMigrate(netId, true)
                end
            end
            -- Delete the vehicle
            DeleteEntity(vehicle)
            
            -- Remove from tracking immediately to prevent tracking thread from affecting other vehicles
            if plate then
                plate = plate:gsub("%s+", "")
                lastSavedPositions[plate] = nil
            end
        end
        
        if callback then callback() end
    end)
end

function FadeInVehicle(vehicle)
    -- Vehicle fade functionality removed
    return
end

function GetAllAttachedEntities(entity)
    local entities = {}
    
    if IsEntityAVehicle(entity) and IsVehicleAttachedToTrailer(entity) then
        local trailer = GetVehicleTrailerVehicle(entity)
        if trailer and trailer > 0 then
            table.insert(entities, trailer)
        end
    end
    
    return entities
end

function GetClosestGaragePoint()
    local playerPos = GetEntityCoords(PlayerPedId())
    local closestDist = 1000.0
    local closestGarage = nil
    local closestCoords = nil
    local closestGarageType = nil
    
    for k, v in pairs(Config.Garages) do
        local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
        local dist = #(playerPos - garageCoords)
        if dist < closestDist then
            closestDist = dist
            closestGarage = k
            closestCoords = garageCoords
            closestGarageType = "public"
        end
    end
    
    if PlayerData.job then
        for k, v in pairs(Config.JobGarages) do
            if v.job == PlayerData.job.name then
                local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
                local dist = #(playerPos - garageCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestGarage = k
                    closestCoords = garageCoords
                    closestGarageType = "job"
                end
            end
        end
    end
    
    if PlayerData.gang and PlayerData.gang.name ~= "none" then
        for k, v in pairs(Config.GangGarages) do
            if v.gang == PlayerData.gang.name then
                local garageCoords = vector3(v.coords.x, v.coords.y, v.coords.z)
                local dist = #(playerPos - garageCoords)
                if dist < closestDist then
                    closestDist = dist
                    closestGarage = k
                    closestCoords = garageCoords
                    closestGarageType = "gang"
                end
            end
        end
    end
    
    -- Check house garages
    for propertyId, garageData in pairs(houseGaragesData) do
        if garageData.coords then
            local dist = #(playerPos - garageData.coords)
            if dist < closestDist then
                closestDist = dist
                closestGarage = propertyId
                closestCoords = garageData.coords
                closestGarageType = "house"
            end
        end
    end
    
    if closestDist <= optimalParkingDistance then
        return closestGarage, closestGarageType, closestCoords, closestDist
    end
    
    return nil, nil, nil, nil
end

function FindClearSpawnPoint(spawnPoints)
    for i, point in ipairs(spawnPoints) do
        local coords = vector3(point.x, point.y, point.z)
        local clear = true
        
        local vehicles = GetGamePool('CVehicle')
        for j = 1, #vehicles do
            local vehicleCoords = GetEntityCoords(vehicles[j])
            if #(vehicleCoords - coords) <= 3.0 then
                clear = false
                break
            end
        end
        
        if clear then
            return point
        end
    end
    
    return nil
end

function IsVehicleOwned(vehicle)
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then return false end
    
    if vehicleOwnershipCache[plate] ~= nil then
        return vehicleOwnershipCache[plate]
    end
    
    vehicleOwnershipCache[plate] = false
    
    QBCore.Functions.TriggerCallback('dw-garages:server:CheckIfVehicleOwned', function(owned)
        vehicleOwnershipCache[plate] = owned
    end, plate)
    
    return vehicleOwnershipCache[plate]
end


CreateThread(function()
    while true do
        Wait(60000)
        vehicleOwnershipCache = {}
    end
end)

function FixEngineSmoke(vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    
    SetVehicleEngineHealth(vehicle, 1000.0)
    Wait(50)
    
    if engineHealth < 300.0 then
        engineHealth = 300.0
    end
    
    SetVehicleEngineHealth(vehicle, engineHealth)
    SetVehicleEngineOn(vehicle, false, true, false)
    SetVehicleDamage(vehicle, 0.0, 0.0, 0.3, 0.0, 0.0, false)
    
    SetEntityProofs(vehicle, false, true, false, false, false, false, false, false)
    Wait(100)
    SetEntityProofs(vehicle, false, false, false, false, false, false, false, false)
end

-- Using ox_target for all interactions
CreateThread(function()
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local isInVehicle = IsPedInAnyVehicle(ped, false)
        local vehicle = GetVehiclePedIsIn(ped, true)
        
        if not DoesEntityExist(vehicle) then 
            isVehicleFaded = false
            fadedVehicle = nil
            canStoreVehicle = false
            isStorageInProgress = false
            -- Clean up ox_target zones for deleted vehicles
            if vehicleTargetZones[vehicle] then
                exports.ox_target:removeLocalEntity(vehicle, vehicleTargetZones[vehicle])
                vehicleTargetZones[vehicle] = nil
            end
            Wait(sleep)
            goto continue
        end
        
        if not isInVehicle and DoesEntityExist(vehicle) and vehicle > 0 then
            local garageId, garageType, garageCoords, garageDist = GetClosestGaragePoint()
            
            if garageId and garageDist <= optimalParkingDistance then
                local pedInDriverSeat = GetPedInVehicleSeat(vehicle, -1)
                local speed = GetEntitySpeed(vehicle)
                local isStationary = speed < 0.1
                
                if pedInDriverSeat == 0 and isStationary then
                    local vehicleCoords = GetEntityCoords(vehicle)
                    local playerCoords = GetEntityCoords(ped)
                    local distToVehicle = #(playerCoords - vehicleCoords)
                    local plate = QBCore.Functions.GetPlate(vehicle)
                    
                    if not plate then goto skip_vehicle end
                    
                    if garageType == "job" and PlayerData.job then
                        local jobName = PlayerData.job.name
                        local jobGarage = Config.JobGarages[garageId]
                        
                        if jobGarage and jobGarage.job == jobName then
                            local isJobVehicle = false
                            local model = GetEntityModel(vehicle)
                            local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
                            
                            if jobGarage.vehicles then
                                for jobVehModel, _ in pairs(jobGarage.vehicles) do
                                    if string.lower(jobVehModel) == modelName then
                                        isJobVehicle = true
                                        break
                                    end
                                end
                            end
                            
                            if isJobVehicle then
                                if distToVehicle < 10.0 then
                                    if not isVehicleFaded or fadedVehicle ~= vehicle then
                                        isVehicleFaded = true
                                        fadedVehicle = vehicle
                                        canStoreVehicle = true
                                    end
                                
                                    if distToVehicle < 5.0 and not isStorageInProgress then
                                        sleep = 0
                                        -- Add ox_target zone for vehicle if not already added
                                        if not vehicleTargetZones[vehicle] then
                                            local plate = QBCore.Functions.GetPlate(vehicle) or tostring(vehicle)
                                            local zoneName = 'park_job_vehicle_' .. plate
                                            -- Remove any existing target on this entity first
                                            if vehicleTargetZones[vehicle] then
                                                exports.ox_target:removeLocalEntity(vehicle, vehicleTargetZones[vehicle])
                                            end
                                            exports.ox_target:addLocalEntity(vehicle, {
                                                {
                                                    name = zoneName,
                                                    icon = 'fas fa-parking',
                                                    label = 'Park Vehicle',
                                                    onSelect = function()
                                                        if canStoreVehicle then
                                                            isStorageInProgress = true
                                                            canStoreVehicle = false
                                                            ParkJobVehicle(vehicle, jobName)
                                                            Citizen.SetTimeout(3000, function()
                                                                isStorageInProgress = false
                                                            end)
                                                        end
                                                    end
                                                }
                                            })
                                            vehicleTargetZones[vehicle] = zoneName
                                        end
                                    end
                                else
                                    if isVehicleFaded and fadedVehicle == vehicle then
                                        isVehicleFaded = false
                                        fadedVehicle = nil
                                        -- Remove ox_target zone when vehicle is out of range
                                        if vehicleTargetZones[vehicle] then
                                            local plate = QBCore.Functions.GetPlate(vehicle) or tostring(vehicle)
                                            exports.ox_target:removeLocalEntity(vehicle, 'park_job_vehicle_' .. plate)
                                            vehicleTargetZones[vehicle] = nil
                                        end
                                        canStoreVehicle = false
                                    end
                                end
                                
                                goto skip_vehicle
                            end
                        end
                    end
                    
                    local isOwned = vehicleOwnershipCache[plate]
                    if isOwned == nil then
                        QBCore.Functions.TriggerCallback('dw-garages:server:CheckIfVehicleOwned', function(owned)
                            vehicleOwnershipCache[plate] = owned
                        end, plate)
                        isOwned = false
                    end

                    if isOwned then
                        if distToVehicle < 10.0 then
                            if not isVehicleFaded or fadedVehicle ~= vehicle then
                                isVehicleFaded = true
                                fadedVehicle = vehicle
                                canStoreVehicle = true
                            end
                        
                            if distToVehicle < 5.0 and not isStorageInProgress then
                                sleep = 0
                                -- Add ox_target zone for vehicle if not already added
                                if not vehicleTargetZones[vehicle] then
                                    local plate = QBCore.Functions.GetPlate(vehicle) or tostring(vehicle)
                                    local zoneName = 'store_vehicle_' .. plate
                                    -- Remove any existing target on this entity first
                                    if vehicleTargetZones[vehicle] then
                                        exports.ox_target:removeLocalEntity(vehicle, vehicleTargetZones[vehicle])
                                    end
                                    exports.ox_target:addLocalEntity(vehicle, {
                                        {
                                            name = zoneName,
                                            icon = 'fas fa-warehouse',
                                            label = 'Store Vehicle',
                                            onSelect = function()
                                                if canStoreVehicle then
                                                    TriggerEvent('dw-garages:client:StoreVehicle', {
                                                        garageId = garageId,
                                                        garageType = garageType
                                                    })
                                                end
                                                    end
                                                }
                                            })
                                    vehicleTargetZones[vehicle] = zoneName
                                end
                            end
                        else
                            if isVehicleFaded and fadedVehicle == vehicle then
                                isVehicleFaded = false
                                fadedVehicle = nil
                                -- Remove ox_target zone when vehicle is out of range
                                if vehicleTargetZones[vehicle] then
                                    exports.ox_target:removeLocalEntity(vehicle, vehicleTargetZones[vehicle])
                                    vehicleTargetZones[vehicle] = nil
                                end
                                canStoreVehicle = false
                            end
                        end
                    else
                        if isVehicleFaded and fadedVehicle == vehicle then
                            isVehicleFaded = false
                            fadedVehicle = nil
                            -- Remove ox_target zone when vehicle is out of range
                            if vehicleTargetZones[vehicle] then
                                exports.ox_target:removeLocalEntity(vehicle, vehicleTargetZones[vehicle])
                                vehicleTargetZones[vehicle] = nil
                            end
                            canStoreVehicle = false
                        end
                    end
                    
                    ::skip_vehicle::
                else
                    if isVehicleFaded and fadedVehicle == vehicle then
                        isVehicleFaded = false
                        fadedVehicle = nil
                        -- Remove ox_target zone when vehicle is out of range
                        if vehicleTargetZones[vehicle] then
                            exports.ox_target:removeZone(vehicleTargetZones[vehicle])
                            vehicleTargetZones[vehicle] = nil
                        end
                        canStoreVehicle = false
                    end
                end
            else
                if isVehicleFaded and fadedVehicle == vehicle then
                    isVehicleFaded = false
                    fadedVehicle = nil
                    -- Remove ox_target zone when vehicle is out of range
                    if vehicleTargetZones[vehicle] then
                        exports.ox_target:removeZone(vehicleTargetZones[vehicle])
                        vehicleTargetZones[vehicle] = nil
                    end
                    canStoreVehicle = false
                end
            end
        elseif isInVehicle then
            local currentVehicle = GetVehiclePedIsIn(ped, false)
            
            if currentVehicle > 0 and DoesEntityExist(currentVehicle) then
                local plate = QBCore.Functions.GetPlate(currentVehicle)
                if plate then
                    QBCore.Functions.TriggerCallback('dw-garages:server:CheckJobAccess', function(hasAccess)
                        if not hasAccess then
                            local isJobVehicle = false
                            local jobName = nil
                            
                            for k, v in pairs(Config.JobGarages) do
                                local model = GetEntityModel(currentVehicle)
                                local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
                                
                                if v.vehicles then
                                    for jobVehModel, _ in pairs(v.vehicles) do
                                        if string.lower(jobVehModel) == modelName then
                                            isJobVehicle = true
                                            jobName = v.job
                                            break
                                        end
                                    end
                                end
                                
                                if isJobVehicle then break end
                            end
                            
                            if isJobVehicle and jobName ~= PlayerData.job.name then
                                TaskLeaveVehicle(ped, currentVehicle, 0)
                                QBCore.Functions.Notify("You don't have access to this job vehicle", "error")
                            end
                        end
                    end, plate)
                end
                
                if isVehicleFaded and fadedVehicle == currentVehicle then
                    isVehicleFaded = false
                    fadedVehicle = nil
                    parkingPromptShown = false
                    canStoreVehicle = false
                end
            end
        end
        
        ::continue::
        Wait(sleep)
    end
end)

RegisterNetEvent('dw-garages:client:FreeJobParkingSpot', function(jobName, spotIndex)
    if occupiedParkingSpots[jobName] then
        occupiedParkingSpots[jobName][spotIndex] = nil
    end
end)


function CreateGarageAttendant(coords, heading, model)
    RequestModel(GetHashKey(model))
    while not HasModelLoaded(GetHashKey(model)) do
        Wait(1)
    end
    
    local ped = CreatePed(4, GetHashKey(model), coords.x, coords.y, coords.z - 1.0, heading, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CLIPBOARD", 0, true)
    
    return ped
end

CreateThread(function()
    while not isPlayerLoaded do
        Wait(500)
    end
    
    local attendantModels = {
        "s_m_m_security_01", "s_m_y_valet_01", "s_m_m_gentransport", 
        "s_m_m_autoshop_01", "s_m_m_autoshop_02"
    }
    
    local garageAttendants = {}
    
    for k, v in pairs(Config.Garages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "public"})
    end
    
    for k, v in pairs(Config.JobGarages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "job", jobName = v.job})
    end
    
    for k, v in pairs(Config.GangGarages) do
        local model = attendantModels[math.random(1, #attendantModels)]
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "gang", gangName = v.gang})
    end
    
    for k, v in pairs(Config.ImpoundLots) do
        local model = "s_m_y_cop_01"
        if k == "paleto" then model = "s_m_y_sheriff_01"
        elseif k == "sandy" then model = "s_m_y_ranger_01" end
        
        local ped = CreateGarageAttendant(v.coords, v.coords.w, model)
        table.insert(garageAttendants, {ped = ped, garageId = k, garageType = "impound"})
    end
    
    if Config.UseTarget then
        for _, data in pairs(garageAttendants) do
            if data.garageType == "public" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "dw-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5
                })
            elseif data.garageType == "job" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "dw-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Job Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5,
                    job = data.jobName
                })
            elseif data.garageType == "gang" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "dw-garages:client:OpenGarage",
                            icon = "fas fa-car",
                            label = "Open Gang Garage",
                            garageId = data.garageId,
                            garageType = data.garageType
                        }
                    },
                    distance = 2.5,
                    gang = data.gangName
                })
            elseif data.garageType == "impound" then
                exports['qb-target']:AddTargetEntity(data.ped, {
                    options = {
                        {
                            type = "client",
                            event = "dw-garages:client:OpenImpoundLot",
                            icon = "fas fa-car",
                            label = "Check Impound Lot",
                            impoundId = data.garageId
                        }
                    },
                    distance = 2.5
                })
            end
        end
    else
        -- Create ox_target zones for all garages
        for k, v in pairs(Config.Garages) do
            local garageKey = "public_" .. k
            garageTargetZones[garageKey] = exports.ox_target:addSphereZone({
                coords = vector3(v.coords.x, v.coords.y, v.coords.z),
                radius = 2.5,
                debug = false,
                options = {
                    {
                        name = 'open_garage_' .. k,
                        icon = 'fas fa-car',
                        label = 'Open Garage',
                        onSelect = function()
                            TriggerEvent("dw-garages:client:OpenGarage", {garageId = k, garageType = "public"})
                        end
                    }
                }
            })
        end
        
        -- Create ox_target zones for job garages
        for k, v in pairs(Config.JobGarages) do
            local garageKey = "job_" .. k
            garageTargetZones[garageKey] = exports.ox_target:addSphereZone({
                coords = vector3(v.coords.x, v.coords.y, v.coords.z),
                radius = 2.5,
                debug = false,
                options = {
                    {
                        name = 'open_job_garage_' .. k,
                        icon = 'fas fa-car',
                        label = 'Open Job Garage',
                        onSelect = function()
                            if PlayerData.job and PlayerData.job.name == v.job then
                                TriggerEvent("dw-garages:client:OpenGarage", {garageId = k, garageType = "job"})
                            end
                        end
                    }
                }
            })
        end
        
        -- Create ox_target zones for gang garages
        for k, v in pairs(Config.GangGarages) do
            local garageKey = "gang_" .. k
            garageTargetZones[garageKey] = exports.ox_target:addSphereZone({
                coords = vector3(v.coords.x, v.coords.y, v.coords.z),
                radius = 2.5,
                debug = false,
                options = {
                    {
                        name = 'open_gang_garage_' .. k,
                        icon = 'fas fa-car',
                        label = 'Open Gang Garage',
                        onSelect = function()
                            if PlayerData.gang and PlayerData.gang.name == v.gang then
                                TriggerEvent("dw-garages:client:OpenGarage", {garageId = k, garageType = "gang"})
                            end
                        end
                    }
                }
            })
        end
        
        -- Create ox_target zones for impound lots
        for k, v in pairs(Config.ImpoundLots) do
            local garageKey = "impound_" .. k
            garageTargetZones[garageKey] = exports.ox_target:addSphereZone({
                coords = vector3(v.coords.x, v.coords.y, v.coords.z),
                radius = 2.5,
                debug = false,
                options = {
                    {
                        name = 'open_impound_' .. k,
                        icon = 'fas fa-car',
                        label = 'Check Impound Lot',
                        onSelect = function()
                            TriggerEvent("dw-garages:client:OpenImpoundLot", {impoundId = k})
                        end
                    }
                }
            })
        end
    end
end)


function OpenGarageUI(vehicles, garageInfo, garageType)
    
    table.sort(vehicles, function(a, b)
        if a.is_favorite and not b.is_favorite then
            return true
        elseif not a.is_favorite and b.is_favorite then
            return false
        else
            return a.vehicle < b.vehicle 
        end
    end)
    
    local vehicleData = FormatVehiclesForNUI(vehicles)
    
    local hasGang = false
    if PlayerData.gang and PlayerData.gang.name and PlayerData.gang.name ~= "none" then
        hasGang = true
    end
    
    local hasJobAccess = false
    
    local isInJobGarage = false
    if garageType == "job" then
        if garageInfo.job == PlayerData.job.name then
            isInJobGarage = true
            hasJobAccess = true
        end
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetAllGarages', function(allGarages)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openGarage",
            vehicles = vehicleData,
            garage = {
                name = garageInfo.label,
                type = garageType,
                location = garageInfo.label,
                hasGang = hasGang,
                hasJobAccess = isInJobGarage, 
                hasSharedAccess = Config.EnableSharedGarages, 
                showJobVehiclesTab = true, 
                gangName = PlayerData.gang and PlayerData.gang.name or nil,
                jobName = PlayerData.job and PlayerData.job.name or nil,
                isJobGarage = garageType == "job",
                isSharedGarage = garageType == "shared",
                isImpound = garageType == "impound",
                id = garageInfo.id
            },
            allGarages = allGarages,
            transferCost = Config.TransferCost or 500
        })
    end)
    
end

RegisterNetEvent('dw-garages:client:OpenGarage', function(data)
    -- Reset any stuck transfer states before opening
    if isTransferringVehicle then
        isTransferringVehicle = false
        transferAnimationActive = false
        currentTransferVehicle = nil
    end
    
    if isMenuOpen then return end
    isMenuOpen = true
   
    local garageId = data.garageId
    local garageType = data.garageType
    local garageInfo = {}   
    currentGarage = {id = garageId, type = garageType}
   
    if garageType == "public" then
        garageInfo = Config.Garages[garageId]
    elseif garageType == "job" then
        garageInfo = Config.JobGarages[garageId]
    elseif garageType == "gang" then
        garageInfo = Config.GangGarages[garageId]
    elseif garageType == "shared" then
        garageInfo = data.garageInfo
    elseif garageType == "house" then
        garageInfo = data.garageInfo
    elseif garageType == "impound" then
        garageInfo = Config.ImpoundLots[garageId]
    end

    local isImpoundLot = (garageType == "impound")

    if garageType == "public" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end)
    elseif garageType == "job" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetJobGarageVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageId)
    elseif garageType == "gang" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetGangVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageInfo.gang, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarageVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageId)
    elseif garageType == "house" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetHouseGarageVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end, garageId)
    elseif garageType == "impound" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetImpoundedVehicles', function(vehicles)
            OpenGarageUI(vehicles or {}, garageInfo, garageType, isImpoundLot)
        end)
    end
end)

-- Event for ps-housing to register house garage (for parking detection, doesn't open menu)
RegisterNetEvent('dw-garages:client:RegisterHouseGarage', function(propertyId, garageData)
    if not propertyId or not garageData then return end
    
    -- Store house garage data for parking detection
    local coords = garageData.coords or garageData.spawnPoint or garageData.takeVehicle
    if coords then
        houseGaragesData[propertyId] = {
            coords = vector3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0),
            label = garageData.label or ("House " .. propertyId .. " Garage"),
            spawnPoint = garageData.spawnPoint or garageData.takeVehicle or {
                x = coords.x or coords[1] or 0.0,
                y = coords.y or coords[2] or 0.0,
                z = coords.z or coords[3] or 0.0,
                w = coords.w or coords[4] or coords.h or 0.0
            },
            propertyId = propertyId
        }
    end
end)

-- Event for ps-housing to open house garage (when E is pressed)
RegisterNetEvent('dw-garages:client:OpenHouseGarage', function(propertyId, garageData)
    if not propertyId or not garageData then return end
    
    -- Store house garage data for parking detection (if not already stored)
    local coords = garageData.coords or garageData.spawnPoint or garageData.takeVehicle
    if coords then
        houseGaragesData[propertyId] = {
            coords = vector3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0),
            label = garageData.label or ("House " .. propertyId .. " Garage"),
            spawnPoint = garageData.spawnPoint or garageData.takeVehicle or {
                x = coords.x or coords[1] or 0.0,
                y = coords.y or coords[2] or 0.0,
                z = coords.z or coords[3] or 0.0,
                w = coords.w or coords[4] or coords.h or 0.0
            },
            propertyId = propertyId
        }
    end
    
    -- Create garage info structure
    local garageInfo = {
        label = garageData.label or ("House " .. propertyId .. " Garage"),
        coords = garageData.coords or {x = 0.0, y = 0.0, z = 0.0},
        spawnPoint = garageData.spawnPoint or garageData.takeVehicle or {
            x = garageData.coords and garageData.coords.x or 0.0,
            y = garageData.coords and garageData.coords.y or 0.0,
            z = garageData.coords and garageData.coords.z or 0.0,
            w = garageData.coords and garageData.coords.w or garageData.coords and garageData.coords.h or 0.0
        },
        spawnPoints = garageData.spawnPoints or nil
    }
    
    -- If spawnPoints is not provided, create a single spawn point from spawnPoint
    if not garageInfo.spawnPoints then
        garageInfo.spawnPoints = {garageInfo.spawnPoint}
    end
    
    -- Trigger the OpenGarage event with house type
    TriggerEvent('dw-garages:client:OpenGarage', {
        garageId = propertyId,
        garageType = "house",
        garageInfo = garageInfo
    })
end)

-- Event to remove house garage data when leaving zone
RegisterNetEvent('dw-garages:client:RemoveHouseGarage', function(propertyId)
    if propertyId then
        houseGaragesData[propertyId] = nil
    end
end)


function DebugJobGarage(garageId)
    local jobGarageInfo = Config.JobGarages[garageId]
    if not jobGarageInfo then
      Wait (100)
        return
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
        
        local count = 0
        for i, vehicle in ipairs(vehicles) do
            if vehicle.garage == garageId then
                count = count + 1
            end
        end
        
        if count == 0 then
            Wait (100)
        end
    end)
end

function OpenJobGarageUI(garageInfo, isImpoundLot)
    local jobVehicles = {}
    local i = 1
    
    for k, v in pairs(garageInfo.vehicles) do
        
        table.insert(jobVehicles, {
            id = i,
            model = v.model,
            name = v.label,
            fuel = 100,
            engine = 100,
            body = 100,
            state = 1,
            stored = true,
            isFavorite = false,
            isJobVehicle = true,
            icon = v.icon or "🚗"
        })
        i = i + 1
    end
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openGarage",
        vehicles = jobVehicles,
        garage = {
            name = garageInfo.label,
            type = "job",
            location = garageInfo.label,
            isJobGarage = true,
            jobName = PlayerData.job and PlayerData.job.name or nil,
            hasJobAccess = true, 
            isImpound = isImpoundLot 
        }
    })
end

RegisterNetEvent('dw-garages:client:CloseGarage')
AddEventHandler('dw-garages:client:CloseGarage', function()
    SetNuiFocus(false, false)
    isMenuOpen = false
    
    -- Reset transfer states
    isTransferringVehicle = false
    transferAnimationActive = false
    currentTransferVehicle = nil
    
    -- Send message to NUI to close all modals
    SendNUIMessage({
        action = "closeAllModals"
    })
end)

RegisterNUICallback('closeGarage', function(data, cb)
    SetNuiFocus(false, false)
    isMenuOpen = false
    
    -- Reset transfer states
    isTransferringVehicle = false
    transferAnimationActive = false
    currentTransferVehicle = nil
    
    -- Clear any pending animations or timers
    if currentTransferVehicle then
        currentTransferVehicle = nil
    end
    
    cb({status = "success"})
end)

-- Fix for takeOutVehicle NUI callback
RegisterNUICallback('takeOutVehicle', function(data, cb)
    local plate = data.plate
    local model = data.model
    
    SetNuiFocus(false, false)
    isMenuOpen = false
    
    if data.state == 0 then
        QBCore.Functions.Notify("This vehicle is already out of the garage.", "error")
        cb({status = "error", message = "Vehicle already out"})
        return
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleByPlate', function(vehData, isOut)
        if isOut then
            QBCore.Functions.Notify("This vehicle is already outside.", "error")
            cb({status = "error", message = "Vehicle already out"})
            return
        end
        
        local garageInfo = {}
        if currentGarage.type == "public" then
            garageInfo = Config.Garages[currentGarage.id]
        elseif currentGarage.type == "job" then
            garageInfo = Config.JobGarages[currentGarage.id]
        elseif currentGarage.type == "gang" then
            garageInfo = Config.GangGarages[currentGarage.id]
        elseif currentGarage.type == "shared" then
            garageInfo = sharedGaragesData[currentGarage.id]
        elseif currentGarage.type == "house" then
            garageInfo = houseGaragesData[currentGarage.id]
            if garageInfo then
                -- Convert to expected format
                garageInfo = {
                    coords = garageInfo.coords or {x = 0.0, y = 0.0, z = 0.0},
                    spawnPoint = garageInfo.spawnPoint or {x = 0.0, y = 0.0, z = 0.0, w = 0.0},
                    spawnPoints = garageInfo.spawnPoints or {garageInfo.spawnPoint or {x = 0.0, y = 0.0, z = 0.0, w = 0.0}}
                }
            end
        end
        
        local spawnPoints = nil
        if garageInfo.spawnPoints then
            spawnPoints = garageInfo.spawnPoints
        else
            spawnPoints = {garageInfo.spawnPoint}
        end
        
        local clearPoint = FindClearSpawnPoint(spawnPoints)
        if not clearPoint then
            QBCore.Functions.Notify("All spawn locations are blocked!", "error")
            cb({status = "error", message = "Spawn locations blocked"})
            return
        end
        
        if currentGarage.type == "shared" then
            QBCore.Functions.TriggerCallback('dw-garages:server:CheckSharedAccess', function(hasAccess)
                if hasAccess then
                    TriggerServerEvent('dw-garages:server:TakeOutSharedVehicle', plate, currentGarage.id)
                    cb({status = "success"})
                else
                    QBCore.Functions.Notify("You don't have access to this vehicle", "error")
                    cb({status = "error", message = "No access"})
                end
            end, plate, currentGarage.id)
            return
        end
        
        local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
        
        if currentGarage.type == "public" or currentGarage.type == "gang" or currentGarage.type == "house" then
            QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleProperties', function(properties)
                if properties then
                    QBCore.Functions.SpawnVehicle(model, function(veh)
                        if not veh or veh == 0 then
                            QBCore.Functions.Notify("Failed to spawn vehicle", "error")
                            cb({status = "error", message = "Failed to spawn"})
                            return
                        end
                        
                        -- Make vehicle persist when player disconnects
                        SetEntityAsMissionEntity(veh, true, true)
                        SetEntityCanBeDamaged(veh, true)
                        SetEntityInvincible(veh, false)
                        if NetworkGetEntityIsNetworked(veh) then
                            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                        end
                        
                        SetEntityHeading(veh, clearPoint.w)
                        SetVehicleFuelLevel(veh, data.fuel)
                        SetVehicleNumberPlateText(veh, plate)
                        FadeInVehicle(veh)
                        
                        -- Apply vehicle properties including livery
                        QBCore.Functions.SetVehicleProperties(veh, properties)
                        Wait(200) -- Wait to ensure properties are applied
                        
                        -- Explicitly apply livery if it exists in properties (check multiple possible property names)
                        if properties.modLivery ~= nil then
                            SetVehicleLivery(veh, properties.modLivery)
                            Wait(50)
                            SetVehicleLivery(veh, properties.modLivery) -- Apply twice to ensure it sticks
                        elseif properties.livery ~= nil then
                            SetVehicleLivery(veh, properties.livery)
                            Wait(50)
                            SetVehicleLivery(veh, properties.livery) -- Apply twice to ensure it sticks
                        end
                        
                        local engineHealth = properties.engineHealth or 1000.0
                        local bodyHealth = properties.bodyHealth or 1000.0
                        
                       SetVehicleEngineHealth(veh, engineHealth + 0.0)
                       SetVehicleBodyHealth(veh, bodyHealth + 0.0)
                       SetVehicleDirtLevel(veh, 0.0)
                        
                        FixEngineSmoke(veh)
                        
                        SetVehicleUndriveable(veh, false)
                        SetVehicleEngineOn(veh, false, true, false)
                        
                        -- Lock vehicle doors (after all properties are set)
                        Wait(100) -- Additional wait to ensure everything is set
                        ApplyGarageLock(veh)
                        
                        TriggerServerEvent('dw-garages:server:UpdateVehicleState', plate, 0)
                        
                        if currentGarage.type == "gang" and data.storedInGang then
                            TriggerServerEvent('dw-garages:server:UpdateGangVehicleState', plate, 0)
                        end

                        TriggerEvent("vehiclekeys:client:SetOwner", plate)
                        
                        -- Keep vehicle in world - don't let framework delete on disconnect
                        if NetworkGetEntityIsNetworked(veh) then
                            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                        end
                        
                        QBCore.Functions.Notify("Vehicle taken out", "success")
                        cb({status = "success"})
                    end, spawnCoords, true)
                else
                    cb({status = "error", message = "Failed to load properties"})
                end
            end, plate)
        else 
            QBCore.Functions.SpawnVehicle(model, function(veh)
                if not veh or veh == 0 then
                    QBCore.Functions.Notify("Failed to spawn vehicle", "error")
                    cb({status = "error", message = "Failed to spawn"})
                    return
                end
                
                -- Make vehicle persist when player disconnects
                SetEntityAsMissionEntity(veh, true, true)
                SetEntityCanBeDamaged(veh, true)
                SetEntityInvincible(veh, false)
                if NetworkGetEntityIsNetworked(veh) then
                    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                end
                
                SetEntityHeading(veh, clearPoint.w)
                SetVehicleFuelLevel(veh, data.fuel)
                SetVehicleNumberPlateText(veh, plate)
                FadeInVehicle(veh)
                
                -- Try to get properties for job vehicles that might have livery
                QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleProperties', function(properties)
                    if properties then
                        -- Apply vehicle properties including livery
                        QBCore.Functions.SetVehicleProperties(veh, properties)
                        Wait(200) -- Wait to ensure properties are applied
                        
                        -- Explicitly apply livery if it exists in properties (check multiple possible property names)
                        if properties.modLivery ~= nil then
                            SetVehicleLivery(veh, properties.modLivery)
                            Wait(50)
                            SetVehicleLivery(veh, properties.modLivery) -- Apply twice to ensure it sticks
                        elseif properties.livery ~= nil then
                            SetVehicleLivery(veh, properties.livery)
                            Wait(50)
                            SetVehicleLivery(veh, properties.livery) -- Apply twice to ensure it sticks
                        end
                    end
                    
                    -- Lock vehicle doors (after properties are applied)
                    Wait(100) -- Additional wait to ensure everything is set
                    ApplyGarageLock(veh)
                    
                    SetVehicleEngineHealth(veh, 1000.0)
                    SetVehicleBodyHealth(veh, 1000.0)
                    SetVehicleDirtLevel(veh, 0.0)
                    SetVehicleUndriveable(veh, false)
                    SetVehicleEngineOn(veh, false, true, false)
                    
        FixEngineSmoke(veh)
        
        -- Update vehicle state for LostVehicleTimeout tracking
        local plate = QBCore.Functions.GetPlate(veh)
        if plate then
            TriggerServerEvent('dw-garages:server:UpdateVehicleState', plate, 0)
                        
                        -- Give keys to player for owned vehicles in job garages
                        TriggerEvent("vehiclekeys:client:SetOwner", plate)
        end
        
                    QBCore.Functions.Notify("Vehicle taken out", "success")
        cb({status = "success"})
                end, plate)
            end, spawnCoords, true)
        end
    end, plate)
end)

RegisterNetEvent('dw-garages:client:TakeOutSharedVehicle', function(plate, vehicleData)
    local garageId = currentGarage.id
    local garageType = currentGarage.type
    
    if not garageId or not garageType then
        QBCore.Functions.Notify("Garage information is missing", "error")
        return
    end
    
    if not sharedGaragesData[garageId] then
        QBCore.Functions.Notify("Shared garage data not found", "error")
        return
    end
    
    if not plate or not vehicleData then
        QBCore.Functions.Notify("Vehicle data is incomplete", "error")
        return
    end
    
    local garageInfo = sharedGaragesData[garageId]
    
    local spawnPoints = nil
    if garageInfo.spawnPoints then
        spawnPoints = garageInfo.spawnPoints
    else
        spawnPoints = {garageInfo.spawnPoint}
    end
    
    local clearPoint = FindClearSpawnPoint(spawnPoints)
    if not clearPoint then
        QBCore.Functions.Notify("All spawn locations are blocked!", "error")
        return
    end
    
    local spawnCoords = vector3(clearPoint.x, clearPoint.y, clearPoint.z)
    
    QBCore.Functions.SpawnVehicle(vehicleData.vehicle, function(veh)
        if not veh or veh == 0 then
            QBCore.Functions.Notify("Error creating shared vehicle. Please try again.", "error")
            return
        end
        
        -- Make vehicle persist when player disconnects
        SetEntityAsMissionEntity(veh, true, true)
        SetEntityCanBeDamaged(veh, true)
        SetEntityInvincible(veh, false)
        if NetworkGetEntityIsNetworked(veh) then
            SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
        end
        
        SetEntityHeading(veh, clearPoint.w)
        SetVehicleFuelLevel(veh, vehicleData.fuel)
        SetVehicleNumberPlateText(veh, plate)
        FadeInVehicle(veh)
        
        QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleProperties', function(properties)
            if properties then
                -- Apply vehicle properties including livery
                QBCore.Functions.SetVehicleProperties(veh, properties)
                Wait(200) -- Wait to ensure properties are applied
                
                -- Explicitly apply livery if it exists in properties (check multiple possible property names)
                if properties.modLivery ~= nil then
                    SetVehicleLivery(veh, properties.modLivery)
                    Wait(50)
                    SetVehicleLivery(veh, properties.modLivery) -- Apply twice to ensure it sticks
                elseif properties.livery ~= nil then
                    SetVehicleLivery(veh, properties.livery)
                    Wait(50)
                    SetVehicleLivery(veh, properties.livery) -- Apply twice to ensure it sticks
                end
                
                local engineHealth = math.max(vehicleData.engine, 900.0)
                local bodyHealth = math.max(vehicleData.body, 900.0)
                
                SetVehicleEngineHealth(veh, engineHealth)
                SetVehicleBodyHealth(veh, bodyHealth)
                SetVehicleDirtLevel(veh, 0.0) 
                
                FixEngineSmoke(veh)
                
                SetVehicleUndriveable(veh, false)
                SetVehicleEngineOn(veh, false, true, false)
                
                -- Update vehicle state for LostVehicleTimeout tracking
                if plate then
                    TriggerServerEvent('dw-garages:server:UpdateVehicleState', plate, 0)
                end
                
                -- Lock vehicle doors (after all properties are set)
                Wait(100) -- Additional wait to ensure everything is set
                ApplyGarageLock(veh)
                
                QBCore.Functions.Notify("Vehicle taken out from shared garage", "success")
            else
                QBCore.Functions.Notify("Failed to load vehicle properties", "error")
            end
        end, plate)
    end, spawnCoords, true)
end)

function PlayVehicleTransferAnimation(plate, fromGarageId, toGarageId)
    local garageInfo = nil
    if currentGarage.type == "public" then
        garageInfo = Config.Garages[fromGarageId]
    elseif currentGarage.type == "job" then
        garageInfo = Config.JobGarages[fromGarageId]
    elseif currentGarage.type == "gang" then
        garageInfo = Config.GangGarages[fromGarageId]
    end
    
    if not garageInfo then 
        TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return 
    end
    
    local garageCoords = vector3(garageInfo.coords.x, garageInfo.coords.y, garageInfo.coords.z)
    
    if not garageInfo.transferSpawn or not garageInfo.transferArrival then
        TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return
    end
    
    local spawnPos = garageInfo.transferSpawn
    local arrivalPos = garageInfo.transferArrival
    local exitPos = garageInfo.transferExit or nil
    
    local truckModel = "flatbed"
    local driverModel = "s_m_m_trucker_01"
    
    RequestModel(GetHashKey(truckModel))
    RequestModel(GetHashKey(driverModel))
    
    local timeout = 0
    while (not HasModelLoaded(GetHashKey(truckModel)) or not HasModelLoaded(GetHashKey(driverModel))) and timeout < 50 do
        Wait(100)
        timeout = timeout + 1
    end
    
    if timeout >= 50 then
        TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
        QBCore.Functions.Notify("Vehicle transferred", "success")
        return
    end
    
    QBCore.Functions.Notify("Vehicle transfer service is on the way...", "primary", 4000)
    
    QBCore.Functions.SpawnVehicle(truckModel, function(truck)
        if not DoesEntityExist(truck) then
            TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
            QBCore.Functions.Notify("Vehicle transferred", "success")
            return
        end
        
        SetEntityAsMissionEntity(truck, true, true)
        SetEntityHeading(truck, spawnPos.w)
        SetVehicleEngineOn(truck, false, true, false)
        
        local driver = CreatePedInsideVehicle(truck, 26, GetHashKey(driverModel), -1, true, false)
        
        if not DoesEntityExist(driver) then
            DeleteEntity(truck)
            TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
            QBCore.Functions.Notify("Vehicle transferred", "success")
            return
        end
        
        SetEntityAsMissionEntity(driver, true, true)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetDriverAbility(driver, 1.0)
        SetDriverAggressiveness(driver, 0.0)
        
        local blip = AddBlipForEntity(truck)
        SetBlipSprite(blip, 67)
        SetBlipColour(blip, 5)
        SetBlipDisplay(blip, 2)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Transfer Truck")
        EndTextCommandSetBlipName(blip)
        
        local vehicleFlags = 447 
        local speed = 10.0    
        
        TaskVehicleDriveToCoord(driver, truck, 
            arrivalPos.x, arrivalPos.y, arrivalPos.z, 
            speed, 0, GetHashKey(truckModel), 
            vehicleFlags, 
            10.0, 
            true 
        )
        
        local startTime = GetGameTimer()
        local maxDriveTime = 90000 
        local arrivalRange = 15.0  
        local lastPos = GetEntityCoords(truck)
        local stuckCounter = 0
        local arrived = false
        
        CreateThread(function()
        while not arrived do
            Wait(1000) 
            
            if not DoesEntityExist(truck) or not DoesEntityExist(driver) then
                break
            end
            
            local curPos = GetEntityCoords(truck)
            local distToDestination = #(curPos - vector3(arrivalPos.x, arrivalPos.y, arrivalPos.z))
            
            if distToDestination < arrivalRange then
                local curSpeed = GetEntitySpeed(truck) * 3.6 
                
                if curSpeed < 1.0 or distToDestination < 5.0 then
                    TaskVehicleTempAction(driver, truck, 27, 10000)
                    arrived = true
                    break
                end
            end
            
            local distMoved = #(curPos - lastPos)
            local vehicleSpeed = GetEntitySpeed(truck)
            
            if distMoved < 0.3 and vehicleSpeed < 0.5 then
                stuckCounter = stuckCounter + 1
                
                if stuckCounter >= 10 then
                    arrived = true
                    break
                end
                if stuckCounter % 3 == 0 then 
                    ClearPedTasks(driver)
                    Wait(500)
                    TaskVehicleDriveToCoord(driver, truck, 
                        arrivalPos.x, arrivalPos.y, arrivalPos.z, 
                        speed, 0, GetHashKey(truckModel), 
                        vehicleFlags, 
                        arrivalRange, true
                    )
                end
            else
                stuckCounter = 0
            end
            
            if GetGameTimer() - startTime > maxDriveTime then
                arrived = true
                break
            end
            
            lastPos = curPos
        end
        
        if DoesEntityExist(truck) and DoesEntityExist(driver) then
            ClearPedTasks(driver)
            TaskVehicleTempAction(driver, truck, 27, 10000) 
            SetVehicleIndicatorLights(truck, 0, true)
            SetVehicleIndicatorLights(truck, 1, true)
            QBCore.Functions.Notify("Loading your vehicle onto the transfer truck...", "primary", 4000)
            PlaySoundFromEntity(-1, "VEHICLES_TRAILER_ATTACH", truck, 0, 0, 0)
            Wait(5000)
            TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, toGarageId, Config.TransferCost or 500)
            QBCore.Functions.Notify("Vehicle transferred successfully!", "success")
            SetVehicleIndicatorLights(truck, 0, false)
            SetVehicleIndicatorLights(truck, 1, false)
            local driveToExit = false
            local exitX, exitY, exitZ, exitHeading
            if exitPos then
                driveToExit = true
                exitX = exitPos.x
                exitY = exitPos.y
                exitZ = exitPos.z
                exitHeading = exitPos.w
            else
                local curPos = GetEntityCoords(truck)
                local curHeading = GetEntityHeading(truck)
                local leaveHeading = (curHeading + 180.0) % 360.0
                local leaveDistance = 100.0
                local success, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(
                    curPos.x + math.sin(math.rad(leaveHeading)) * 20.0,
                    curPos.y + math.cos(math.rad(leaveHeading)) * 20.0,
                    curPos.z,
                    0, 3.0, 0
                )
                
                if success then
                    driveToExit = true
                    exitX = nodePos.x
                    exitY = nodePos.y
                    exitZ = nodePos.z
                    exitHeading = nodeHeading
                else
                    driveToExit = true
                    exitX = curPos.x + math.sin(math.rad(leaveHeading)) * leaveDistance
                    exitY = curPos.y + math.cos(math.rad(leaveHeading)) * leaveDistance
                    exitZ = curPos.z
                    exitHeading = leaveHeading
                end
            end
            
            if driveToExit then
                TaskVehicleDriveToCoord(driver, truck, exitX, exitY, exitZ, speed, 0, GetHashKey(truckModel), vehicleFlags, 2.0, true)
                
                Wait(5000)
                    
                    Wait(50) 
            end
            
            RemoveBlip(blip)
            DeleteEntity(driver)
            DeleteEntity(truck)
        end
    end)
    end, vector3(spawnPos.x, spawnPos.y, spawnPos.z), true)
end

function normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length > 0 then
        return vector3(vec.x / length, vec.y / length, vec.z / length)
    else
        return vector3(0, 0, 0)
    end
end

function normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length > 0 then
        return vector3(vec.x / length, vec.y / length, vec.z / length)
    else
        return vector3(0, 0, 0)
    end
end

RegisterNUICallback('directTransferVehicle', function(data, cb)
    local plate = data.plate
    local newGarageId = data.newGarageId
    local cost = data.cost or Config.TransferCost or 500
    
    cb({status = "success"})
    
    -- Reset transfer states before starting new transfer
    isTransferringVehicle = false
    transferAnimationActive = false
    currentTransferVehicle = nil
    
    if Config.EnableTransferAnimation then
        local fromGarageId = currentGarage.id
        PlayVehicleTransferAnimation(plate, fromGarageId, newGarageId)
    else
        TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, newGarageId, cost)
    end
    
    -- Fallback timeout to ensure modal closes if transfer fails silently
    Citizen.SetTimeout(15000, function()
        -- Force close modal if still open
        SendNUIMessage({
            action = "closeTransferModal"
        })
        -- Reset states
        isTransferringVehicle = false
        transferAnimationActive = false
        currentTransferVehicle = nil
    end)
    
    Citizen.SetTimeout(1000, function()
        TriggerEvent('dw-garages:client:RefreshVehicleList')
    end)
end)

RegisterNUICallback('transferVehicle', function(data, cb)
    local plate = data.plate
    local newGarageId = data.newGarageId
    local cost = data.cost or Config.TransferCost or 500
    
    
    if not plate or not newGarageId then
        cb({status = "error", message = "Invalid data"})
        -- Close modal on error
        SendNUIMessage({
            action = "closeTransferModal"
        })
        return
    end
    
    if isTransferringVehicle then
        cb({status = "error", message = "Transfer already in progress"})
        return
    end
    
    isTransferringVehicle = true
    currentTransferVehicle = {plate = plate, garage = newGarageId}
    
    -- Don't close NUI focus, keep menu open during transfer
    TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, newGarageId, cost)
    
    -- Fallback timeout to reset state and close modal if server doesn't respond
    Citizen.SetTimeout(15000, function()
        if isTransferringVehicle then
            isTransferringVehicle = false
            transferAnimationActive = false
            currentTransferVehicle = nil
            -- Force close modal if stuck
            SendNUIMessage({
                action = "closeTransferModal"
            })
            -- Restore NUI focus if menu is still open
            if currentGarage and isMenuOpen then
                SetNuiFocus(true, true)
            end
        end
    end)
    cb({status = "success"})
end)

RegisterNetEvent("dw-garages:client:PlayTransferAnimation", function(plate, newGarageId)
    local ped = PlayerPedId()
    local garageType = currentGarage.type
    local currentGarageId = currentGarage.id
    
    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        TaskLeaveVehicle(ped, vehicle, 0)
        Wait(1500)
    end
    
    transferAnimationActive = true
    
    local currentGarageInfo = nil
    local newGarageInfo = nil
    
    if garageType == "public" then
        currentGarageInfo = Config.Garages[currentGarageId]
    elseif garageType == "job" then
        currentGarageInfo = Config.JobGarages[currentGarageId]
    elseif garageType == "gang" then
        currentGarageInfo = Config.GangGarages[currentGarageId]
    end
    
    local newGarageInfoFound = false
    for k, v in pairs(Config.Garages) do
        if k == newGarageId then
            newGarageInfo = v
            newGarageInfoFound = true
            break
        end
    end
    
    if not newGarageInfoFound and PlayerData.job then
        for k, v in pairs(Config.JobGarages) do
            if k == newGarageId and v.job == PlayerData.job.name then
                newGarageInfo = v
                newGarageInfoFound = true
                break
            end
        end
    end
    
    if not newGarageInfoFound and PlayerData.gang and PlayerData.gang.name ~= "none" then
        for k, v in pairs(Config.GangGarages) do
            if k == newGarageId and v.gang == PlayerData.gang.name then
                newGarageInfo = v
                newGarageInfoFound = true
                break
            end
        end
    end
    
    if not newGarageInfoFound then
        QBCore.Functions.Notify("Target garage not found", "error")
        isTransferringVehicle = false
        transferAnimationActive = false
        currentTransferVehicle = nil
        return
    end
    local animDict = "cellphone@"
    local animName = "cellphone_text_read_base"
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end
    TaskPlayAnim(ped, animDict, animName, 2.0, 2.0, -1, 51, 0, false, false, false)
    QBCore.Functions.Notify("Arranging vehicle transfer...", "primary", 3000)
    Wait(3000)
    animDict = "missheistdockssetup1clipboard@base"
    animName = "base"
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(100)
    end
    TaskPlayAnim(ped, animDict, animName, 2.0, 2.0, -1, 51, 0, false, false, false)
    QBCore.Functions.Notify("Signing transfer papers...", "primary", 3000)
    Wait(3000)
    ClearPedTasks(ped)
    TriggerServerEvent('dw-garages:server:TransferVehicleToGarage', plate, newGarageId, Config.TransferCost or 500)
    transferAnimationActive = false
    Wait(1000)
    isTransferringVehicle = false
    currentTransferVehicle = nil
end)

RegisterNetEvent('dw-garages:client:TransferComplete', function(newGarageId, plate)
    QBCore.Functions.Notify("Vehicle transferred to " .. newGarageId .. " garage", "success")
    
    -- Reset transfer states immediately
    isTransferringVehicle = false
    transferAnimationActive = false
    currentTransferVehicle = nil
    
    -- Close transfer modal if open (send multiple times to ensure it closes)
    SendNUIMessage({
        action = "closeTransferModal"
    })
    
    -- Send again after a small delay to ensure it closes
    Citizen.SetTimeout(100, function()
        SendNUIMessage({
            action = "closeTransferModal"
        })
    end)
    
    -- Send one more time after a longer delay as final safety check
    Citizen.SetTimeout(500, function()
        SendNUIMessage({
            action = "closeTransferModal"
        })
    end)
    
    -- Ensure NUI focus is restored if menu is still open
    if currentGarage and isMenuOpen then
        SetNuiFocus(true, true)
        local garageId = currentGarage.id
        QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    end
end)

RegisterNUICallback('updateVehicleName', function(data, cb)
    local plate = data.plate
    local newName = data.name
    
    if plate and newName then
        TriggerServerEvent('dw-garages:server:UpdateVehicleName', plate, newName)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)

RegisterNUICallback('toggleFavorite', function(data, cb)
    local plate = data.plate
    local isFavorite = data.isFavorite
    
    if plate then
        TriggerServerEvent('dw-garages:server:ToggleFavorite', plate, isFavorite)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid plate"})
    end
end)

RegisterNUICallback('storeInGang', function(data, cb)
    local plate = data.plate
    local gangName = PlayerData.gang.name
    
    if plate and gangName then
        TriggerServerEvent('dw-garages:server:StoreVehicleInGang', plate, gangName)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)


RegisterNUICallback('storeInShared', function(data, cb)
    local plate = data.plate
    
    if plate then
        OpenSharedGarageSelectionUI(plate)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid data"})
    end
end)

RegisterNUICallback('removeFromShared', function(data, cb)
    local plate = data.plate
    
    if plate then
        TriggerServerEvent('dw-garages:server:RemoveVehicleFromSharedGarage', plate)
        cb({status = "success"})
    else
        cb({status = "error", message = "Invalid plate"})
    end
end)

function OpenSharedGarageSelectionUI(plate)
    QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarages', function(garages)
        if #garages == 0 then
            QBCore.Functions.Notify("You don't have access to any shared garages", "error")
            return
        end
        
        local formattedGarages = {}
        for _, garage in ipairs(garages) do
            table.insert(formattedGarages, {
                id = garage.id,
                name = garage.name,
                owner = garage.isOwner
            })
        end
        
        SendNUIMessage({
            action = "openSharedGarageSelection",
            garages = formattedGarages,
            plate = plate
        })
    end)
end

RegisterNUICallback('storeInSelectedSharedGarage', function(data, cb)
    local plate = data.plate
    local garageId = data.garageId
    
    if not plate or not garageId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    TriggerServerEvent('dw-garages:server:TransferVehicleToSharedGarage', plate, garageId)
    
    cb({status = "success"})
end)

function IsSpawnPointClear(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    for i = 1, #vehicles do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        if #(vehicleCoords - coords) <= radius then
            return false
        end
    end
    return true
end

RegisterNetEvent('dw-garages:client:StoreVehicle', function(data)
    local ped = PlayerPedId()
    local garageId = nil
    local garageType = nil
    local garageInfo = nil
    
    if data and data.garageId and data.garageType then
        garageId = data.garageId
        garageType = data.garageType
    elseif currentGarage and currentGarage.id and currentGarage.type then
        garageId = currentGarage.id
        garageType = currentGarage.type
    else
        local pos = GetEntityCoords(PlayerPedId())
        local closestDist = 999999
        local closestGarage = nil
        local closestType = nil
        
        
        for k, v in pairs(Config.Garages) do
            local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
            if dist < closestDist and dist < 10.0 then
                closestDist = dist
                closestGarage = k
                closestType = "public"
            end
        end
        
        if PlayerData.job then
            for k, v in pairs(Config.JobGarages) do
                if PlayerData.job.name == v.job then
                    local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
                    if dist < closestDist and dist < 10.0 then
                        closestDist = dist
                        closestGarage = k
                        closestType = "job"
                    end
                end
            end
        end
        
        if PlayerData.gang and PlayerData.gang.name ~= "none" then
            for k, v in pairs(Config.GangGarages) do
                if PlayerData.gang.name == v.gang then
                    local dist = #(pos - vector3(v.coords.x, v.coords.y, v.coords.z))
                    if dist < closestDist and dist < 10.0 then
                        closestDist = dist
                        closestGarage = k
                        closestType = "gang"
                    end
                end
            end
        end
        
        -- Check house garages
        for propertyId, garageData in pairs(houseGaragesData) do
            if garageData.coords then
                local dist = #(pos - garageData.coords)
                if dist < closestDist and dist < 10.0 then
                    closestDist = dist
                    closestGarage = propertyId
                    closestType = "house"
                end
            end
        end
        
        garageId = closestGarage
        garageType = closestType
        
        if garageId then
            Wait (100)
        end
    end
    
    if not garageId or not garageType then
        QBCore.Functions.Notify("Not in a valid parking zone", "error")
        return
    end
    
    if garageType == "public" then
        garageInfo = Config.Garages[garageId]
    elseif garageType == "job" then
        garageInfo = Config.JobGarages[garageId]
    elseif garageType == "gang" then
        garageInfo = Config.GangGarages[garageId]
    elseif garageType == "house" then
        garageInfo = houseGaragesData[garageId]
        if garageInfo then
            -- Convert to expected format
            garageInfo = {
                coords = garageInfo.coords or {x = 0.0, y = 0.0, z = 0.0},
                spawnPoint = garageInfo.spawnPoint or {x = 0.0, y = 0.0, z = 0.0, w = 0.0},
                spawnPoints = garageInfo.spawnPoints or {garageInfo.spawnPoint or {x = 0.0, y = 0.0, z = 0.0, w = 0.0}}
            }
        end
    end
    
    if not garageInfo then
        QBCore.Functions.Notify("Invalid garage", "error")
        return
    end
    
    local garageCoords = nil
    if garageInfo.coords then
        if type(garageInfo.coords) == "vector3" then
            garageCoords = garageInfo.coords
        else
            garageCoords = vector3(garageInfo.coords.x, garageInfo.coords.y, garageInfo.coords.z)
        end
    else
        -- Fallback for house garages
        if garageType == "house" and houseGaragesData[garageId] then
            garageCoords = houseGaragesData[garageId].coords
        else
            QBCore.Functions.Notify("Invalid garage coordinates", "error")
            return
        end
    end
    
    local curVeh = GetVehiclePedIsIn(ped, false)
    
    if curVeh == 0 then
        curVeh = GetClosestVehicleInGarage(garageCoords, 15.0)
        
        if curVeh == 0 or not DoesEntityExist(curVeh) then
            QBCore.Functions.Notify("No vehicle found nearby to park", "error")
            return
        end
        
        if GetVehicleNumberOfPassengers(curVeh) > 0 or not IsVehicleSeatFree(curVeh, -1) then
            QBCore.Functions.Notify("Vehicle cannot be stored while occupied", "error")
            return
        end
    end
    
    currentGarage = {id = garageId, type = garageType}
    
    local plate = QBCore.Functions.GetPlate(curVeh)
    local props = QBCore.Functions.GetVehicleProperties(curVeh)
    
    -- Explicitly capture and save livery to props
    if DoesEntityExist(curVeh) then
        local livery = GetVehicleLivery(curVeh)
        if livery ~= nil and livery >= 0 then
            props.modLivery = livery
        end
    end
    
    local fuel = GetVehicleFuelLevel(curVeh)
    local engineHealth = GetVehicleEngineHealth(curVeh)
    local bodyHealth = GetVehicleBodyHealth(curVeh)
    
    QBCore.Functions.TriggerCallback('dw-garages:server:CheckOwnership', function(isOwner, isInGarage)
        -- Allow storage if player owns the vehicle, or has access to shared garage, or has gang access
        if isOwner or isInGarage or (garageType == "gang" and isInGarage) then
            FadeOutVehicle(curVeh, function()
                TriggerServerEvent('dw-garages:server:StoreVehicle', plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
                QBCore.Functions.Notify("Vehicle stored in garage", "success")
                
                if isMenuOpen then
                    if garageType == "house" then
                        QBCore.Functions.TriggerCallback('dw-garages:server:GetHouseGarageVehicles', function(vehicles)
                            if vehicles then
                                SendNUIMessage({
                                    action = "refreshVehicles",
                                    vehicles = FormatVehiclesForNUI(vehicles)
                                })
                            end
                        end, garageId)
                    else
                        QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
                            if vehicles then
                                SendNUIMessage({
                                    action = "refreshVehicles",
                                    vehicles = FormatVehiclesForNUI(vehicles)
                                })
                            end
                        end, garageId)
                    end
                end
            end)
        else
            QBCore.Functions.Notify("You don't have permission to store this vehicle", "error")
        end
    end, plate, garageType)
end)

function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end


RegisterNetEvent('dw-garages:client:ManageSharedGarages')
AddEventHandler('dw-garages:client:ManageSharedGarages', function()
    
    if not Config.EnableSharedGarages then
        SendNUIMessage({
            action = "openSharedGarageManager",
            garages = {},
            error = "Shared garages feature is disabled"
        })
        SetNuiFocus(true, true)
        return
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:CheckSharedGaragesTables', function(tablesExist)
        if not tablesExist then
            TriggerServerEvent('dw-garages:server:CreateSharedGaragesTables')
            
            SendNUIMessage({
                action = "openSharedGarageManager",
                garages = {},
                error = "Initializing shared garages feature..."
            })
            SetNuiFocus(true, true)
            return
        end
        
        QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarages', function(garages)
            sharedGaragesData = {}
            
            local formattedGarages = {}
            
            for _, garage in ipairs(garages) do
                sharedGaragesData[garage.id] = {
                    id = garage.id,
                    name = garage.name,
                    label = garage.name,
                    isOwner = garage.isOwner,
                    accessCode = garage.access_code,
                    spawnPoint = Config.Garages["legion"].spawnPoint,
                    spawnPoints = Config.Garages["legion"].spawnPoints
                }
                
                table.insert(formattedGarages, {
                    id = garage.id,
                    name = garage.name,
                    isOwner = garage.isOwner,
                    accessCode = garage.access_code
                })
            end
            
            SendNUIMessage({
                action = "openSharedGarageManager",
                garages = formattedGarages
            })
            SetNuiFocus(true, true)
        end)
    end)
end)


RegisterNUICallback('manageSharedGarages', function(data, cb)
    TriggerEvent('dw-garages:client:ManageSharedGarages')
    cb({status = "success"})
end)

RegisterNUICallback('createSharedGarage', function(data, cb)
    local garageName = data.name
    
    if not garageName or garageName == "" then
        cb({status = "error", message = "Invalid garage name"})
        return
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:CreateSharedGarage', function(success, result)
        if success then
            QBCore.Functions.Notify("Shared garage created successfully. Code: " .. result.code, "success")
            cb({status = "success", garageData = result})
        else
            QBCore.Functions.Notify(result, "error")
            cb({status = "error", message = result})
        end
    end, garageName)
end)

RegisterNUICallback('joinSharedGarage', function(data, cb)
    local accessCode = data.code
    
    if not accessCode or accessCode == "" then
        cb({status = "error", message = "Invalid access code"})
        return
    end
    
    TriggerServerEvent('dw-garages:server:RequestJoinSharedGarage', accessCode)
    cb({status = "success"})
end)

RegisterNUICallback('openSharedGarage', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    local garageInfo = sharedGaragesData[garageId]
    if not garageInfo then
        cb({status = "error", message = "Garage data not found"})
        return
    end
    
    SetNuiFocus(false, false)
    
    TriggerEvent('dw-garages:client:OpenGarage', {
        garageId = garageId,
        garageType = "shared",
        garageInfo = garageInfo
    })
    
    cb({status = "success"})
end)

RegisterNUICallback('manageSharedGarageMembers', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarageMembers', function(members)
        if members then
            SendNUIMessage({
                action = "openSharedGarageMembersManager",
                members = members,
                garageId = garageId
            })
            cb({status = "success", members = members})
        else
            cb({status = "error", message = "Failed to fetch members"})
        end
    end, garageId)
end)

RegisterNUICallback('removeSharedGarageMember', function(data, cb)
    local memberId = data.memberId
    local garageId = data.garageId
    
    if not memberId or not garageId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    TriggerServerEvent('dw-garages:server:RemoveMemberFromSharedGarage', memberId, garageId)
    cb({status = "success"})
end)

RegisterNUICallback('deleteSharedGarage', function(data, cb)
    local garageId = data.garageId
    
    if not garageId then
        cb({status = "error", message = "Invalid garage ID"})
        return
    end
    
    TriggerServerEvent('dw-garages:server:DeleteSharedGarage', garageId)
    cb({status = "success"})
end)

RegisterNetEvent('dw-garages:client:ReceiveJoinRequest', function(data)
    table.insert(pendingJoinRequests, data)
    
    QBCore.Functions.Notify(data.requesterName .. " wants to join your " .. data.garageName .. " garage", "primary", 10000)
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openJoinRequest",
        request = data
    })
end)

RegisterNUICallback('handleJoinRequest', function(data, cb)
    local requestId = data.requestId
    local approved = data.approved
    
    if not requestId then
        cb({status = "error", message = "Invalid request ID"})
        return
    end
    
    local requestData = nil
    for i, request in ipairs(pendingJoinRequests) do
        if request.requesterId == requestId then
            requestData = request
            table.remove(pendingJoinRequests, i)
            break
        end
    end
    
    if not requestData then
        cb({status = "error", message = "Request not found"})
        return
    end
    
    if approved then
        TriggerServerEvent('dw-garages:server:ApproveJoinRequest', requestData)
    else
        TriggerServerEvent('dw-garages:server:DenyJoinRequest', requestData)
    end
    
    cb({status = "success"})
end)

RegisterNetEvent('dw-garages:client:RefreshVehicleList', function()
    if not currentGarage or not isMenuOpen then return end
    
    local garageId = currentGarage.id
    local garageType = currentGarage.type
    
    if garageType == "public" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    elseif garageType == "gang" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetGangVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, PlayerData.gang.name, garageId)
    elseif garageType == "shared" then
        QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarageVehicles', function(vehicles)
            if vehicles then
                SendNUIMessage({
                    action = "refreshVehicles",
                    vehicles = FormatVehiclesForNUI(vehicles)
                })
            end
        end, garageId)
    end
end)

RegisterNetEvent('dw-garages:client:VehicleTransferCompleted', function(successful, plate)
    -- Always reset transfer states regardless of success
    isTransferringVehicle = false
    transferAnimationActive = false
    currentTransferVehicle = nil
    
    -- Close transfer modal if open (send multiple times to ensure it closes)
    SendNUIMessage({
        action = "closeTransferModal"
    })
    
    -- Send again after a small delay to ensure it closes
    Citizen.SetTimeout(100, function()
        SendNUIMessage({
            action = "closeTransferModal"
        })
    end)
    
    -- Send one more time after a longer delay as final safety check
    Citizen.SetTimeout(500, function()
        SendNUIMessage({
            action = "closeTransferModal"
        })
    end)

    -- Ensure the garage UI remains interactive (covers shared remove flow too)
    if currentGarage and isMenuOpen then
        SetNuiFocus(true, true)
    end
    
    if successful then
        if currentGarage and isMenuOpen then
            local garageId = currentGarage.id
            local garageType = currentGarage.type
            
            if garageType == "public" then
                QBCore.Functions.TriggerCallback('dw-garages:server:GetPersonalVehicles', function(vehicles)
                    if vehicles then
                        SendNUIMessage({
                            action = "refreshVehicles",
                            vehicles = FormatVehiclesForNUI(vehicles)
                        })
                    end
                end, garageId)
            elseif garageType == "shared" then
                QBCore.Functions.TriggerCallback('dw-garages:server:GetSharedGarageVehicles', function(vehicles)
                    if vehicles then
                        SendNUIMessage({
                            action = "refreshVehicles",
                            vehicles = FormatVehiclesForNUI(vehicles)
                        })
                    end
                end, garageId)
            end
        end
    else
        -- Transfer failed - ensure NUI focus is restored if menu is still open
        if currentGarage and isMenuOpen then
            SetNuiFocus(true, true)
        end
    end
end)

function GetVehicleClassName(vehicleClass)
    local classes = {
        [0] = "Compact",
        [1] = "Sedan",
        [2] = "SUV",
        [3] = "Coupe",
        [4] = "Muscle",
        [5] = "Sports Classic",
        [6] = "Sports",
        [7] = "Super",
        [8] = "Motorcycle",
        [9] = "Off-road",
        [10] = "Industrial",
        [11] = "Utility",
        [12] = "Van",
        [13] = "Cycle",
        [14] = "Boat",
        [15] = "Helicopter",
        [16] = "Plane",
        [17] = "Service",
        [18] = "Emergency",
        [19] = "Military",
        [20] = "Commercial",
        [21] = "Train",
        [22] = "Open Wheel"
    }
    return classes[vehicleClass] or "Unknown"
end

function GetVehicleHoverInfo(vehicle)
    if not DoesEntityExist(vehicle) then return nil end
    
    local ped = PlayerPedId()
    local plate = QBCore.Functions.GetPlate(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local make = GetMakeNameFromVehicleModel(model)
    local vehicleClass = GetVehicleClass(vehicle)
    local className = GetVehicleClassName(vehicleClass)
    local inVehicle = (GetVehiclePedIsIn(ped, false) == vehicle)
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local fuelLevel = 0
    
    if GetResourceState('LegacyFuel') ~= 'missing' then
        fuelLevel = exports['LegacyFuel']:GetFuel(vehicle)
    elseif GetResourceState('ps-fuel') ~= 'missing' then
        fuelLevel = exports['ps-fuel']:GetFuel(vehicle)
    elseif GetResourceState('qb-fuel') ~= 'missing' then
        fuelLevel = exports['qb-fuel']:GetFuel(vehicle)
    else
        fuelLevel = GetVehicleFuelLevel(vehicle)
    end
    
    local vehicleInfo = nil
    QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleInfo', function(info)
        vehicleInfo = info
    end, plate)
    
    local netId = nil
    if NetworkGetEntityIsNetworked(vehicle) then
        netId = NetworkGetNetworkIdFromEntity(vehicle)
    end
    
    local info = {
        plate = plate,
        model = displayName,
        make = make,
        class = className,
        netId = netId,
        inVehicle = inVehicle,
        fuel = fuelLevel,
        engine = engineHealth / 10,
        body = bodyHealth / 10,
        ownerName = "You",
        garage = "Unknown",
        state = 1 
    }
    
    if vehicleInfo then
        info.name = vehicleInfo.name or info.model
        info.ownerName = vehicleInfo.ownerName or "You"
        info.garage = vehicleInfo.garage or "Unknown"
        info.state = vehicleInfo.state or 1
    end
    
    return info
end


function RayCastGamePlayCamera(distance)
    local cameraRotation = GetGameplayCamRot()
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = {
        x = cameraCoord.x + direction.x * distance,
        y = cameraCoord.y + direction.y * distance,
        z = cameraCoord.z + direction.z * distance
    }
    local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(
        cameraCoord.x, cameraCoord.y, cameraCoord.z,
        destination.x, destination.y, destination.z,
        1, PlayerPedId(), 0
    )
    local _, hit, endCoords, _, entityHit = GetShapeTestResult(rayHandle)
    return hit, endCoords, entityHit
end

function RotationToDirection(rotation)
    local adjustedRotation = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z
    }
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    return direction
end

RegisterNUICallback('enterVehicle', function(data, cb)
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        local ped = PlayerPedId()
        TaskEnterVehicle(ped, vehicle, -1, -1, 1.0, 1, 0)
    end
    
    cb({status = "success"})
end)

RegisterNUICallback('exitVehicle', function(data, cb)
    local ped = PlayerPedId()
    TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 0)
    cb({status = "success"})
end)

RegisterNUICallback('storeHoveredVehicle', function(data, cb)
    local plate = data.plate
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        local garageId, garageType = GetClosestGarage()
        
        if garageId then
            StoreVehicleInGarage(vehicle, garageId, garageType)
            cb({status = "success"})
        else
            QBCore.Functions.Notify("Not near a garage", "error")
            cb({status = "error", message = "Not near a garage"})
        end
    else
        cb({status = "error", message = "Vehicle not found"})
    end
end)

RegisterNUICallback('showVehicleDetails', function(data, cb)
    local plate = data.plate
    local netId = data.netId
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    
    if DoesEntityExist(vehicle) then
        if vehicleHoverInfo then
            showVehicleInfoModal(vehicleHoverInfo)
            cb({status = "success"})
        else
            cb({status = "error", message = "Vehicle info not found"})
        end
    else
        cb({status = "error", message = "Vehicle not found"})
    end
end)

function GetClosestGarage()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local closestDistance = 999999
    local closestGarage = nil
    local closestGarageType = nil
    
    for k, v in pairs(Config.Garages) do
        local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
        if distance < closestDistance and distance < 30.0 then
            closestDistance = distance
            closestGarage = k
            closestGarageType = "public"
        end
    end
    
    for k, v in pairs(Config.JobGarages) do
        if PlayerData.job and PlayerData.job.name == v.job then
            local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
            if distance < closestDistance and distance < 30.0 then
                closestDistance = distance
                closestGarage = k
                closestGarageType = "job"
            end
        end
    end
    
    for k, v in pairs(Config.GangGarages) do
        if PlayerData.gang and PlayerData.gang.name == v.gang then
            local distance = #(playerCoords - vector3(v.coords.x, v.coords.y, v.coords.z))
            if distance < closestDistance and distance < 30.0 then
                closestDistance = distance
                closestGarage = k
                closestGarageType = "gang"
            end
        end
    end
    
    return closestGarage, closestGarageType
end

function StoreVehicleInGarage(vehicle, garageId, garageType)
    local plate = QBCore.Functions.GetPlate(vehicle)
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    
    -- Explicitly capture and save livery to props
    if DoesEntityExist(vehicle) then
        local livery = GetVehicleLivery(vehicle)
        if livery ~= nil and livery >= 0 then
            props.modLivery = livery
        end
    end
    
    local fuel = 0
    
    if GetResourceState('LegacyFuel') ~= 'missing' then
        fuel = exports['LegacyFuel']:GetFuel(vehicle)
    elseif GetResourceState('ps-fuel') ~= 'missing' then
        fuel = exports['ps-fuel']:GetFuel(vehicle)
    elseif GetResourceState('qb-fuel') ~= 'missing' then
        fuel = exports['qb-fuel']:GetFuel(vehicle)
    else
        fuel = GetVehicleFuelLevel(vehicle)
    end
    
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    
    -- Check ownership/access before storing
    QBCore.Functions.TriggerCallback('dw-garages:server:CheckOwnership', function(isOwner, isInGarage)
        -- Allow storage if player owns the vehicle, or has access to shared garage, or has gang access
        if isOwner or isInGarage or (garageType == "gang" and isInGarage) then
            FadeOutVehicle(vehicle, function()
                TriggerServerEvent('dw-garages:server:StoreVehicle', plate, garageId, props, fuel, engineHealth, bodyHealth, garageType)
                QBCore.Functions.Notify("Vehicle stored in garage", "success")
            end)
        else
            QBCore.Functions.Notify("You don't have permission to store this vehicle", "error")
        end
    end, plate, garageType)
end

CreateThread(function()
    if Config.EnableImpound then
        for k, v in pairs(Config.ImpoundLots) do
            local blip = AddBlipForCoord(v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, v.blip.sprite)
            SetBlipDisplay(blip, v.blip.display)
            SetBlipScale(blip, v.blip.scale)
            SetBlipAsShortRange(blip, v.blip.shortRange)
            SetBlipColour(blip, v.blip.color)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentSubstringPlayerName(v.label)
            EndTextCommandSetBlipName(blip)
            
            table.insert(impoundBlips, blip)
        end
    end
end)



RegisterNetEvent('dw-garages:client:OpenImpoundLot')
AddEventHandler('dw-garages:client:OpenImpoundLot', function(data)
    local impoundId = data.impoundId
    local impoundInfo = Config.ImpoundLots[impoundId]
    
    if not impoundInfo then
        QBCore.Functions.Notify("Invalid impound lot", "error")
        return
    end
    
    currentImpoundLot = {id = impoundId, label = impoundInfo.label, coords = impoundInfo.coords}
    
    QBCore.Functions.TriggerCallback('dw-garages:server:GetImpoundedVehicles', function(vehicles)
        if vehicles and #vehicles > 0 then
            SetNuiFocus(true, true)
            SendNUIMessage({
                action = "setImpoundOnly",
                forceImpoundOnly = true
            })
            
            SendNUIMessage({
                action = "openImpound",
                vehicles = FormatVehiclesForNUI(vehicles),
                impound = {
                    name = impoundInfo.label,
                    id = impoundId,
                    location = impoundInfo.label
                }
            })
        else
            QBCore.Functions.Notify("No vehicles in impound", "error")
        end
    end)
end)

RegisterCommand('impound', function(source, args)
    if not PlayerData.job or not Config.ImpoundJobs[PlayerData.job.name] then
        QBCore.Functions.Notify("You are not authorized to impound vehicles", "error")
        return
    end
    
    local impoundFine = tonumber(args[1]) or Config.ImpoundFee  
    
    impoundFine = math.max(100, math.min(10000, impoundFine))  
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = nil
    
    if IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    else
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    
    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify("No vehicle nearby to impound", "error")
        return
    end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then
        QBCore.Functions.Notify("Could not read vehicle plate", "error")
        return
    end
    
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    
    -- Explicitly capture and save livery to props
    if DoesEntityExist(vehicle) then
        local livery = GetVehicleLivery(vehicle)
        if livery ~= nil and livery >= 0 then
            props.modLivery = livery
        end
    end
    
    local dialog = lib.inputDialog("Impound Vehicle", {
        {
            type = 'input',
            label = "Reason for impound",
            description = 'Enter the reason for impounding this vehicle',
            required = true,
            min = 3,
            max = 255,
        }
    })
    
    if dialog and dialog[1] and dialog[1] ~= "" then
        local reason = dialog[1]
        local impoundType = "police"
        
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_CLIPBOARD", 0, true)
        QBCore.Functions.Progressbar("impounding_vehicle", "Impounding Vehicle...", 10000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() 
            ClearPedTasks(ped)
            
            TriggerServerEvent('dw-garages:server:ImpoundVehicleWithParams', plate, props, reason, impoundType, 
                PlayerData.job.name, PlayerData.charinfo.firstname .. " " .. PlayerData.charinfo.lastname, impoundFine)
            
            -- Try to delete vehicle immediately (server will also trigger deletion as backup)
            if DoesEntityExist(vehicle) then
                -- Remove mission entity status before deleting
                if IsEntityAMissionEntity(vehicle) then
                    SetEntityAsMissionEntity(vehicle, false, true)
                end
                local netId = nil
                if NetworkGetEntityIsNetworked(vehicle) then
                    netId = NetworkGetNetworkIdFromEntity(vehicle)
                    if netId then
                        SetNetworkIdCanMigrate(netId, true)
                    end
                end
                FadeOutVehicle(vehicle, function()
                    QBCore.Functions.Notify("Vehicle impounded with $" .. impoundFine .. " fine", "success")
                end)
            else
                -- Vehicle reference is stale, find it by plate
                local vehicles = GetGamePool('CVehicle')
                for i = 1, #vehicles do
                    local veh = vehicles[i]
                    if DoesEntityExist(veh) then
                        local vehPlate = QBCore.Functions.GetPlate(veh)
                        if vehPlate and vehPlate:gsub("%s+", "") == plate:gsub("%s+", "") then
                            if IsEntityAMissionEntity(veh) then
                                SetEntityAsMissionEntity(veh, false, true)
                            end
                            local netId = nil
                            if NetworkGetEntityIsNetworked(veh) then
                                netId = NetworkGetNetworkIdFromEntity(veh)
                                if netId then
                                    SetNetworkIdCanMigrate(netId, true)
                                end
                            end
                            DeleteEntity(veh)
                            QBCore.Functions.Notify("Vehicle impounded with $" .. impoundFine .. " fine", "success")
                            break
                        end
                    end
                end
            end
        end, function() 
            ClearPedTasks(ped)
            QBCore.Functions.Notify("Impound cancelled", "error")
        end)
    end
end, false)

TriggerEvent('chat:addSuggestion', '/impound', 'Impound a vehicle with custom fine', {
    { name = "fine", help = "Fine amount ($100-$10,000)" }
})


function OpenImpoundUI(vehicles, impoundInfo, impoundId)
    local formattedVehicles = {}
   
    for i, vehicle in ipairs(vehicles) do
        local vehicleInfo = QBCore.Shared.Vehicles[vehicle.vehicle]
        if vehicleInfo then
            local enginePercent = round(vehicle.engine / 10, 1)
            local bodyPercent = round(vehicle.body / 10, 1)
            local fuelPercent = vehicle.fuel or 100
           
            local displayName = vehicleInfo.name
            if vehicle.custom_name and vehicle.custom_name ~= "" then
                displayName = vehicle.custom_name
            end
           
            local totalFee = Config.ImpoundFee 
            if vehicle.impoundfee ~= nil then
                local customFee = tonumber(vehicle.impoundfee)
                if customFee and customFee > 0 then
                    totalFee = customFee
                end
            end
           
            local reasonString = vehicle.impoundreason or "No reason specified"
            if reasonString and #reasonString > 50 then
                reasonString = reasonString:sub(1, 47) .. "..."
            end
           
            table.insert(formattedVehicles, {
                id = i,
                plate = vehicle.plate,
                model = vehicle.vehicle,
                name = displayName,
                fuel = fuelPercent,
                engine = enginePercent,
                body = bodyPercent,
                impoundFee = totalFee,
                impoundReason = reasonString,
                impoundType = vehicle.impoundtype or "police",
                impoundedBy = vehicle.impoundedby or "Unknown Officer"
            })
        end
    end
   
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openImpound",
        vehicles = formattedVehicles,
        impound = {
            name = impoundInfo.label,
            id = impoundId,
            location = impoundInfo.label
        }
    })
end

RegisterNUICallback('releaseImpoundedVehicle', function(data, cb)
    local plate = data.plate
    local impoundId = currentImpoundLot.id
    local fee = data.fee
    
    if not plate or not impoundId then
        cb({status = "error", message = "Invalid data"})
        return
    end
    
    -- Clean the plate (remove spaces)
    plate = plate:gsub("%s+", "")
    
    QBCore.Functions.TriggerCallback('dw-garages:server:CanPayImpoundFee', function(canPay)
        if canPay then
            local impoundInfo = Config.ImpoundLots[impoundId]
            local spawnPoint = FindClearSpawnPoint(impoundInfo.spawnPoints)
            
            if not spawnPoint then
                QBCore.Functions.Notify("All spawn locations are blocked!", "error")
                cb({status = "error", message = "Spawn blocked"})
                return
            end
            
            QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleByPlate', function(vehData)
                if vehData then
                    QBCore.Functions.TriggerCallback('dw-garages:server:GetVehicleProperties', function(properties)
                        if properties then
                            local spawnCoords = vector3(spawnPoint.x, spawnPoint.y, spawnPoint.z)
                            QBCore.Functions.SpawnVehicle(vehData.vehicle, function(veh)
                                if not veh or veh == 0 then
                                    QBCore.Functions.Notify("Failed to spawn vehicle", "error")
                                    cb({status = "error", message = "Failed to spawn"})
                                    return
                                end
                                
                                -- Make vehicle persist when player disconnects
                                SetEntityAsMissionEntity(veh, true, true)
                                SetEntityCanBeDamaged(veh, true)
                                SetEntityInvincible(veh, false)
                                if NetworkGetEntityIsNetworked(veh) then
                                    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(veh), false)
                                end
                                
                                SetEntityHeading(veh, spawnPoint.w)
                                SetEntityCoords(veh, spawnPoint.x, spawnPoint.y, spawnPoint.z)
                                SetVehicleFuelLevel(veh, vehData.fuel or 100)
                                SetVehicleNumberPlateText(veh, plate)
                                FadeInVehicle(veh)
                                
                                -- Apply vehicle properties including livery
                                QBCore.Functions.SetVehicleProperties(veh, properties)
                                Wait(200) -- Wait to ensure properties are applied
                                
                                -- Explicitly apply livery if it exists in properties (check multiple possible property names)
                                if properties.modLivery ~= nil then
                                    SetVehicleLivery(veh, properties.modLivery)
                                    Wait(50)
                                    SetVehicleLivery(veh, properties.modLivery) -- Apply twice to ensure it sticks
                                elseif properties.livery ~= nil then
                                    SetVehicleLivery(veh, properties.livery)
                                    Wait(50)
                                    SetVehicleLivery(veh, properties.livery) -- Apply twice to ensure it sticks
                                end
                                
                                -- Get engine and body health - check properties first, then database values
                                local engineHealth = 1000.0
                                local bodyHealth = 1000.0
                                
                                -- Check if properties have health values stored (in 0-1000 format)
                                if properties.engineHealth ~= nil then
                                    engineHealth = math.max(tonumber(properties.engineHealth) or 1000.0, 200.0)
                                elseif vehData.engine ~= nil then
                                    -- Database stores as 0-100, convert to 0-1000
                                    local dbEngine = tonumber(vehData.engine) or 100
                                    engineHealth = math.max(dbEngine * 10.0, 200.0)
                                end
                                
                                if properties.bodyHealth ~= nil then
                                    bodyHealth = math.max(tonumber(properties.bodyHealth) or 1000.0, 200.0)
                                elseif vehData.body ~= nil then
                                    -- Database stores as 0-100, convert to 0-1000
                                    local dbBody = tonumber(vehData.body) or 100
                                    bodyHealth = math.max(dbBody * 10.0, 200.0)
                                end
                                
                                -- Ensure values are within valid range (200-1000)
                                engineHealth = math.max(200.0, math.min(1000.0, engineHealth))
                                bodyHealth = math.max(200.0, math.min(1000.0, bodyHealth))
                                
                                SetVehicleEngineHealth(veh, engineHealth)
                                SetVehicleBodyHealth(veh, bodyHealth)
                                SetVehicleDirtLevel(veh, 0.0) 
                                
                                FixEngineSmoke(veh)

                                SetVehicleUndriveable(veh, false)
                                SetVehicleEngineOn(veh, false, true, false)
                                
                                -- Lock vehicle doors (after all properties are set)
                                ApplyGarageLock(veh)

                                TriggerEvent("vehiclekeys:client:SetOwner", plate)
                                
                                -- Pay fee - PayImpoundFee will update state from 2 (impounded) to 0 (outside)
                                -- This must be called AFTER vehicle spawns to ensure proper state handling
                                TriggerServerEvent('dw-garages:server:PayImpoundFee', plate, fee)
                                
                                -- PayImpoundFee already updates state to 0 and OutsideVehicles tracking
                                -- No need for additional UpdateVehicleState call here
                                
                                QBCore.Functions.Notify("Vehicle released from impound", "success")
                                cb({status = "success"})
                            end, spawnCoords, true)
                        else
                            QBCore.Functions.Notify("Failed to load vehicle properties", "error")
                            cb({status = "error", message = "Failed to load vehicle"})
                        end
                    end, plate)
                else
                    QBCore.Functions.Notify("Vehicle data not found", "error")
                    cb({status = "error", message = "Vehicle not found"})
                end
            end, plate)
        else
            QBCore.Functions.Notify("You don't have enough money to pay the impound fee", "error")
            cb({status = "error", message = "Insufficient funds"})
        end
    end, fee)
end)

RegisterNetEvent('dw-garages:client:ImpoundVehicle')
AddEventHandler('dw-garages:client:ImpoundVehicle', function()
    if not PlayerData.job or not Config.ImpoundJobs[PlayerData.job.name] then
        QBCore.Functions.Notify("You are not authorized to impound vehicles", "error")
        return
    end
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = nil
    
    if IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    else
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, 5.0, 0, 71)
    end
    
    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify("No vehicle nearby to impound", "error")
        return
    end
    
    local plate = QBCore.Functions.GetPlate(vehicle)
    if not plate then
        QBCore.Functions.Notify("Could not read vehicle plate", "error")
        return
    end
    
    local props = QBCore.Functions.GetVehicleProperties(vehicle)
    
    -- Explicitly capture and save livery to props
    if DoesEntityExist(vehicle) then
        local livery = GetVehicleLivery(vehicle)
        if livery ~= nil and livery >= 0 then
            props.modLivery = livery
        end
    end
    
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)
    local impoundType = "police"
    
    -- Convert Config.ImpounderTypes to ox_lib format
    local impoundOptions = {}
    for key, value in pairs(Config.ImpounderTypes) do
        table.insert(impoundOptions, {label = value, value = key})
    end
    
    local dialog = lib.inputDialog("Impound Vehicle", {
        {
            type = 'input',
            label = "Reason for Impound",
            description = 'Enter the reason for impounding this vehicle',
            required = true,
            min = 3,
            max = 255,
        },
        {
            type = 'select',
            label = "Impound Type",
            description = 'Select the type of impound',
            options = impoundOptions,
            default = "police",
            required = true,
        }
    })
    
    if dialog and dialog[1] and dialog[1] ~= "" and dialog[2] then
        local reason = dialog[1]
        local impoundType = dialog[2]
        TaskStartScenarioInPlace(ped, "PROP_HUMAN_CLIPBOARD", 0, true)
        QBCore.Functions.Progressbar("impounding_vehicle", "Impounding Vehicle...", 10000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function() 
            ClearPedTasks(ped)
            
            TriggerServerEvent('dw-garages:server:ImpoundVehicle', plate, props, reason, impoundType, PlayerData.job.name, PlayerData.charinfo.firstname .. " " .. PlayerData.charinfo.lastname)
            
            -- Try to delete vehicle immediately (server will also trigger deletion as backup)
            if DoesEntityExist(vehicle) then
                -- Remove mission entity status before deleting
                if IsEntityAMissionEntity(vehicle) then
                    SetEntityAsMissionEntity(vehicle, false, true)
                end
                local netId = nil
                if NetworkGetEntityIsNetworked(vehicle) then
                    netId = NetworkGetNetworkIdFromEntity(vehicle)
                    if netId then
                        SetNetworkIdCanMigrate(netId, true)
                    end
                end
                FadeOutVehicle(vehicle, function()
                    QBCore.Functions.Notify("Vehicle impounded successfully", "success")
                end)
            else
                -- Vehicle reference is stale, find it by plate
                local vehicles = GetGamePool('CVehicle')
                for i = 1, #vehicles do
                    local veh = vehicles[i]
                    if DoesEntityExist(veh) then
                        local vehPlate = QBCore.Functions.GetPlate(veh)
                        if vehPlate and vehPlate:gsub("%s+", "") == plate:gsub("%s+", "") then
                            if IsEntityAMissionEntity(veh) then
                                SetEntityAsMissionEntity(veh, false, true)
                            end
                            local netId = nil
                            if NetworkGetEntityIsNetworked(veh) then
                                netId = NetworkGetNetworkIdFromEntity(veh)
                                if netId then
                                    SetNetworkIdCanMigrate(netId, true)
                                end
                            end
                            DeleteEntity(veh)
                            QBCore.Functions.Notify("Vehicle impounded successfully", "success")
                            break
                        end
                    end
                end
            end
        end, function() 
            ClearPedTasks(ped)
            QBCore.Functions.Notify("Impound cancelled", "error")
        end)
    end
end)

-- Event to delete impounded vehicle by plate (called from server after successful impound)
RegisterNetEvent('dw-garages:client:DeleteImpoundedVehicle', function(plate)
    if not plate then return end
    
    plate = plate:gsub("%s+", "")
    
    -- Find vehicle by plate
    local vehicles = GetGamePool('CVehicle')
    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if DoesEntityExist(vehicle) then
            local vehiclePlate = QBCore.Functions.GetPlate(vehicle)
            if vehiclePlate and vehiclePlate:gsub("%s+", "") == plate then
                -- Remove mission entity status before deleting
                if IsEntityAMissionEntity(vehicle) then
                    SetEntityAsMissionEntity(vehicle, false, true)
                end
                
                -- Allow network migration temporarily for deletion
                local netId = nil
                if NetworkGetEntityIsNetworked(vehicle) then
                    netId = NetworkGetNetworkIdFromEntity(vehicle)
                    if netId then
                        SetNetworkIdCanMigrate(netId, true)
                    end
                end
                
                -- Delete the vehicle
                DeleteEntity(vehicle)
                break
            end
        end
    end
end)

RegisterNUICallback('closeImpound', function(data, cb)
    SetNuiFocus(false, false)
    cb({status = "success"})
end)

-- Track player's current vehicle for crash/disconnect handling
CreateThread(function()
    local lastVehiclePlate = nil
    
    while true do
        Wait(5000) -- Check every 5 seconds
        
        if isPlayerLoaded then
            local ped = PlayerPedId()
            local isInVehicle = IsPedInAnyVehicle(ped, false)
            
            if isInVehicle then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if DoesEntityExist(vehicle) then
                    local plate = QBCore.Functions.GetPlate(vehicle)
                    if plate then
                        plate = plate:gsub("%s+", "") -- Remove spaces
                        
                        -- Only send update if plate changed
                        if plate ~= lastVehiclePlate then
                            lastVehiclePlate = plate
                            TriggerServerEvent('dw-garages:server:UpdatePlayerVehicle', plate)
                        end
                    end
                end
            else
                -- Player is not in a vehicle, clear tracking
                if lastVehiclePlate then
                    lastVehiclePlate = nil
                    TriggerServerEvent('dw-garages:server:UpdatePlayerVehicle', nil)
                end
            end
        end
    end
end)
