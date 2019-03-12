ESX              = nil
local Categories = {}
local Vehicles   = {}

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

Citizen.CreateThread(function()
	local char = Config.PlateLetters
	char = char + Config.PlateNumbers
	if Config.PlateUseSpace then char = char + 1 end

	if char > 8 then
		print(('esx_vehicleshop_lite: ^1WARNING^7 plate character count reached, %s/8 characters.'):format(char))
	end
end)

function RemoveOwnedVehicle(plate)
	MySQL.Async.execute('DELETE FROM owned_vehicles WHERE plate = @plate', {
		['@plate'] = plate
	})
end

MySQL.ready(function()
	Categories     = MySQL.Sync.fetchAll('SELECT * FROM vehicle_categories')
	local vehicles = MySQL.Sync.fetchAll('SELECT * FROM vehicles')

	for i=1, #vehicles, 1 do
		local vehicle = vehicles[i]

		for j=1, #Categories, 1 do
			if Categories[j].name == vehicle.category then
				vehicle.categoryLabel = Categories[j].label
				vehicle.categoryLabel_cn = Categories[j].label_cn
				vehicle.categoryLabel_zh = Categories[j].label_zh
				break
			end
		end

		table.insert(Vehicles, vehicle)
	end

	-- send information after db has loaded, making sure everyone gets vehicle information
	TriggerClientEvent('esx_vehicleshop_lite:sendCategories', -1, Categories)
	TriggerClientEvent('esx_vehicleshop_lite:sendVehicles', -1, Vehicles)
end)

RegisterServerEvent('esx_vehicleshop_lite:setVehicleOwned')
AddEventHandler('esx_vehicleshop_lite:setVehicleOwned', function (vehicleProps)
	local _source = source
	local xPlayer = ESX.GetPlayerFromId(_source)

	MySQL.Async.execute('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (@owner, @plate, @vehicle)',
	{
		['@owner']   = xPlayer.identifier,
		['@plate']   = vehicleProps.plate,
		['@vehicle'] = json.encode(vehicleProps)
	}, function (rowsChanged)
		TriggerClientEvent('esx:showVehicleNotification', _source, 'vehicle_belongs', vehicleProps.plate)
	end)
end)

RegisterServerEvent('esx_vehicleshop_lite:setVehicleOwnedPlayerId')
AddEventHandler('esx_vehicleshop_lite:setVehicleOwnedPlayerId', function (playerId, vehicleProps)
	local xPlayer = ESX.GetPlayerFromId(playerId)

	MySQL.Async.execute('INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (@owner, @plate, @vehicle)',
	{
		['@owner']   = xPlayer.identifier,
		['@plate']   = vehicleProps.plate,
		['@vehicle'] = json.encode(vehicleProps)
	}, function (rowsChanged)
		TriggerClientEvent('esx:showVehicleNotification', playerId, 'vehicle_belongs', vehicleProps.plate)
	end) 
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:getCategories', function (source, cb)
	cb(Categories)
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:getVehicles', function (source, cb)
	cb(Vehicles)
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:buyVehicle', function (source, cb, vehicleModel)
	local xPlayer     = ESX.GetPlayerFromId(source)
	local vehicleData = nil

	for i=1, #Vehicles, 1 do
		if Vehicles[i].model == vehicleModel then
			vehicleData = Vehicles[i]
			break
		end
	end

	if xPlayer.getMoney() >= vehicleData.price then
		xPlayer.removeMoney(vehicleData.price)
		cb(true)
	else
		cb(false)
	end
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:resellVehicle', function (source, cb, plate, model)
	local resellPrice = 0

	-- calculate the resell price
	for i=1, #Vehicles, 1 do
		if GetHashKey(Vehicles[i].model) == model then
			resellPrice = ESX.Math.Round(Vehicles[i].price / 100 * Config.ResellPercentage)
			break
		end
	end

	if resellPrice == 0 then
		print(('esx_vehicleshop_lite: %s attempted to sell an unknown vehicle!'):format(GetPlayerIdentifiers(source)[1]))
		cb(false)
	end

	MySQL.Async.fetchAll('SELECT * FROM rented_vehicles WHERE plate = @plate', {
		['@plate'] = plate
	}, function (result)
		if result[1] then -- is it a rented vehicle?
			cb(false) -- it is, don't let the player sell it since he doesn't own it
		else
			local xPlayer = ESX.GetPlayerFromId(source)

			MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE owner = @owner AND @plate = plate', {
				['@owner'] = xPlayer.identifier,
				['@plate'] = plate
			}, function (result)

				if result[1] then -- does the owner match?

					local vehicle = json.decode(result[1].vehicle)

					if vehicle.model == model then
						if vehicle.plate == plate then
							xPlayer.addMoney(resellPrice)
							RemoveOwnedVehicle(plate)
							cb(true)
						else
							print(('esx_vehicleshop_lite: %s attempted to sell an vehicle with plate mismatch!'):format(xPlayer.identifier))
							cb(false)
						end
					else
						print(('esx_vehicleshop_lite: %s attempted to sell an vehicle with model mismatch!'):format(xPlayer.identifier))
						cb(false)
					end
				else

					if xPlayer.job.grade_name == 'boss' then
						MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE owner = @owner AND @plate = plate', {
							['@owner'] = 'society:' .. xPlayer.job.name,
							['@plate'] = plate
						}, function (result)

							if result[1] then

								local vehicle = json.decode(result[1].vehicle)

								if vehicle.model == model then
									if vehicle.plate == plate then
										xPlayer.addMoney(resellPrice)
										RemoveOwnedVehicle(plate)

										cb(true)
									else
										print(('esx_vehicleshop_lite: %s attempted to sell an vehicle with plate mismatch!'):format(xPlayer.identifier))
										cb(false)
									end
								else
									print(('esx_vehicleshop_lite: %s attempted to sell an vehicle with model mismatch!'):format(xPlayer.identifier))
									cb(false)
								end

							else
								cb(false)
							end

						end)
					else
						cb(false)
					end
				end

			end)
		end
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:isPlateTaken', function (source, cb, plate)
	MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE plate = @plate', {
		['@plate'] = plate
	}, function (result)
		cb(result[1] ~= nil)
	end)
