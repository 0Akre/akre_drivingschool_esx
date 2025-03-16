ESX = exports["es_extended"]:getSharedObject()

local function SendNotification(source, message, type)
    if Config.Notify.system == "qb" then
        TriggerClientEvent('esx:showNotification', source, message)
    elseif Config.Notify.system == "ox" then
        TriggerClientEvent('ox_lib:notify', source, {
            description = message,
            type = type or 'success'
        })
    else
        TriggerClientEvent('esx:showNotification', source, message)
    end
end

ESX.RegisterServerCallback('driving-school:server:hasLicense', function(source, cb, licenseType)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    TriggerEvent('esx_license:checkLicense', source, licenseType, function(hasLicense)
        cb(hasLicense)
    end)
end)

RegisterNetEvent('driving-school:server:addLicense')
AddEventHandler('driving-school:server:addLicense', function(playerId, licenseType)
    local src = source
    if not playerId then src = source else src = playerId end
    
    TriggerEvent('esx_license:addLicense', src, licenseType, function()
        local message = "Získal jsi novou licenci: " .. licenseType
        SendNotification(src, message, 'success')
    end)
end)

RegisterNetEvent('driving-school:server:removeLicense')
AddEventHandler('driving-school:server:removeLicense', function(playerId, licenseType)
    local src = source
    if not playerId then src = source else src = playerId end
    
    TriggerEvent('esx_license:removeLicense', src, licenseType, function()
        local message = "Byla ti odebrána licence: " .. licenseType
        SendNotification(src, message, 'error')
    end)
end)

ESX.RegisterServerCallback('driving-school:server:checkMoney', function(source, cb, price)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if xPlayer.getMoney() >= price then
        xPlayer.removeMoney(price)
        
        local message = Config.Notify.messages.payment_success:gsub("{price}", price)
        SendNotification(source, message, 'success')
        
        cb(true)
    else
        local message = Config.Notify.messages.insufficient_funds:gsub("{price}", price)
        SendNotification(source, message, 'error')
        cb(false)
    end
end)

ESX.RegisterServerCallback('driving-school:server:hasPassedTheory', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    local result = MySQL.Sync.fetchScalar('SELECT theory_passed FROM driving_school_progress WHERE identifier = @identifier', {
        ['@identifier'] = xPlayer.getIdentifier()
    })
    
    cb(result == 1)
end)

RegisterNetEvent('driving-school:server:saveTheoryResult')
AddEventHandler('driving-school:server:saveTheoryResult', function(passed)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if passed then
        MySQL.Sync.execute('INSERT INTO driving_school_progress (identifier, theory_passed) VALUES (@identifier, 1) ON DUPLICATE KEY UPDATE theory_passed = 1', {
            ['@identifier'] = xPlayer.getIdentifier()
        })
    end
end)

RegisterNetEvent('driving-school:server:giveLicense')
AddEventHandler('driving-school:server:giveLicense', function(licenseType, licenseClass)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local licenseLabel = ''
    local licenseType = ''
    
    if licenseClass == "A" then
        licenseType = "motorcycle"
        licenseLabel = Config.Notify.messages.license_A
    elseif licenseClass == "B" then
        licenseType = "drive"
        licenseLabel = Config.Notify.messages.license_B
    elseif licenseClass == "C" then
        licenseType = "truck"
        licenseLabel = Config.Notify.messages.license_C
    elseif licenseClass == "D" then
        licenseType = "bus"
        licenseLabel = Config.Notify.messages.license_D
    end
    
    TriggerEvent('esx_license:addLicense', src, licenseType, function()
        SendNotification(src, licenseLabel, 'success')
    end)
end)

ESX.RegisterServerCallback('driving-school:server:getAllLicenses', function(source, cb, target)
    local xPlayer = ESX.GetPlayerFromId(target)
    
    MySQL.Async.fetchAll('SELECT * FROM user_licenses WHERE owner = @owner', {
        ['@owner'] = xPlayer.getIdentifier()
    }, function(result)
        local licenses = {}
        for i=1, #result, 1 do
            table.insert(licenses, {
                type = result[i].type,
                label = result[i].label
            })
        end
        
        cb(licenses)
    end)
end)

MySQL.ready(function()
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `driving_school_progress` (
            `identifier` varchar(60) NOT NULL,
            `theory_passed` tinyint(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`)
        )
    ]])
end)

RegisterCommand('checkdriverlicense', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    TriggerEvent('esx_license:checkLicense', source, 'drive', function(hasLicense)
        if hasLicense then
            print(xPlayer.getName() .. " has a driver's license")
            SendNotification(source, "You have a driver's license", 'success')
        else
            print(xPlayer.getName() .. " does not have a driver's license")
            SendNotification(source, "You do not have a driver's license", 'error')
        end
    end)
end, false)

RegisterCommand('removelicense', function(source, args, rawCommand)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if args[1] and args[2] then
        local targetId = tonumber(args[1])
        local licenseType = args[2]
        
        if not targetId then
            SendNotification(source, "Invalid player ID", 'error')
            return
        end
        
        local targetPlayer = ESX.GetPlayerFromId(targetId)
        if not targetPlayer then
            SendNotification(source, "Player with ID " .. targetId .. " not found", 'error')
            return
        end
        
        MySQL.Async.execute('DELETE FROM user_licenses WHERE type = @type AND owner = @owner', {
            ['@type'] = licenseType,
            ['@owner'] = targetPlayer.getIdentifier()
        }, function(rowsChanged)
            if rowsChanged > 0 then
                print("Removed " .. rowsChanged .. " licenses of type " .. licenseType .. " from player " .. targetPlayer.getName())
                SendNotification(source, "You have removed " .. licenseType .. " license from player " .. targetPlayer.getName(), 'success')
                SendNotification(targetId, "Your " .. licenseType .. " license has been removed", 'error')
            else
                print("No licenses were removed - the player probably does not have it")
                SendNotification(source, "The player does not have a " .. licenseType .. " license", 'error')
            end
        end)
    else
        SendNotification(source, "Usage: /removelicense [Player ID] [License Type]", 'error')
    end
end, false)