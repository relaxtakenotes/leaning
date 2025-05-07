local flags = CLIENT and {FCVAR_REPLICATED} or {FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY}
local concommand_flags = {FCVAR_CLIENTCMD_CAN_EXECUTE}

local lean_amount = CreateConVar("sv_lean_amount", 16, flags)
local ron_lean_speed = CreateConVar("sv_lean_speed_ron", 1, flags)
local general_lean_speed = CreateConVar("sv_lean_speed_general", 1, flags)
local unpredicted = CreateConVar("sv_lean_unpredicted", 0, flags, "Restores some compatibility with mods that also alter the view offset.")
local debugmode = CreateConVar("sv_lean_debug", 0, flags, "a buncha shit")
local notify = CreateConVar("sv_lean_notify", 0, flags, "a buncha shit")
local allow_crouch_leans = CreateConVar("sv_lean_allowcrouch", 1, flags)
local always_allow_leaning = CreateConVar("sv_lean_always_allow_leaning", 0, flags)
local auto_in_sights = CreateConVar("cl_lean_auto_insights", 0, 1)
local interp = CreateConVar("cl_lean_interp_ratio", 2, flags, nil, 1)

local hull_size_4 = Vector(4, 4, 4)
local hull_size_5 = Vector(5, 5, 5)

local hull_size_4_negative = Vector(-4, -4, -4)
local hull_size_5_negative = Vector(-5, -5, -5)

local SP = game.SinglePlayer()

local halt_leaning = true

local binds = {
    {"_cl_lean_right_key_hold", "Lean Right (Hold)", "leaning_right", "hold"},
    {"_cl_lean_left_key_hold", "Lean Left (Hold)", "leaning_left", "hold"},

    {"_cl_lean_right_key_toggle", "Lean Right (Toggle)", "leaning_right", "toggle"},
    {"_cl_lean_left_key_toggle", "Lean Left (Toggle)", "leaning_left", "toggle"},

    {"_cl_lean_auto_key_toggle", "Lean Auto (Toggle)", "leaning_auto", "toggle"},
    {"_cl_lean_auto_key_hold", "Lean Auto (Hold)", "leaning_auto", "hold"},

    {"_cl_lean_ron_key_toggle", "Lean RON (Toggle)", "leaning_ron", "toggle"},
    {"_cl_lean_ron_key_hold", "Lean RON (Hold)", "leaning_ron", "hold"}
}

local function bool_to_str(bool)
    if bool then return "On" else return "Off" end
end

local function get_in_sights(ply) -- arccw, arc9, tfa, mgbase, fas2 works
    if !auto_in_sights:GetBool() then return false end
    local weapon = ply:GetActiveWeapon()
    return ply:KeyDown(IN_ATTACK2) or (weapon.GetInSights and weapon:GetInSights()) or (weapon.ArcCW and weapon:GetState() == ArcCW.STATE_SIGHTS) or (weapon.GetIronSights and weapon:GetIronSights())
end

hook.Add("PlayerButtonDown", "leaning_keys", function(ply, button)
    for i, data in ipairs(binds) do
        local info_name = data[1]
        local pretty_name = data[2]
        local network_name = data[3]
        local typee = data[4]

        local need_to_press = ply:GetInfoNum(info_name, -1)

        if button == need_to_press then
            if typee == "hold" then
                ply:SetNW2Var(network_name, true)
                if notify:GetBool() then ply:ChatPrint("[Leaning] Enabled "..pretty_name) end
            end

            if typee == "toggle" then
                local state = not ply:GetNW2Var(network_name, false)
                ply:SetNW2Var(network_name, state)

                if notify:GetBool() then ply:ChatPrint("[Leaning] Toggled "..pretty_name..": "..bool_to_str(state)) end

                for j, j_data in ipairs(binds) do
                    if j_data[4] == "toggle" and network_name != j_data[3] then
                        ply:SetNW2Var(j_data[3], false)
                    end
                end
            end
        end
    end
end)

