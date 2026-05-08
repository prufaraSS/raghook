if CLIENT then
    CreateClientConVar("rm_hook_client_enable",1,true,true,"Toggles hook functionality for you.",0,1)
    CreateClientConVar("rm_hook_client_hook_default",1,true,true,"If one, on ragdollize you auto-equip hooks. If zero, you're in grabbing mode.",0,1)
else

require("ragmod")

CreateConVar("rm_ragdoll_mass", 200, FCVAR_NEVER_AS_STRING, "How much ragdoll weight. Too low makes ragdoll feel like a feather, and too much makes hooks pull, fedhoria moves and ragmod movement too weak.", 1)
local speed = CreateConVar("rm_hook_speed", 200, FCVAR_NEVER_AS_STRING, "Changes the speed of hook attraction.")
local constant = CreateConVar("rm_hook_constant", 800, FCVAR_NEVER_AS_STRING, "Changes the constant of hook.")
local damping = CreateConVar("rm_hook_damping", 250, FCVAR_NEVER_AS_STRING, "Changes the damping of hook.")
local hook_material = CreateConVar("rm_hook_material", "cable/rope", 0, "Sets material of rope.")
CreateConVar("rm_hook_enable", 1, FCVAR_NEVER_AS_STRING, "Enables rope shoot")
local length = CreateConVar("rm_hook_length", 5000, FCVAR_NEVER_AS_STRING, "Available distance for hook")
local airaccelerate = CreateConVar("rm_hook_airacceleration", 100, FCVAR_NEVER_AS_STRING, "The air movement power while grappling")

cvars.AddChangeCallback("rm_hook_enable", function(_,_,n)
	if n == 1 then
		hook.Add("RM_RagdollReady","ragmod_on_ragdoll", rm_hook_ragdoll)
		hook.Add("KeyPress","ragmod_grabblehook", rm_hook_on_press)
		hook.Add("KeyRelease", "ragmod_grapplehook", rm_hook_on_release)
	else
		hook.Remove("RM_RagdollReady","ragmod_on_ragdoll")
		hook.Remove("KeyPress","ragmod_grabblehook")
		hook.Remove("KeyRelease", "ragmod_grapplehook")
	end
end)

local shootsound = "Weapon_Pistol.NPC_Single"
local hitsound = "Metal.SawbladeStick"
local returnsound = "garrysmod/balloon_pop_cute.wav"
local hooksreadysound = "Player.WeaponSelected"
local hooksholstersound = "Player.WeaponSelectionClose"

if file.Exists("","tf") then
	shootsound = "WeaponGrapplingHook.Shoot"
	hitsound = "WeaponGrapplingHook.ImpactDefault"
	returnsound = "WeaponGrapplingHook.ReelStop"
end

local key_attack, key_attack2

local ropes = {}

timer.Create("ropes_pull", 0.1, 0, function()
	for _,v in pairs(ropes) do
		if IsValid(v.constr) then
			local kv = v.rope:GetKeyValues()
			v.rope:Fire("SetLength", math.max(kv.Length - kv.speed, 0))
			v.constr:Fire("SetSpringLength", math.max(kv.Length - kv.speed,0))
		end
	end
end)

function clear_ropes()
	local removal = {}
	for k,v in pairs(ropes) do
		if not IsValid(v.constr) then
			table.remove(ropes,k)
		end
	end
end

function create_elastic(bone, rag, trace)
	local Constr, Rope = constraint.Winch(
		nil,
		rag,
		trace.Entity,
		bone,
		trace.PhysicsBone,
		Vector(3,0,0),
		trace.HitPos - trace.Entity:GetPos(),
		1,
		0,
		0,
		1024,
		1024,
		hook_material:GetString(),
		true,
		color_white
	)
	Rope:SetKeyValue("speed", speed:GetInt())
	Constr:Fire("SetSpringConstant", constant:GetInt())
	Constr:Fire("setSpringDamping", damping:GetInt())
	return {
		constr = Constr,
		rope = Rope
	}
end


local hooked_players = RecipientFilter()

function rm_hook_ragdoll(ragdoll, owner)
	local bones = ragdoll:GetPhysicsObjectCount()
	local mass_sum = 0
	for i = 0, bones - 1 do
		local bone = ragdoll:GetPhysicsObjectNum(i)
		if bone:IsValid() then
			mass_sum = mass_sum + bone:GetMass()
		end
	end
	local convar = GetConVar("rm_ragdoll_mass"):GetFloat()
	for i = 0, bones - 1 do
		local bone = ragdoll:GetPhysicsObjectNum(i)
		if bone:IsValid() then
			bone:SetMass(bone:GetMass() / mass_sum * convar)
		end
	end
	
	ragdoll.grapples = {}
	ragdoll.ragmod_enable_hooks = owner:GetInfoNum("rm_hook_client_enable",1) == 1
	ragdoll.ragmod_equipped_hooks = owner:GetInfoNum("rm_hook_client_hook_default",1) == 1
	if not ragdoll.ragmod_equipped_hooks then return end
	if ragdoll.ragmod_enable_hooks then
		timer.Simple(0.11,function()
			owner:CrosshairEnable()
		end)
	end