end)

ESX.RegisterServerCallback('esx_vehicleshop_lite:retrieveJobVehicles', function (source, cb, type)
	local xPlayer = ESX.GetPlayerFromId(source)

	MySQL.Async.fetchAll('SELECT * FROM owned_vehicles WHERE owner = @owner AND type = @type AND job = @job', {
		['@owner'] = xPlayer.identifier,
		['@type'] = type,
		['@job'] = xPlayer.job.name
	}, function (result)
		cb(result)
	end)
end)

RegisterServerEvent('esx_vehicleshop_lite:setJobVehicleState')
AddEventHandler('esx_vehicleshop_lite:setJobVehicleState', function(plate, state)
	local xPlayer = ESX.GetPlayerFromId(source)

	MySQL.Async.execute('UPDATE owned_vehicles SET `stored` = @stored WHERE plate = @plate AND job = @job', {
		['@stored'] = state,
		['@plate'] = plate,
		['@job'] = xPlayer.job.name
	}, function(rowsChanged)
		if rowsChanged == 0 then
			print(('esx_vehicleshop_lite: %s exploited the garage!'):format(xPlayer.identifier))
		end
	end)
end)

function PayRent(d, h, m)
	MySQL.Async.fetchAll('SELECT * FROM rented_vehicles', {}, function (result)
		for i=1, #result, 1 do
			local xPlayer = ESX.GetPlayerFromIdentifier(result[i].owner)

			-- message player if connected
			if xPlayer ~= nil then
				xPlayer.removeAccountMoney('bank', result[i].rent_price)
				TriggerClientEvent('esx:showVehicleNotification', xPlayer.source, 'paid_rental', ESX.Math.GroupDigits(result[i].rent_price))
			else -- pay rent either way
				MySQL.Sync.execute('UPDATE users SET bank = bank - @bank WHERE identifier = @identifier',
				{
					['@bank']       = result[i].rent_price,
					['@identifier'] = result[i].owner
				})
			end

			TriggerEvent('esx_addonaccount:getSharedAccount', 'society_cardealer', function(account)
				account.addMoney(result[i].rent_price)
			end)
		end
	end)
end

TriggerEvent('cron:runAt', 22, 00, PayRent)