hook.Add("PlayerButtonUp", "leaning_keys", function(ply, button)
    for i, data in ipairs(binds) do
        local info_name = data[1]
        local pretty_name = data[2]
        local network_name = data[3]
        local typee = data[4]

        local need_to_press = ply:GetInfoNum(info_name, -1)

        if button == need_to_press then
            if typee == "hold" then
                ply:SetNW2Var(network_name, false)
                if notify:GetBool() then ply:ChatPrint("[Leaning] Disabled "..pretty_name) end
            end
        end
    end
end)

local function can_lean(ply)
    if !ply:OnGround() then return false end -- no leans in air
    if ply:IsSprinting() and ply:KeyDown(IN_FORWARD + IN_BACK + IN_MOVELEFT + IN_MOVERIGHT) then return false end -- no leans while sprint, checking if ply is actually moving
    if ply.GetSliding and ply:GetSliding() then return false end -- sliding mods support
    if !allow_crouch_leans:GetBool() and ply:Crouching() then return false end
    local wep = ply:GetActiveWeapon()
    if wep and wep.CanLean == false then return false end -- arc9 has this on some guns, some other mods could add this too
    return true
end

hook.Add("SetupMove", "leaning_main", function(ply, mv, cmd)
    local eyepos = ply:EyePos() - ply:GetNW2Vector("leaning_best_head_offset")
    local angles = cmd:GetViewAngles()

    local canlean = always_allow_leaning:GetBool() or can_lean(ply)

    local fraction = ply:GetNW2Float("leaning_fraction", 0)

    local leaning_left = ply:GetNW2Bool("leaning_left") and canlean
    local leaning_right = ply:GetNW2Bool("leaning_right") and canlean
    local leaning_ron = ply:GetNW2Bool("leaning_ron") and canlean

    local leaning_auto = not (leaning_left or leaning_right or leaning_ron) and (ply:GetNW2Bool("leaning_auto") or get_in_sights(ply)) and canlean

    if debugmode:GetBool() then
        debugoverlay.ScreenText(0.2, 0.2, "leaning_left: "..bool_to_str(leaning_left).." | leaning_right: "..bool_to_str(leaning_right).." | leaning_ron: "..bool_to_str(leaning_ron).." | leaning_auto: "..bool_to_str(leaning_auto), FrameTime() * 5, color_white)
    end

    if leaning_left then
        fraction = Lerp(FrameTime() * 5 * general_lean_speed:GetFloat() + FrameTime(), fraction, -1)
    end

    if leaning_right then
        fraction = Lerp(FrameTime() * 5 * general_lean_speed:GetFloat() + FrameTime(), fraction, 1)
    end

    if leaning_ron then
        if cmd:KeyDown(IN_MOVELEFT) then
            fraction = Lerp(FrameTime() * 3 * ron_lean_speed:GetFloat() * math.abs(fraction - 1) + FrameTime(), fraction, -1)
        elseif cmd:KeyDown(IN_MOVERIGHT) then
            fraction = Lerp(FrameTime() * 3 * ron_lean_speed:GetFloat() * math.abs(fraction + 1) + FrameTime(), fraction, 1)
        end

        cmd:SetForwardMove(0)
        cmd:SetSideMove(0)
        mv:SetSideSpeed(0)
        mv:SetForwardSpeed(0)
    end

    // the worst shit i wrote in a good while
    // max 7 traces per frame... i can do better
    // can also get rid of the gay if nesting
    // and maybe i can stop repeating myself so much

    if leaning_auto then
        local wish_fraction = 0

        local angles_right = angles:Right()
        local angles_forward = angles:Forward()

        local sanity = util.TraceHull({
            start = eyepos,
            endpos = eyepos + angles_forward * lean_amount:GetFloat(),
            mask = MASK_BLOCKLOS,
            filter = ply,
            mins = hull_size_4_negative,
            maxs = hull_size_4
        })

        if sanity.Fraction < 0.99 then
            local left = util.TraceLine({
                start = eyepos,
                endpos = eyepos - angles_right * lean_amount:GetFloat(),
                mask = MASK_BLOCKLOS,
                filter = ply
            })

            local right = util.TraceLine({
                start = eyepos,
                endpos = eyepos + angles_right * lean_amount:GetFloat(),
                mask = MASK_BLOCKLOS,
                filter = ply
            })

            local left_forward = util.TraceLine({
                start = left.HitPos,
                endpos = left.HitPos + angles_forward * lean_amount:GetFloat() * 2,
                mask = MASK_BLOCKLOS,
                filter = ply
            })

            local right_forward = util.TraceLine({
                start = right.HitPos,
                endpos = right.HitPos + angles_forward * lean_amount:GetFloat() * 2,
                mask = MASK_BLOCKLOS,
                filter = ply
            })

            if (left_forward.Fraction != 1 or right_forward.Fraction != 1) and (not left_forward.Hit or not right_forward.Hit) then
                local left_forward = util.TraceLine({
                    start = left.HitPos,
                    endpos = left.HitPos + angles_forward * 10000,
                    mask = MASK_BLOCKLOS,
                    filter = ply
                })

                local right_forward = util.TraceLine({
                    start = right.HitPos,
                    endpos = right.HitPos + angles_forward * 10000,
                    mask = MASK_BLOCKLOS,
                    filter = ply
                })

                if left_forward.HitPos and right_forward.HitPos then
                    // use Distance2DSqr when it's available everywhere
                    local start = left_forward.HitPos
                    local endd = right_forward.HitPos
                    local diff = start - endd
                    local distance = diff.x ^ 2 + diff.y ^ 2

                    if distance <= 4096 then
                        wish_fraction = 0
                    else
                        if left_forward.Fraction > right_forward.Fraction then
                            wish_fraction = -1
                        else
                            wish_fraction = 1
                        end
                    end
                else
                    wish_fraction = 0
                end
            else
                wish_fraction = 0
            end
        else
            wish_fraction = 0
        end

        fraction = Lerp(FrameTime() * 5 * general_lean_speed:GetFloat() + FrameTime(), fraction, wish_fraction)
    end

    if not leaning_left and not leaning_right and not leaning_ron and not leaning_auto then
        fraction = Lerp(FrameTime() * 5 * general_lean_speed:GetFloat() + FrameTime(), fraction, 0)
    end

    if math.abs(fraction) <= 0.0001 then
        fraction = 0
    end

    ply:SetNW2Float("leaning_fraction", fraction)

    local fraction_smooth = ply:GetNW2Float("leaning_fraction_smooth", 0)
    fraction_smooth = Lerp(FrameTime() * 10 + FrameTime(), fraction_smooth, fraction)
    if math.abs(fraction_smooth) <= 0.0001 then
        fraction_smooth = 0
    end
    ply:SetNW2Float("leaning_fraction_smooth", fraction_smooth)

    local amount = fraction_smooth * lean_amount:GetFloat()

    local offsetang = Angle(angles:Unpack())
    offsetang.x = 0
    offsetang:RotateAroundAxis(offsetang:Forward(), amount)

    local offset = Vector(0, -amount, 0)
    offset:Rotate(offsetang)

    if math.abs(fraction_smooth) >= 0.0001 then
        local tr = util.TraceHull({
            start = eyepos,
            endpos = eyepos + offset,
            maxs = hull_size_5,
            mins = hull_size_5_negative,
            mask = MASK_BLOCKLOS,
            filter = ply
        })

        local best_offset = tr.HitPos - eyepos

        ply:SetNW2Vector("leaning_best_head_offset_last", ply:GetNW2Vector("leaning_best_head_offset"))
        ply:SetNW2Vector("leaning_best_head_offset", best_offset)

        local delta = ply:GetNW2Vector("leaning_best_head_offset") - ply:GetNW2Vector("leaning_best_head_offset_last")

        if unpredicted:GetBool() then
            ply:SetCurrentViewOffset(ply:GetCurrentViewOffset() + delta)
            ply:SetViewOffset(ply:GetViewOffset() + delta)
            ply:SetViewOffsetDucked(ply:GetViewOffsetDucked() + delta)
        else
            ply:SetCurrentViewOffset(ply:GetCurrentViewOffset() + delta)
            ply:SetViewOffset(vector_up * ply:GetNW2Float("leaning_height") + best_offset)
            ply:SetViewOffsetDucked(vector_up * ply:GetNW2Float("leaning_height_ducked") + best_offset)
        end
    else
        ply:SetNW2Float("leaning_height", ply:GetViewOffset().z)
        ply:SetNW2Float("leaning_height_ducked", ply:GetViewOffsetDucked().z)
    end
end)