end

function rm_hook_on_press(plr, key)
	local key_attack = bit.band(key,1) == 1
	local key_attack2 = bit.band(key,2048) == 2048
	local key_toggle = bit.band(key,8192) == 8192
	if not key_attack and not key_attack2 and not key_toggle then return end
	local rag = ragmod:GetRagmodRagdoll(plr)
	if not IsValid(rag) or not plr:Alive() or not rag.ragmod_enable_hooks then return end
	local hook_equipped = rag.ragmod_equipped_hooks
	if key_attack and hook_equipped then
		rag.ragmod_current_bone_num = rag:LookupBone("ValveBiped.Bip01_L_Hand")
		plr.RagmodInputState.Reach.ArmLeft = false
	elseif key_attack2 and hook_equipped then
		rag.ragmod_current_bone_num = rag:LookupBone("ValveBiped.Bip01_R_Hand")
		plr.RagmodInputState.Reach.ArmRight = false
	elseif key_toggle then
		rag.ragmod_equipped_hooks = not rag.ragmod_equipped_hooks
		if rag.ragmod_equipped_hooks then
			plr:CrosshairEnable()
			rag:EmitSound(hooksreadysound)
		else
			plr:CrosshairDisable()
			rag:EmitSound(hooksholstersound)
		end
		return
	end
	if not hook_equipped then return end
	rag.ragmod_grapple_bonepos = rag:GetBonePosition(rag.ragmod_current_bone_num)
	local trace = util.QuickTrace(rag.ragmod_grapple_bonepos,plr:EyeAngles():Forward()*5000,rag)
	if not trace.Hit or trace.HitSky then return end
	rag.grapples[rag.ragmod_current_bone_num] = create_elastic(rag:TranslateBoneToPhysBone(rag.ragmod_current_bone_num), rag, trace)
	table.insert(ropes, rag.grapples[rag.ragmod_current_bone_num])
	rag:EmitSound(shootsound)
	EmitSound(hitsound, trace.HitPos, trace.Entity:EntIndex())
	hooked_players:AddPlayer(plr)
end

function rm_hook_on_release(plr, key)
	local key_attack = bit.band(key,1) == 1
	local key_attack2 = bit.band(key,2048) == 2048
	if not key_attack and not key_attack2 then return end
	local rag = ragmod:GetRagmodRagdoll(plr)
	if not IsValid(rag) or not plr:Alive() then return end
	local left_arm = rag:LookupBone("ValveBiped.Bip01_L_Hand")
	local right_arm = rag:LookupBone("ValveBiped.Bip01_R_Hand")
	if key_attack and rag.grapples[left_arm] and IsValid(rag.grapples[left_arm].constr) then
		rag.grapples[left_arm].constr:Remove()
	elseif key_attack2 and rag.grapples[right_arm] and IsValid(rag.grapples[right_arm].constr) then
		rag.grapples[right_arm].constr:Remove() 
	else
		return
	end
	if not rag.grapples[left_arm] or not IsValid(rag.grapples[left_arm]) and not rag.grapples[right_arm] or not IsValid(rag.grapples[right_arm]) then
	    hooked_players:RemovePlayer(plr)
	end
	clear_ropes()
	rag:EmitSound(returnsound)
end

local right = Angle(0, -90, 0)
function rm_hook_movement()
    for id in pairs(hooked_players:GetPlayers()) do
	local plr = Entity(id)
	local forward = 0
	if plr:KeyDown(IN_FORWARD) then forward = 1 end
	if plr:KeyDown(IN_BACK) then forward = forward - 1 end
	local sideway = 0
	if plr:KeyDown(IN_MOVERIGHT) then sideway = 1 end
	if plr:KeyDown(IN_MOVELEFT) then sideway = sideway - 1 end
	local rag = ragmod:GetRagmodRagdoll(plr)
	if not rag or not IsValid(rag) or not plr or not IsValid(plr) then
	    hooked_players:RemovePlayer(plr)
	    continue
	end
	local boneid = rag:LookupBone("ValveBiped.Bip01_Spine")
	rag:GetPhysicsObjectNum(rag:TranslateBoneToPhysBone(boneid)):AddVelocity(plr:GetAimVector() * forward * airaccelerate:GetInt())
	local aim_right = plr:GetAimVector()
	aim_right:Rotate(right)
	rag:GetPhysicsObjectNum(rag:TranslateBoneToPhysBone(boneid)):AddVelocity(aim_right * sideway * airaccelerate:GetInt())
    end
end

hook.Add("RM_RagdollReady","ragmod_on_ragdoll", rm_hook_ragdoll)
hook.Add("KeyPress","ragmod_grabblehook", rm_hook_on_press)
hook.Add("KeyRelease", "ragmod_grapplehook", rm_hook_on_release)
hook.Add("Think","ragmod_hook_movement", rm_hook_movement)

end
