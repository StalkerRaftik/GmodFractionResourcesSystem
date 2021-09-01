util.AddNetworkString("rp.Fractions.Network")
util.AddNetworkString("rp.Fractions.NetworkToClient")
-----------------------------------------------
---------- FRACTION RESOURCES SYSTEM ----------
--------------- (By LOST CITY) ----------------

rp = rp or {}
rp.Fractions = rp.Fractions or {}

-----------------------------------------------
------------------ Константы ------------------
-----------------------------------------------
local PayDayTimer = 1800
local FractionDeathPenalty = 1
local ResPerMember = 15
local ResFromMembersLimit = 150
local PropsPaymentMultiplier = 0.125 -- ex.: 20props * 0.25 = 5 resources payment
-- Flags integration
local DirectFlagResourcesIncome = 50 -- will be added directly in fraction resources
local FlagResourcesIncome = 50 -- will be added to flag container

local KitPrice1 = 5
local KitPrice2 = 10
local KitPrice3 = 20
local KitPrice4 = 30
local GeneralKitsCooldown = 600 -- in seconds

-----------------------------------------------
------------------ Формулы --------------------
-----------------------------------------------


-----------------------------------------------
------------------ База данных ----------------
-----------------------------------------------

-- DATA INITIALIZING
hook.Add("Initialize", "rp.Fractions.CreateDB", function()
    db:Query("CREATE TABLE IF NOT EXISTS rp_fractionresources(Name VARCHAR(255) NOT NULL PRIMARY KEY, data TEXT NOT NULL)")
end)

function UpdateFractionResourcesDB()
	for name, obj in pairs(rp.Fractions) do
		if obj.DataInitialized ~= true then continue end

		local Data = obj:BuildDBData()
		db:Query("UPDATE rp_fractionresources SET data=? WHERE Name=?;", util.TableToJSON(Data), name)
	end
end



-----------------------------------------------
------------------ Класс ----------------------
-----------------------------------------------
local Fraction = {
	Entity = nil,
	Name = "_Base",
	NPC = nil,
	DataInitialized = false,
	Props = {},
}
local mt = {__index = Fraction}


function Fraction:Create(name)
	local obj = {}
	setmetatable(obj, mt)

	obj.Name = name
	rp.Fractions[name] = obj
	obj.Props = {}

	return obj
end

function Fraction:ReadDBData()
	db:Query("SELECT * FROM rp_fractionresources WHERE Name='" .. self.Name .. "' LIMIT 1;", function(rawdata)
		if rawdata[1] then
			local fractionData = util.JSONToTable(rawdata[1].data)
			local resources = fractionData.Resources
			local props = util.JSONToTable(rawdata[1].props)
			self.Props = props
			self:AddResources(resources)
			FractionSpawnProps(self)
		else
			db:Query('INSERT INTO rp_fractionresources (name, data, props) VALUES(?, ?, ?);', self.Name, util.TableToJSON({Resources = 0}), util.TableToJSON({}))
		end
		self.DataInitialized = true
	end)
end

function Fraction:AddProp(content)
	table.insert(self.Props, nil, content)
end

function Fraction:CreateEntity(mdl, vec, ang)
	local resEnt = ents.Create("loot_container")
	resEnt:SetModel(mdl)
	resEnt:SetPos(vec)
	resEnt:SetAngles(ang)
    resEnt:Spawn()
	local phys = resEnt:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end
    constraint.RemoveAll(resEnt)
    self.Entity = resEnt

   	self:ReadDBData()

   	return self
end

function Fraction:GetName()
	return self.Name
end

function Fraction:GetResources()
	return self.Entity:GetItemCount("entity", "resources")
end
function Fraction:AddResources(amount)
	if not isnumber(amount) or amount <= 0 then return end

	self.Entity:AddItem(INV_ENTITY, "resources", amount)
	if self.NPC then
		self.NPC:SetNVar('FractionResources', self:GetResources(), NETWORK_PROTOCOL_PUBLIC)
	end

	self:CheckResourcesLimit()
end

function Fraction:CheckResourcesLimit()
	if self:GetResources() > 20000 then
		self:RemoveResources(self:GetResources() - 20000)
	end
end