local function angle_offset(new, old)
    local _, ang = WorldToLocal(vector_origin, new, vector_origin, old)

    return ang
end

local function lean_bones(ply, roll)
    if CLIENT then ply:SetupBones() end

    if halt_leaning then
        return
    end

    for _, bone_name in ipairs({"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Head1"}) do
        local bone = ply:LookupBone(bone_name)

        if not bone then continue end

        local ang
        local old_ang

        local matrix = ply:GetBoneMatrix(bone)

        if IsValid(matrix) then
            ang = matrix:GetAngles()
            old_ang = matrix:GetAngles()
        else
            _, ang = ply:GetBonePosition(bone)
            _, old_ang = ply:GetBonePosition(bone)
        end

        if bone_name != "ValveBiped.Bip01_Head1" then
            local eyeangles = ply:EyeAngles()
            eyeangles.x = 0
            local forward = eyeangles:Forward()
            ang:RotateAroundAxis(forward, roll)
        else
            local eyeangles = ply:EyeAngles()
            local forward = eyeangles:Forward()
            ang:RotateAroundAxis(forward, -roll)
        end

        ang = angle_offset(ang, old_ang)

        ply:ManipulateBoneAngles(bone, ang, false)
    end
end

if SERVER then
    hook.Add("Think", "leaning_bend", function()
        for k, ply in ipairs(player.GetAll()) do
            local absolute = math.abs(ply:GetNW2Float("leaning_fraction_smooth"))

            if absolute > 0 then
                ply.stop_leaning_bones = false
            end

            if ply.stop_leaning_bones then continue end

            lean_bones(ply, ply:GetNW2Float("leaning_fraction_smooth") * lean_amount:GetFloat())

            if absolute == 0 then
                ply.stop_leaning_bones = true
            end
        end
    end)

    hook.Add("Think", "draw_hitboxes", function()
        if not debugmode:GetBool() then return end

        for _, ent in pairs(ents.GetAll()) do
            if ent:GetHitboxSetCount() == nil then continue end
            if not ent:IsPlayer() then continue end

            local breaking_lag_comp = false

            ent.prev_pos = ent.current_pos or vector_origin
            ent.current_pos = ent:GetPos()

            if (ent.current_pos - ent.prev_pos):Length2DSqr() > 64 * 64 then
                breaking_lag_comp = true
            end

            for group=0, ent:GetHitboxSetCount() - 1 do
                    for hitbox=0, ent:GetHitBoxCount( group ) - 1 do
                    local matrix = ent:GetBoneMatrix(ent:GetHitBoxBone(hitbox, group))
                    local pos = matrix:GetTranslation()
                    local ang = matrix:GetAngles()
                    local mins, maxs = ent:GetHitBoxBounds(hitbox, group)

                    local color = Color(26, 102, 202)

                    if breaking_lag_comp then
                        color = Color(50, 0, 50, 255)
                    end

                    debugoverlay.SweptBox(pos, pos, mins, maxs, ang, engine.TickInterval() * 3, color)
                end
            end

            debugoverlay.SweptBox(ent:EyePos(), ent:EyePos(), hull_size_4_negative, hull_size_4, angle_zero, engine.TickInterval() * 3, Color(146, 90, 26))
        end
    end)
end

if CLIENT then
    for i, data in ipairs(binds) do
        CreateConVar(data[1], -1, {FCVAR_USERINFO, FCVAR_ARCHIVE})
    end

    local lerped_fraction = 0

    hook.Add("PreRender", "leaning_bend", function()
        for k, ply in ipairs(player.GetAll()) do
            ply.leaning_fraction_true_smooth = Lerp(FrameTime() / (engine.TickInterval() * interp:GetInt()), ply.leaning_fraction_true_smooth or 0, ply:GetNW2Float("leaning_fraction_smooth") * lean_amount:GetFloat())
            local absolute = math.abs(ply.leaning_fraction_true_smooth)

            if absolute <= 0.00001 then ply.leaning_fraction_true_smooth = 0 end

            if absolute > 0 then
                ply.stop_leaning_bones = false
            end

            if ply.stop_leaning_bones then continue end

            lean_bones(ply, ply.leaning_fraction_true_smooth)

            if ply == LocalPlayer() then
                local eyes = ply:EyeAngles()
                eyes.z = ply.leaning_fraction_true_smooth * 0.5
                ply:SetEyeAngles(eyes)
            end

            if absolute == 0 then
                ply.stop_leaning_bones = true
            end
        end
    end)

    local cl_ehw_override = GetConVar("cl_ehw_override")

    hook.Add("CalcViewModelView", "leaning_roll", function(wep, vm, oldpos, oldang, pos, ang)
        if string.StartsWith(wep:GetClass(), "mg_") then return end

        ang.z = ang.z + lerped_fraction

        if (cl_ehw_override and cl_ehw_override:GetBool()) then
            oldang.z = oldang.z + lerped_fraction
        end
    end)

    concommand.Add("cl_lean_bind", function(ply, cmd, args, argstr)
        local scrw = ScrW()
        local scrh = ScrH()
        local ww = scrw / 8
        local wh = scrh / 2

        local m = 5

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Leaning Controls")
        frame:SetPos(scrw / 2 - ww / 2, scrh / 2 - wh / 2)
        frame:SetSize(ww, wh)
        frame:SetVisible(true)
        frame:SetDraggable(true)
        frame:SetSizable(true)
        frame:ShowCloseButton(true)
        frame:MakePopup()

        local l = vgui.Create("DLabel", frame)
        l:Dock(TOP)
        l:DockMargin(m, 0, m, 0)
        l:SetColor(color_white)
        l:SetWrap(true)
        l:SetAutoStretchVertical(true)
        l:SetText("Press backspace to disable the bind.")

        local ltwo = vgui.Create("DLabel", frame)
        ltwo:Dock(TOP)
        ltwo:DockMargin(m, 0, m, m * 2)
        ltwo:SetColor(color_white)
        ltwo:SetWrap(true)
        ltwo:SetAutoStretchVertical(true)
        ltwo:SetText("This wont automatically handle bind collisions, so be aware.")

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)

        local sights = vgui.Create("DCheckBoxLabel", scroll)
        sights:Dock(TOP)
        sights:DockMargin(m, m, m, m*3)
        sights:SetValue(auto_in_sights:GetBool())
        sights:SetConVar("cl_lean_auto_insights")
        sights:SetText("Auto Lean In Sights")
        sights:SetWrap(true)

        for i, data in ipairs(binds) do
            local l = vgui.Create("DLabel", scroll)
            l:Dock(TOP)
            l:DockMargin(m, m, m, 0)
            l:SetColor(color_white)
            l:SetText(data[2])
            
            local binder = vgui.Create("DBinder", scroll)

            local convar_name = data[1]
            local convar = GetConVar(convar_name)

            local bw = ww - 10
            local bh = 30
            local bpx = bw / 4
            local bpy = bh / 2

            binder:SetValue(convar:GetInt())

            binder:SetSize(bw, bh)
            binder:SetPos(bpx, bpy)
            binder:Dock(TOP)
            binder:DockMargin(m, m, m, m)
            function binder:OnChange(num)
                if num == -1 or not num then return end

                if num == KEY_BACKSPACE then
                    convar:SetInt(-1)
                    binder:SetValue(-1)
                    LocalPlayer():ChatPrint("Removed the bind: "..convar_name)
                else
                    convar:SetInt(num)
                    LocalPlayer():ChatPrint("New bound key: "..input.GetKeyName(num).." "..convar_name)
                end
            end
        end
    end)
end

hook.Add("ShutDown", "leaning_sourceengineweloveit", function() 
    halt_leaning = true
end)

hook.Add("InitPostEntity", "leaning_sourceengineweloveit", function() 
    halt_leaning = false
end)