function Fraction:RemoveResources(amount)
	self.Entity:RemoveItem(INV_ENTITY, "resources", amount)
	if self.NPC then
		self.NPC:SetNVar('FractionResources', self:GetResources(), NETWORK_PROTOCOL_PUBLIC)
	end
end

function Fraction:BuildDBData()
	local Data = {
		Resources = self:GetResources()
	}
	return Data
end

function Fraction:GetPlayersCount()
	local counter = 0
	for _,ply in pairs(player.GetAll()) do
		if ply:GetFraction() == self then
			counter = counter + 1
		end
	end
	return counter
end

// FLAGS INTEGRATION
function Fraction:AddFlagResources(flag, amount)
	flag.container:AddItem(INV_ENTITY, "resources", amount)
end

function Fraction:GetPropsCount()
	return #self.Props
end

function Fraction:GetResourcesForPropsHolding()
	return math.Round(#self.Props * PropsPaymentMultiplier)
end

function Fraction:GetCapturedTerritoriesTables()
	local capturedTerritories = {}
	for name, flag in pairs(rp.Conquest.Flags) do
		if flag:GetNVar("FlagOwner") == self.Name then
			table.insert(capturedTerritories, flag.id)
		end
	end

	return capturedTerritories
end

---------------------------------------------------

function Fraction:PayDayAdvertising(ResourcesByFlags, ResourcesWasAdded, ResourcesWasSpended)
	for _,ply in pairs(player.GetAll()) do
		local fraction = ply:GetFraction()
		if fraction == self then
			ply:SendSystemMessage("*", '============= ПРИБЫЛЬ ФРАКЦИИ =============')
			ply:SendSystemMessage("*", 'Суммарная прибыль: ' .. (ResourcesWasAdded >= 0 and ("+" .. ResourcesWasAdded) or ResourcesWasAdded) .. ".")
			ply:SendSystemMessage("*", 'Из них:')
			ply:SendSystemMessage("*", '+' .. ResourcesByFlags .. ' за удержание флагов')
			ply:SendSystemMessage("*", '+' .. math.Clamp(ResPerMember * self:GetPlayersCount(), 0, ResFromMembersLimit) .. ' за участников в сети')
			ply:SendSystemMessage("*", 'Со склада для поддержания строений было потрачено ' .. math.Round(#fraction.Props/4) .. ' ресурсов')
			ply:SendSystemMessage("*", 'Теперь на складе ' .. fraction:GetResources() .. " ресурсов.")
			ply:SendSystemMessage("*", '')
			local territories = fraction:GetCapturedTerritoriesTables()
			if #territories > 0 then
				ply:SendSystemMessage("*", 'В контейнер каждой удерживаемой территории было добавлено +' .. FlagResourcesIncome .. " ресурсов.")
				ply:SendSystemMessage("*", 'Успейте их забрать раньше конкурентов!')
				ply:SendSystemMessage("*", 'Текущие удерживаемые территории:')
				local outstr = ""
				for key, idName in pairs(territories) do
					outstr = outstr .. idName .. ", "
				end
				ply:SendSystemMessage("*", string.sub( outstr, 1, #outstr - 2))
				ply:SendSystemMessage("*", '')
			end
			ply:SendSystemMessage("*", 'Следующий конвой придет через ' .. math.floor(PayDayTimer/60) .. " минут")
			ply:SendSystemMessage("*", 'С предыдущего конвоя было суммарно потрачено ' .. ResourcesWasSpended .. ' ресурсов')
			ply:SendSystemMessage("*", '===========================================')
		end
	end
end

function Fraction:PayDay()
	self.ResourcesAfterPayday = self.ResourcesAfterPayday or self:GetResources()

	local ResDiffBetweenPaydays = self.ResourcesAfterPayday - self:GetResources()
	local oldResources = self:GetResources()
	local playersOnline = self:GetPlayersCount()
	local NewResources = math.Clamp(ResPerMember * playersOnline, 0, ResFromMembersLimit)
	
	local ResourcesByFlags = 0
	for name, flag in pairs(rp.Conquest.Flags) do
		if flag:GetNVar("FlagOwner") ~= self.Name then continue end

		ResourcesByFlags = ResourcesByFlags + DirectFlagResourcesIncome
		self:AddFlagResources(flag, FlagResourcesIncome)
	end
	NewResources = NewResources + ResourcesByFlags
	self:AddResources(NewResources)
	self:RemoveResources(self:GetResourcesForPropsHolding())
	self.ResourcesAfterPayday = self:GetResources()

	self:PayDayAdvertising(ResourcesByFlags, self:GetResources() - oldResources, ResDiffBetweenPaydays)
end

function Fraction:MemberDied()
	self:RemoveResources(FractionDeathPenalty)
end

function Fraction:GetKitPrice(kitGrade)
	if kitGrade == 1 then
		return KitPrice1
	elseif kitGrade == 2 then
		return KitPrice2
	elseif kitGrade == 3 then
		return KitPrice3
	elseif kitGrade == 4 then
		return KitPrice4
	end
end

------------Внешние функции----------------
function PLAYER:GiveKit(kitGrade)
	local fraction = self:GetFraction()
	local kits = rp.teams[self:GetJob()].kits
	if fraction == nil or kits == nil then return end

	self:SetWeaponsGivingWithoutInventoryFlag()
	for i = 1, 2 do
		if kitGrade < i then
			self:RemoveWeaponsGivingWithoutInventoryFlag()
			return
		end

		if kits[i] == nil or table.IsEmpty(kits[i]) then continue end

		for type, tab in pairs(kits[i]) do
			for class, count in pairs(tab) do
				if not isnumber(count) then 
					class = count 
					count = 1
				end

				if type == "weapon" then
					self:Give(class, true)
				else
					self:AddItem(type, class, { count = count, droppable = false, })
				end
			end
		end
	end
	self:RemoveWeaponsGivingWithoutInventoryFlag()

	if kitGrade > 2 then
		for type, tab in pairs(kits[kitGrade]) do
			for class, count in pairs(tab) do
				if not isnumber(count) then 
					class = count 
					count = 1
				end

				if type == "weapon" then
					self:Give(class, true)
				else
					self:AddItem(type, class, { count = count, droppable = false, })
				end
			end
		end
	end

	rp.Notify(self, NOTIFY_ERROR, "Вы получили набор!")

	hook.Run( "rp.Fractions.PlayerGetResources", self, fraction, fraction:GetKitPrice(kitGrade) )
end

function PLAYER:TryToGetKit(kitGrade)
	if self.JobKitsCooldown and self.JobKitsCooldown[kitGrade] and self.JobKitsCooldown[kitGrade] > CurTime() then
		rp.Notify(self, NOTIFY_ERROR, "Следующий раз этот набор можно будет взять через " .. math.Round((self.JobKitsCooldown[kitGrade]-CurTime())/60) .. " минут")
		return
	end

	local fraction = self:GetFraction()
	if fraction == nil then return end

	local ResourcesNeeded = fraction:GetKitPrice(kitGrade)

	local FractionResources = fraction:GetResources()
	if FractionResources < ResourcesNeeded then
		rp.Notify(self, NOTIFY_ERROR, "Не хватает ресурсов группировки!")
		return
	end

	self.JobKitsCooldown = self.JobKitsCooldown or {}
	self.JobKitsCooldown[kitGrade] = CurTime() + GeneralKitsCooldown
	fraction:RemoveResources(ResourcesNeeded)
	self:GiveKit(kitGrade)
end

function PLAYER:GetFraction()
	return rp.Fractions[rp.teams[self:GetJob()].category]
end

function ClearAllResources()
	for _, frac in pairs(rp.Fractions) do
		frac:RemoveResources(frac:GetResources())
	end
end

-----------------------------------------------
------------------ Фракции --------------------
-----------------------------------------------
hook.Add( "InitPostEntity", "rp.Fractions.InitSpawn", function()

	Fraction:Create("Поместье “Блэйк” Округа “Asheville”")
		:CreateEntity(
			'models/props/de_prodigy/prodcratesb.mdl',
			Vector(-9905.628906, 9613.624023, 236.413330),
			Angle(-0.003, -179.923, -0.051)
		)

	Fraction:Create("Полицейский департамент “Asheville”")
		:CreateEntity(
			'models/props/de_prodigy/ammo_can_01.mdl',
			Vector(-11662.347656, -2284.101562, 5.365740),
			Angle(0.025, 90.000, -0.017)
		)

	Fraction:Create("Бандиты города “Ashville”")
		:CreateEntity(
			'models/props/cs_office/shelves_metal1.mdl',
			Vector(-5868.592285, -12695.365234, -6.535003),
			Angle(-0.000, 179.980, -0.026)
		)
end)

-----------------------------------------------
------------------ Таймеры --------------------
-----------------------------------------------

timer.Create("rp.Fractions.DBUpdateTimer", 60, 0, function()
	UpdateFractionResourcesDB()
end)

function SyncronizeFractionResourcesCounter()
	for name, fraction in pairs(rp.Fractions) do
		if fraction.NPC then
			fraction.NPC:SetNVar('FractionResources', fraction:GetResources(), NETWORK_PROTOCOL_PUBLIC)
		end
	end
end

timer.Create("rp.Fractions.SyncronizeDataWithClients", 10, 0, function()
	SyncronizeFractionResourcesCounter()
end)

timer.Create( "rp.Fractions.MainTimer", PayDayTimer, 0, function()
	for name, obj in pairs(rp.Fractions) do
		obj:PayDay()
	end
end)

-----------------------------------------------
------------------ Сеть -----------------------
-----------------------------------------------
hook.Add( "mcs_npcSpawned", "rp.Fractions.AddNPCs", function()
	for name, fraction in pairs(rp.Fractions) do
		for npcname, npc in pairs(MCS.Spawns) do
			if npc.category and npc.category == name then
				fraction.NPC = npc.Entity
				npc.Entity:SetNVar('FractionResources', 0, NETWORK_PROTOCOL_PUBLIC)
				break
			end
		end
	end
end)

net.Receive("rp.Fractions.Network", function(len, ply)
	local kitGrade = net.ReadUInt(3)
	ply:TryToGetKit(kitGrade)
end)






-----------------------------------------------
------------------ Хуки -----------------------
-----------------------------------------------

------------Пропы за ресурсы----------------
hook.Add('PlayerSpawnProp', 'rp.Fractions.PlayerSpawnProp', function(pl, mdl)
	if pl:IsSuperAdmin() then return true end

	local fraction = pl:GetFraction()
	--if pl:GetJob() == 1 then
		if not pl:HaveItem(INV_ENTITY, "toolset") then
			pl:SendSystemMessage("Строительство", "У вас нет инструментов для строительства!")
			return false
		end

		if pl:HaveItem(INV_ENTITY, "building_resources") then
			pl:RemoveItem(INV_ENTITY, "building_resources", 1)
			pl:SendSystemMessage("Строительство", "Вы сконструировали предмет, осталось " .. pl:GetItemCount(INV_ENTITY, "building_resources") .. " ресурса.")
			return true
		else
			pl:SendSystemMessage("Строительство", "В вашем инвентаре нет строительных ресурсов!")
			return false
		end
	-- elseif fraction ~= nil then
	-- 	local FractionResources = fraction:GetResources()
	-- 	if FractionResources < 1 then
	-- 		pl:SendSystemMessage("Оповещение группировки", "Не хватает ресурсов группировки!")
	-- 		return false
	-- 	end
	-- 	fraction:RemoveResources(1)
	-- 	pl:SendSystemMessage("Оповещение группировки", "Вы создали проп за 1 ресурс, остаток: " .. fraction:GetResources())
	-- 	return true
	-- else
	-- 	DarkRP.notify(pl, 1, 4, "Вам не доступно создание пропов")
	-- 	return false
	-- end

end)

hook.Add('PlayerSpawnedProp', 'rp.Fractions.PlayerSpawnedProp', function(pl, mdl, ent)
	local fraction = pl:GetFraction()
	if fraction then

		-- ent.FractionSpawned = true
		ent:SetNVar("PropFraction", fraction.Name, NETWORK_PROTOCOL_PUBLIC)


		-- fraction.Props[#fraction.Props+1] = content

		-- db:Query("UPDATE rp_fractionresources SET data=? WHERE Name=?;", util.TableToJSON(fraction.Props), fraction:GetName())
	end
end)

hook.Add('PostPlayerDeath', 'rp.Fractions.PlayerDied', function(ply)
	local fraction = ply:GetFraction()
	if fraction ~= nil then fraction:MemberDied() end
end)



-----------------------------------------------
---------------Для сохранения пропов-----------
-----------------------------------------------
function PropGetEntTable( ent )

	if !ent or !ent:IsValid() then return false end

	local content = {}
	content.Class = ent:GetClass()
	content.Pos = ent:GetPos()
	content.Angle = ent:GetAngles()
	content.Model = ent:GetModel()
	content.Skin = ent:GetSkin()
	//content.Mins, content.Maxs = ent:GetCollisionBounds()
	content.ColGroup = ent:GetCollisionGroup()
	content.Name = ent:GetName()
	content.ModelScale = ent:GetModelScale()
	content.Color = ent:GetColor()
	content.Material = ent:GetMaterial()
	content.Solid = ent:GetSolid()
	content.RenderMode = ent:GetRenderMode()
	content.PropID = nil

	-- if Properties.SpecialENTSSave[ent:GetClass()] != nil and isfunction(Properties.SpecialENTSSave[ent:GetClass()]) then

	-- 	local othercontent = Properties.SpecialENTSSave[ent:GetClass()](ent)
	-- 	if not othercontent then return false end
	-- 	if othercontent != nil and istable(othercontent) then
	-- 		table.Merge(content, othercontent)
	-- 	end

	-- end

	if ( ent.GetNetworkVars ) then
		content.DT = ent:GetNetworkVars()
	end

	local sm = ent:GetMaterials()
	if ( sm and istable(sm) ) then

		for k, v in pairs( sm ) do

			if ( ent:GetSubMaterial( k )) then

				content.SubMat = content.SubMat or {}
				content.SubMat[ k ] = ent:GetSubMaterial( k )

			end

		end

	end

	local bg = ent:GetBodyGroups()
	if ( bg ) then

		for k, v in pairs( bg ) do

			if ( ent:GetBodygroup( v.id ) > 0 ) then

				content.BodyG = content.BodyG or {}
				content.BodyG[ v.id ] = ent:GetBodygroup( v.id )

			end

		end

	end

	if ent:GetPhysicsObject() and ent:GetPhysicsObject():IsValid() then
		content.Frozen = !ent:GetPhysicsObject():IsMoveable()
	end

	if content.Class == "prop_dynamic" then
		content.Class = "prop_physics"
	end

	--content.Table = Properties.UselessContent( ent:GetTable() )

	return content

end

function SpawnPropFromDatabase( data, fraction)
	-- if data.Class == "prop_physics" and data.Frozen then
	-- 	data.Class = "prop_dynamic" -- Can reduce lags
	-- end

	local ent = ents.Create(data.Class)
	if !ent then return false end
	if not ent:IsVehicle() then if not ent:IsValid() then return false end end
	ent:SetPos( data.Pos or Vector(0, 0, 0) )
	ent:SetAngles( data.Angle or Angle(0, 0, 0) )
	ent:SetModel( data.Model or "models/error.mdl" )
	ent:SetSkin( data.Skin or 0 )
	//ent:SetCollisionBounds( ( data.Mins or 0 ), ( data.Maxs or 0 ) )
	ent:SetCollisionGroup( data.ColGroup or 0 )
	ent:SetName( data.Name or "" )
	ent:SetModelScale( data.ModelScale or 1 )
	ent:SetMaterial( data.Material or "" )
	ent:SetSolid( data.Solid or 6 )
	ent.PropID = data.PropID

	-- if Properties.SpecialENTSSpawn[data.Class] != nil and isfunction(Properties.SpecialENTSSpawn[data.Class]) then
	-- 	Properties.SpecialENTSSpawn[data.Class](ent, data.Other)
	-- else
	ent:Spawn()
	-- end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end
    constraint.RemoveAll(ent)

	ent:SetRenderMode( data.RenderMode or RENDERMODE_NORMAL )
	ent:SetColor( data.Color or Color(255, 255, 255, 255) )

	if data.EntityMods ~= nil and istable(data.EntityMods) then -- OLD DATA
		if data.EntityMods.material then
			ent:SetMaterial( data.EntityMods.material["MaterialOverride"] or "")
		end
		if data.EntityMods.colour then
			ent:SetColor( data.EntityMods.colour.Color or Color(255, 255, 255, 255))
		end
	end

	if data.DT then
		for k, v in pairs( data.DT ) do
			if ( data.DT[ k ] == nil ) then continue end
			if !isfunction(ent[ "Set" .. k ]) then continue end
			ent[ "Set" .. k ]( ent, data.DT[ k ] )
		end
	end

	if data.BodyG then
		for k, v in pairs( data.BodyG ) do
			ent:SetBodygroup( k, v )
		end
	end


	if data.SubMat then
		for k, v in pairs( data.SubMat ) do
			if type(k) != "number" or type(v) == "string" then continue end
			ent:SetSubMaterial( k, v )

		end
	end

	-- ent:CPPISetOwner(ply)
	-- ent.ItemOwner = ply
	-- ent:SetNVar('PropPropertyID', propID, NETWORK_PROTOCOL_PUBLIC)
	-- ent.PropertiesProp = true
	ent:SetNVar("PropFraction", fraction.Name, NETWORK_PROTOCOL_PUBLIC)
	ent:SetNVar("PropFractionSave", true, NETWORK_PROTOCOL_PUBLIC)
end


--Function for saving prop in bd and array
--
-- Command for prop saving
--
rp.AddCommand('/savefrprop', function(pl, text, args)
	local ent = ents.GetByIndex(args[1])
	if (not ent) then return end

	-- if ent:GetNetVar('PropIsOwned') != true then return end
	if ent:GetClass() != "prop_physics" then return end

	local fraction = pl:GetFraction()

	if not fraction then
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
	if (ent:GetNVar("PropFraction") == fraction.Name) and (rp.teams[pl:GetJob()].leader == true) or (rp.teams[pl:GetJob()].subleader == true) then

		local content = PropGetEntTable(ent)
		if not content then return end
		DarkRP.notify(pl, 1, 4, "Вы сохранили проп")
		-- print(#fraction.Props)
		ent.PropID = (#fraction.Props+1)
		content.PropID = (#fraction.Props+1)
		fraction.Props[#fraction.Props+1] = content
		ent:SetNVar("PropFractionSave", true, NETWORK_PROTOCOL_PUBLIC)
		db:Query("UPDATE rp_fractionresources SET props=? WHERE Name=?;", util.TableToJSON(fraction.Props), fraction:GetName())

		return true
	else
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
end)

rp.AddCommand('/unsavefrprop', function(pl, text, args)
	local ent = ents.GetByIndex(args[1])
	if (not ent or ent.PropID) then return end

	if ent:GetNVar('PropFractionSave') != true then return end
	if ent:GetClass() != "prop_physics" then return end

	local fraction = pl:GetFraction()

	if not fraction or fraction.Props == nil then
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
	if (ent:GetNVar("PropFraction") == fraction.Name) and (rp.teams[pl:GetJob()].leader == true) or (rp.teams[pl:GetJob()].subleader == true) then
		DarkRP.notify(pl, 1, 4, "Вы отменили сохранение пропа")
		ent:SetNVar("PropFractionSave", false, NETWORK_PROTOCOL_PUBLIC)
		fraction.Props[ent.PropID] = nil
		db:Query("UPDATE rp_fractionresources SET props=? WHERE Name=?;", util.TableToJSON(fraction.Props), fraction:GetName())

		return true
	else
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
end)

rp.AddCommand('/removefrprop', function(pl, text, args)
	local ent = ents.GetByIndex(args[1])
	if (not ent) then return end

	if ent:GetNVar('PropFractionSave') != false then return end
	if ent:GetClass() != "prop_physics" then return end

	local fraction = pl:GetFraction()

	if not fraction then
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
	if (ent:GetNVar("PropFraction") == fraction.Name) and (rp.teams[pl:GetJob()].leader == true) or (rp.teams[pl:GetJob()].subleader == true) then
		ent:Remove()
		return true
	else
		DarkRP.notify(pl, 1, 4, "Вы не можете выполнить данное действие")
		return false
	end
end)


function FractionSpawnProps(obj)
	-- for k, v in pairs(ents.GetAll()) do
	-- 	if v:GetNVar("PropFractionSave") == true then v:Remove() end
	-- end
	for k, v in pairs(obj.Props) do
		SpawnPropFromDatabase(v, obj)
	end
end


hook.Add( "InitPostEntity", "rp.Fractions.InitSpawnProps", function()
	for name, obj in pairs(rp.Fractions) do
		if obj.DataInitialized ~= true then continue end
		FractionSpawnProps(obj)
	end
end)
