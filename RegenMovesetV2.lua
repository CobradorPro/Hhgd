-- StarterPlayer > StarterPlayerScripts > RegenMovesetV2 (LocalScript)
-- REGENERATION MOVESET V2 — 100% LOCAL, ZERO DEPENDÊNCIAS DE SERVIDOR

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- CONFIGURAÇÕES E PALETA NATURAL (SEM NEON / SEM ILUMINAÇÃO ARTIFICIAL)
--------------------------------------------------------------------------------
local CFG = {
	Cooldown = {
		Jump = 6.5,
		Noclip = 10.0,
		Grapple = 4.5,
		HeadThrow = 7.5,
	},
	Jump = {
		UpVelocity = 118,
		ForwardSpeed = 28,
		CrawlDuration = 3.8,
		CrawlSpeed = 16,
	},
	Noclip = {
		Duration = 3.4,
		Speed = 21,
	},
	Grapple = {
		Range = 155,
		PullSpeed = 92,
	},
	HeadThrow = {
		Speed = 115,
		UpwardBias = 14,
		Gravity = 135,
		MaxFlightTime = 2.3,
		PostImpactWait = 0.55,
	},
	MaxDrops = 36,
}

local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
local QUALITY = IS_MOBILE
	and { strands = 2, segs = 6, frags = 2, muscleBands = 2, vertebrae = 3 }
	or  { strands = 3, segs = 10, frags = 4, muscleBands = 4, vertebrae = 5 }

local COL = {
	Bone       = Color3.fromRGB(224, 214, 196),
	BoneDark   = Color3.fromRGB(182, 170, 152),
	Cartilage  = Color3.fromRGB(202, 188, 174),
	Marrow     = Color3.fromRGB(132, 28, 32),
	MuscleDeep = Color3.fromRGB(115, 22, 28),
	Muscle     = Color3.fromRGB(148, 34, 40),
	MuscleMid  = Color3.fromRGB(168, 48, 52),
	Tendon     = Color3.fromRGB(186, 152, 142),
	Blood      = Color3.fromRGB(108, 14, 20),
	BloodDark  = Color3.fromRGB(72, 10, 14),
	Dust       = Color3.fromRGB(138, 130, 120),
}

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

--------------------------------------------------------------------------------
-- FUNÇÕES MATEMÁTICAS E DE INTERPOLAÇÃO
--------------------------------------------------------------------------------
local PI = math.pi
local TAU = PI * 2

local function clamp01(x)
	return x < 0 and 0 or (x > 1 and 1 or x)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function inv(a, b, x)
	if math.abs(b - a) < 1e-6 then return x >= b and 1 or 0 end
	return clamp01((x - a) / (b - a))
end

local function smooth(a, b, x)
	local t = inv(a, b, x)
	return t * t * (3 - 2 * t)
end

local function smoother(a, b, x)
	local t = inv(a, b, x)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function outCubic(x)
	x = clamp01(x)
	return 1 - (1 - x) ^ 3
end

local function inCubic(x)
	x = clamp01(x)
	return x * x * x
end

local function outQuart(x)
	x = clamp01(x)
	return 1 - (1 - x) ^ 4
end

local function outBack(x, k)
	x = clamp01(x)
	k = k or 1.45
	local i = x - 1
	return 1 + (k + 1) * i * i * i + k * i * i
end

local function spring(x, damp, freq)
	x = clamp01(x)
	if x >= 1 then return 1 end
	damp = damp or 6.0
	freq = freq or 11.5
	return 1 - math.exp(-damp * x) * math.cos(freq * x)
end

local function bell(x)
	return math.sin(PI * clamp01(x))
end

local function rand(a, b)
	return a + math.random() * (b - a)
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-3 and f.Unit or Vector3.new(0, 0, -1)
end

local function safeUnit(v, fallback)
	return v.Magnitude > 1e-4 and v.Unit or (fallback or Vector3.yAxis)
end

--------------------------------------------------------------------------------
-- GERENCIADOR DE LIMPEZA (MAID)
--------------------------------------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ list = {} }, Maid)
end

function Maid:Add(item)
	table.insert(self.list, item)
	return item
end

function Maid:Clean()
	for i = #self.list, 1, -1 do
		local x = self.list[i]
		if typeof(x) == "RBXScriptConnection" then
			x:Disconnect()
		elseif typeof(x) == "Instance" then
			pcall(function() x:Destroy() end)
		elseif type(x) == "function" then
			pcall(x)
		end
	end
	table.clear(self.list)
end

--------------------------------------------------------------------------------
-- ESTADO DO SISTEMA E CICLO DE VIDA
--------------------------------------------------------------------------------
local S = {
	gen = 0,
	busy = nil,
	cd = {},
	char = nil,
	hum = nil,
	root = nil,
	r6 = false,
}

local function alive(gen)
	return S.gen == gen
		and S.char ~= nil
		and S.char.Parent ~= nil
		and S.hum ~= nil
		and S.hum.Health > 0
		and S.root ~= nil
		and S.root.Parent ~= nil
end

local function Animate(ctx, dur, fn)
	local t0 = os.clock()
	local last = t0
	while true do
		if not alive(ctx.gen) then
			error("CANCEL", 0)
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.05)
		last = now
		local elapsed = now - t0
		local p = dur > 0 and clamp01(elapsed / dur) or 1
		local stop = fn(p, elapsed, dt)
		if stop == true or p >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function Wait(ctx, sec)
	Animate(ctx, sec, function() end)
end

--------------------------------------------------------------------------------
-- MAPEAMENTO ANATÔMICO E CONTROLE DE ARTICULAÇÕES (R6 E R15)
--------------------------------------------------------------------------------
local GROUPS_R6 = {
	Torso = { "Torso" },
	Head  = { "Head" },
	LArm  = { "Left Arm" },
	RArm  = { "Right Arm" },
	LLeg  = { "Left Leg" },
	RLeg  = { "Right Leg" },
}

local GROUPS_R15 = {
	Torso = { "LowerTorso", "UpperTorso" },
	Head  = { "Head" },
	LArm  = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	RArm  = { "RightUpperArm", "RightLowerArm", "RightHand" },
	LLeg  = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
	RLeg  = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
}

local function Group(name)
	if not S.char then return {} end
	local map = S.r6 and GROUPS_R6 or GROUPS_R15
	local list = map[name] or {}
	local out = {}
	for _, partName in ipairs(list) do
		local p = S.char:FindFirstChild(partName)
		if p and p:IsA("BasePart") then
			table.insert(out, p)
		end
	end
	return out
end

local function Concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, v in ipairs(list) do
			table.insert(out, v)
		end
	end
	return out
end

local function GetUpperTorso()
	if not S.char then return S.root end
	return S.char:FindFirstChild("UpperTorso") or S.char:FindFirstChild("Torso") or S.root
end

local function GetLowerTorso()
	if not S.char then return S.root end
	return S.char:FindFirstChild("LowerTorso") or S.char:FindFirstChild("Torso") or S.root
end

-- Captura e restaura Motor6Ds para animação procedural compatível com R6 e R15
local function CreatePoseController(ctx)
	local motors = {}
	local origC0 = {}
	local targetOffsets = {}

	local function registerAlias(alias, motor)
		if motor and motor:IsA("Motor6D") then
			motors[alias] = motor
			if not origC0[motor] then
				origC0[motor] = motor.C0
			end
		end
	end

	if S.r6 then
		local root = S.char:FindFirstChild("HumanoidRootPart")
		local torso = S.char:FindFirstChild("Torso")
		if root then
			registerAlias("Root", root:FindFirstChild("RootJoint"))
		end
		if torso then
			registerAlias("Neck", torso:FindFirstChild("Neck"))
			registerAlias("RShoulder", torso:FindFirstChild("Right Shoulder"))
			registerAlias("LShoulder", torso:FindFirstChild("Left Shoulder"))
			registerAlias("RHip", torso:FindFirstChild("Right Hip"))
			registerAlias("LHip", torso:FindFirstChild("Left Hip"))
		end
	else
		local lt = S.char:FindFirstChild("LowerTorso")
		local ut = S.char:FindFirstChild("UpperTorso")
		local head = S.char:FindFirstChild("Head")
		local rua = S.char:FindFirstChild("RightUpperArm")
		local rla = S.char:FindFirstChild("RightLowerArm")
		local lua = S.char:FindFirstChild("LeftUpperArm")
		local lla = S.char:FindFirstChild("LeftLowerArm")
		local rul = S.char:FindFirstChild("RightUpperLeg")
		local rll = S.char:FindFirstChild("RightLowerLeg")
		local lul = S.char:FindFirstChild("LeftUpperLeg")
		local lll = S.char:FindFirstChild("LeftLowerLeg")

		if lt then registerAlias("Root", lt:FindFirstChild("Root")) end
		if ut then registerAlias("Waist", ut:FindFirstChild("Waist")) end
		if head then registerAlias("Neck", head:FindFirstChild("Neck")) end
		if rua then registerAlias("RShoulder", rua:FindFirstChild("RightShoulder")) end
		if rla then registerAlias("RElbow", rla:FindFirstChild("RightElbow")) end
		if lua then registerAlias("LShoulder", lua:FindFirstChild("LeftShoulder")) end
		if lla then registerAlias("LElbow", lla:FindFirstChild("LeftElbow")) end
		if rul then registerAlias("RHip", rul:FindFirstChild("RightHip")) end
		if rll then registerAlias("RKnee", rll:FindFirstChild("RightKnee")) end
		if lul then registerAlias("LHip", lul:FindFirstChild("LeftHip")) end
		if lll then registerAlias("LKnee", lll:FindFirstChild("LeftKnee")) end
	end

	local animateScript = S.char:FindFirstChild("Animate")
	local wasAnimateEnabled = animateScript and animateScript:IsA("LocalScript") and not animateScript.Disabled

	local ctrl = {}

	function ctrl:SuppressDefaultAnimations(suppress)
		if animateScript and animateScript:IsA("LocalScript") then
			animateScript.Disabled = suppress and true or false
		end
		if suppress and S.hum then
			local animator = S.hum:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					pcall(function() track:Stop(0.1) end)
				end
			end
		end
	end

	-- Aplica rotação e translação no espaço padrão da Parte0 (X=Direita, Y=Cima, -Z=Frente)
	function ctrl:SetJoint(alias, posOffset, rotCF, alpha)
		local m = motors[alias]
		if not m or not m.Parent then return end
		local base = origC0[m]
		if not base then return end
		alpha = alpha or 1
		local pOff = (posOffset or Vector3.zero) * alpha
		local rOff = CFrame.identity:Lerp(rotCF or CFrame.identity, alpha)
		local goal = CFrame.new(base.Position + pOff) * rOff * base.Rotation
		targetOffsets[m] = goal
		m.C0 = goal
	end

	function ctrl:Reset(blendTime)
		if not blendTime or blendTime <= 0 then
			for m, c0 in pairs(origC0) do
				if m and m.Parent then
					m.C0 = c0
				end
			end
			table.clear(targetOffsets)
			return
		end
		local snapshot = {}
		for m, _ in pairs(origC0) do
			if m and m.Parent then
				snapshot[m] = m.C0
			end
		end
		local t0 = os.clock()
		while os.clock() - t0 < blendTime and alive(ctx.gen) do
			local a = outCubic((os.clock() - t0) / blendTime)
			for m, startCF in pairs(snapshot) do
				if m and m.Parent and origC0[m] then
					m.C0 = startCF:Lerp(origC0[m], a)
				end
			end
			RunService.RenderStepped:Wait()
		end
		for m, c0 in pairs(origC0) do
			if m and m.Parent then
				m.C0 = c0
			end
		end
	end

	ctx.maid:Add(function()
		for m, c0 in pairs(origC0) do
			if m and m.Parent then
				m.C0 = c0
			end
		end
		if wasAnimateEnabled and animateScript and animateScript.Parent then
			animateScript.Disabled = false
		end
	end)

	return ctrl
end

-- Captura transparência de partes e acessórios
local function CaptureVisibility(parts, includeAccessories)
	local orig = {}
	local partSet = {}

	local function record(inst)
		if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
			if orig[inst] == nil then
				orig[inst] = inst.Transparency
			end
		end
	end

	local function recordTree(rootInst)
		record(rootInst)
		for _, d in ipairs(rootInst:GetDescendants()) do
			record(d)
		end
	end

	for _, p in ipairs(parts) do
		partSet[p] = true
		recordTree(p)
	end

	if includeAccessories and S.char then
		for _, acc in ipairs(S.char:GetChildren()) do
			if acc:IsA("Accessory") then
				local handle = acc:FindFirstChild("Handle")
				if handle then
					local matched = (includeAccessories == true)
					if not matched then
						local weld = handle:FindFirstChildWhichIsA("JointInstance")
						local attachedTo = weld and (weld.Part0 == handle and weld.Part1 or weld.Part0)
						if attachedTo and partSet[attachedTo] then
							matched = true
						end
						if not matched and partSet[S.char:FindFirstChild("Head")] then
							local att = handle:FindFirstChildOfClass("Attachment")
							if att and (att.Name:find("Hat") or att.Name:find("Hair") or att.Name:find("Face") or att.Name:find("Head")) then
								matched = true
							end
						end
					end
					if matched then
						recordTree(handle)
					end
				end
			end
		end
	end

	return orig
end

local function SetVisibility(orig, hiddenFraction, filterFn)
	hiddenFraction = clamp01(hiddenFraction)
	for inst, baseTrans in pairs(orig) do
		if inst and inst.Parent and (not filterFn or filterFn(inst)) then
			local target = baseTrans + (1 - baseTrans) * hiddenFraction
			if math.abs(inst.Transparency - target) > 0.002 then
				inst.Transparency = target
			end
		end
	end
end

--------------------------------------------------------------------------------
-- FÍSICA E EFEITOS NATURAIS (SEM LUZES / SEM NEON / SEM BRILHOS)
--------------------------------------------------------------------------------
local function NewCtx(gen)
	local ctx = {
		gen = gen,
		maid = Maid.new(),
		drops = 0,
	}

	local folder = Instance.new("Folder")
	folder.Name = "RegenV2_LocalFX"
	folder.Parent = Workspace
	ctx.folder = ctx.maid:Add(folder)

	local carrier = Instance.new("Part")
	carrier.Name = "ParticleCarrier"
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.CastShadow = false
	carrier.Transparency = 1
	carrier.Size = Vector3.new(0.2, 0.2, 0.2)
	carrier.Parent = folder
	ctx.carrier = carrier

	-- Poeira física discreta (100% influenciada pela iluminação natural do ambiente, zero emissão própria)
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = TEX_SMOKE
	dust.Color = ColorSequence.new(COL.Dust)
	dust.LightEmission = 0
	dust.LightInfluence = 1
	dust.Rate = 0
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.4, 1.35),
		NumberSequenceKeypoint.new(1, 2.3),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.6, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Lifetime = NumberRange.new(0.55, 1.05)
	dust.Speed = NumberRange.new(2.5, 6.5)
	dust.Drag = 4.5
	dust.SpreadAngle = Vector2.new(82, 18)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-35, 35)
	dust.Parent = carrier
	ctx.dust = dust

	-- Micro-partículas orgânicas opacas (sem brilho)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = TEX_SMOKE
	mist.Color = ColorSequence.new(COL.MuscleDeep, COL.BloodDark)
	mist.LightEmission = 0
	mist.LightInfluence = 1
	mist.Rate = 0
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.7, 0.38),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(0.22, 0.45)
	mist.Speed = NumberRange.new(2, 5.5)
	mist.Drag = 6
	mist.SpreadAngle = Vector2.new(180, 180)
	mist.Rotation = NumberRange.new(0, 360)
	mist.Parent = carrier
	ctx.mist = mist

	return ctx
end

local function FXPart(ctx, color, material, shape, castShadow)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = (castShadow == true)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color or COL.Muscle
	p.Transparency = 1
	p.Size = Vector3.new(0.05, 0.05, 0.05)
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = ctx.folder
	return p
end

local function Put(p, cf, size, trans, color)
	if not p or not p.Parent then return end
	if trans >= 0.995 then
		p.Transparency = 1
		return
	end
	p.Transparency = clamp01(trans)
	p.Size = Vector3.new(
		math.max(size.X, 0.02),
		math.max(size.Y, 0.02),
		math.max(size.Z, 0.02)
	)
	p.CFrame = cf
	if color then
		p.Color = color
	end
end

local function EmitDust(ctx, pos, count)
	if not ctx.carrier or not ctx.carrier.Parent then return end
	ctx.carrier.CFrame = CFrame.new(pos)
	ctx.dust:Emit(IS_MOBILE and math.ceil(count * 0.6) or count)
end

local function EmitTissueMist(ctx, pos, count)
	if not ctx.carrier or not ctx.carrier.Parent then return end
	ctx.carrier.CFrame = CFrame.new(pos)
	ctx.mist:Emit(IS_MOBILE and math.ceil(count * 0.6) or count)
end

-- Gotas e fragmentos físicos naturais (sem luz)
local function SpawnPhysicalDrop(ctx, pos, vel, radius, mat, col)
	if ctx.drops >= CFG.MaxDrops then return end
	ctx.drops += 1
	local d = Instance.new("Part")
	d.Shape = Enum.PartType.Ball
	local sz = radius or rand(0.11, 0.22)
	d.Size = Vector3.new(sz, sz, sz)
	d.Color = col or (math.random() < 0.5 and COL.Blood or COL.MuscleDeep)
	d.Material = mat or Enum.Material.SmoothPlastic
	d.CanCollide = true
	d.CanQuery = false
	d.CanTouch = false
	d.CastShadow = false
	d.Massless = true
	d.CFrame = CFrame.new(pos)
	d.Parent = ctx.folder
	d.AssemblyLinearVelocity = vel or Vector3.new(rand(-5, 5), rand(2, 8), rand(-5, 5))
	TweenService:Create(d, TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.new(0.03, 0.03, 0.03),
		Transparency = 1,
	}):Play()
	Debris:AddItem(d, 1.0)
	task.delay(1.0, function()
		ctx.drops = math.max(0, ctx.drops - 1)
	end)
end

local function ShakeCamera(hum, intensity, duration)
	if not hum then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration and hum.Parent do
			local decay = 1 - (os.clock() - t0) / duration
			local mag = intensity * decay * decay
			hum.CameraOffset = Vector3.new(
				rand(-mag, mag),
				rand(-mag, mag),
				rand(-mag * 0.5, mag * 0.5)
			)
			RunService.RenderStepped:Wait()
		end
		if hum.Parent then
			hum.CameraOffset = Vector3.zero
		end
	end)
end

local function RayParams(ctx, extraIgnore)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local list = { S.char, ctx.folder }
	if extraIgnore then
		for _, item in ipairs(extraIgnore) do
			table.insert(list, item)
		end
	end
	rp.FilterDescendantsInstances = list
	return rp
end

local function GroundBelow(ctx, pos, maxDepth)
	local r = Workspace:Raycast(pos + Vector3.new(0, 2.2, 0), Vector3.new(0, -(maxDepth or 80), 0), RayParams(ctx))
	if r then
		return r.Position, r.Normal, r.Material
	end
	return pos - Vector3.new(0, 3.0, 0), Vector3.yAxis, Enum.Material.Concrete
end

--------------------------------------------------------------------------------
-- SISTEMA DE FIBRAS E TENDÕES MUSCULARES (GEOMETRIA PURA)
--------------------------------------------------------------------------------
local function NewTendonBundle(ctx, customCount)
	local B = { strands = {} }
	local nStrands = customCount or QUALITY.strands
	for k = 1, nStrands do
		local isTendon = (k == nStrands)
		local segs = {}
		local col = isTendon and COL.Tendon or (k % 2 == 0 and COL.Muscle or COL.MuscleDeep)
		local mat = isTendon and Enum.Material.Granite or Enum.Material.SmoothPlastic
		for i = 1, QUALITY.segs do
			segs[i] = FXPart(ctx, col, mat)
		end
		B.strands[k] = {
			segs = segs,
			isTendon = isTendon,
			phase = k * 2.09,
			radialOffset = (k - (nStrands + 1) * 0.5) * 0.11,
		}
	end
	return B
end

local function DrawTendonBundle(B, pointA, pointB, sag, waveAmp, thickness, trans)
	local diff = pointB - pointA
	local dist = diff.Magnitude
	if dist < 0.04 or trans >= 0.99 then
		for _, s in ipairs(B.strands) do
			for _, seg in ipairs(s.segs) do
				seg.Transparency = 1
			end
		end
		return {}
	end

	local dir = diff / dist
	local right = dir:Cross(Vector3.yAxis)
	right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
	local up = right:Cross(dir).Unit
	local clock = os.clock()
	local samplePts = {}

	for _, s in ipairs(B.strands) do
		local n = #s.segs
		local prev = pointA
		for i = 1, n do
			local f = i / n
			local env = bell(f)
			local w1 = math.sin(f * PI * 3 + clock * 8.5 + s.phase) * waveAmp * env
			local w2 = math.cos(f * PI * 2 + clock * 6.5 + s.phase) * waveAmp * 0.65 * env
			local pt = pointA
				+ diff * f
				- Vector3.new(0, sag * env, 0)
				+ right * (w1 + s.radialOffset * env)
				+ up * w2
			local mid = (prev + pt) * 0.5
			local segLen = (pt - prev).Magnitude
			local th = (s.isTendon and thickness * 0.65 or thickness) * (1 - 0.28 * env)
			Put(s.segs[i], CFrame.lookAt(mid, pt), Vector3.new(th, th, segLen + th * 0.45), trans)
			samplePts[i] = pt
			prev = pt
		end
	end
	return samplePts
end

--------------------------------------------------------------------------------
-- MOTOR DE RECONSTRUÇÃO ANATÔMICA MULTICAMADAS (QUALIDADE EXTREMA)
--------------------------------------------------------------------------------
--[[
	Cada membro possui sua própria sequência de reconstrução contínua:
	1. Colar / Base de Conexão Proximal (evita peças flutuando)
	2. Estrutura Óssea Interna Crescendo (vértebras, costelas, diáfises ósseas duplas, crânio + mandíbula)
	3. Formação de Segmentos e Anéis de Cartilagem Articular
	4. Camadas Musculares Geométricas (feixes musculares individuais que envolvem o osso)
	5. Expansão de Volume (contração elástica e pulsação orgânica)
	6. Formação da Superfície Externa (fechamento dérmico contínuo da raiz até a extremidade)
	7. Encaixe Preciso + Movimentos Secundários (micro-espasmos, ajuste articular sem cortes)
]]
local function BuildAnatomicalRigForPart(ctx, part, anatomyType)
	local rig = {
		part = part,
		anatomyType = anatomyType,
		bones = {},
		joints = {},
		muscles = {},
		tendons = {},
		skin = nil,
	}

	-- 1. Estrutura Óssea e Cartilagens conforme o tipo do membro
	if anatomyType == "Torso" then
		-- Coluna vertebral segmentada + arcos costais geométricos
		local vCount = QUALITY.vertebrae
		for i = 1, vCount do
			table.insert(rig.bones, FXPart(ctx, i % 2 == 0 and COL.Bone or COL.BoneDark, Enum.Material.Slate))
		end
		-- Costelas / Placas Torácicas Esquerda e Direita + Esterno
		for i = 1, 3 do
			table.insert(rig.joints, FXPart(ctx, COL.Cartilage, Enum.Material.Slate))
		end
	elseif anatomyType == "Head" then
		-- Eixo cervical + Caixa craniana superior + Mandíbula articulada inferior
		table.insert(rig.bones, FXPart(ctx, COL.BoneDark, Enum.Material.Slate)) -- Coluna cervical
		table.insert(rig.bones, FXPart(ctx, COL.Bone, Enum.Material.Slate))     -- Abóbada craniana
		table.insert(rig.bones, FXPart(ctx, COL.BoneDark, Enum.Material.Slate)) -- Mandíbula
		table.insert(rig.joints, FXPart(ctx, COL.Cartilage, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder))
	elseif anatomyType == "Arm" or anatomyType == "Leg" then
		-- Epífise proximal + 2 hastes ósseas paralelas (ex: tíbia/fíbula ou rádio/ulna) + epífise distal
		table.insert(rig.bones, FXPart(ctx, COL.Bone, Enum.Material.Slate))     -- Osso principal
		table.insert(rig.bones, FXPart(ctx, COL.BoneDark, Enum.Material.Slate)) -- Osso secundário
		table.insert(rig.joints, FXPart(ctx, COL.Cartilage, Enum.Material.Slate)) -- Junta proximal
		table.insert(rig.joints, FXPart(ctx, COL.Cartilage, Enum.Material.Slate)) -- Junta distal
	else
		table.insert(rig.bones, FXPart(ctx, COL.Bone, Enum.Material.Slate))
		table.insert(rig.joints, FXPart(ctx, COL.Cartilage, Enum.Material.Slate))
	end

	-- 2. Feixes Musculares Geométricos (envolvem os ossos em quadrantes anatômicos)
	local mCount = QUALITY.muscleBands
	local quadOffsets = {
		Vector3.new(0, 0, -1),
		Vector3.new(0, 0,  1),
		Vector3.new(-1, 0, 0),
		Vector3.new( 1, 0, 0),
	}
	for i = 1, mCount do
		local col = (i % 2 == 1) and COL.Muscle or COL.MuscleDeep
		table.insert(rig.muscles, {
			part = FXPart(ctx, col, Enum.Material.SmoothPlastic),
			dir = quadOffsets[((i - 1) % #quadOffsets) + 1],
			phase = i * 1.57,
			baseCol = col,
		})
	end

	-- 3. Tendões conectores na base
	for i = 1, 2 do
		table.insert(rig.tendons, FXPart(ctx, COL.Tendon, Enum.Material.Granite))
	end

	-- 4. Camada Dérmica / Superfície Externa
	rig.skin = FXPart(ctx, part.Color, part.Material)

	return rig
end

local function DestroyAnatomicalRig(rig)
	for _, p in ipairs(rig.bones) do p:Destroy() end
	for _, p in ipairs(rig.joints) do p:Destroy() end
	for _, m in ipairs(rig.muscles) do m.part:Destroy() end
	for _, t in ipairs(rig.tendons) do t:Destroy() end
	if rig.skin then rig.skin:Destroy() end
end

local function UpdateAnatomicalRig(ctx, rig, g, origTrans, seed)
	local part = rig.part
	if g <= 0 or not part or not part.Parent then
		for _, p in ipairs(rig.bones) do p.Transparency = 1 end
		for _, p in ipairs(rig.joints) do p.Transparency = 1 end
		for _, m in ipairs(rig.muscles) do m.part.Transparency = 1 end
		for _, t in ipairs(rig.tendons) do t.Transparency = 1 end
		if rig.skin then rig.skin.Transparency = 1 end
		if part and part.Parent and g <= 0 then
			part.Transparency = 1
		end
		return
	end

	local clock = os.clock()
	local sz = part.Size
	local baseCF = part.CFrame
	local aType = rig.anatomyType

	-- Direção de crescimento:
	-- Torso e Head crescem de baixo para cima (+Y); Braços e Pernas crescem do topo/junta para a ponta (-Y)
	local growsUp = (aType == "Torso" or aType == "Head")
	local anchorY = growsUp and (-sz.Y * 0.5) or (sz.Y * 0.5)
	local growSign = growsUp and 1 or -1

	-- Fase 1: Crescimento Ósseo (0.00 -> 0.42)
	local boneProg = smoother(0.0, 0.42, g)
	-- Fase 2: Formação de Segmentos & Cartilagem (0.12 -> 0.52)
	local segProg = smoother(0.12, 0.52, g)
	-- Fase 3: Camadas Musculares Geométricas (0.24 -> 0.72)
	local musProg = inv(0.24, 0.72, g)
	-- Fase 4: Expansão de Volume e Contração (0.45 -> 0.85)
	local volProg = inv(0.45, 0.85, g)
	-- Fase 5: Superfície Externa e Encaixe (0.66 -> 1.00)
	local skinProg = smoother(0.66, 0.96, g)
	local finalLock = smoother(0.88, 1.0, g)

	-- Movimento secundário (tremor orgânico que diminui conforme o encaixe finaliza)
	local instability = (1 - finalLock) * (0.045 * bell(clamp01(g * 1.2)))
	local twitchPitch = math.noise(clock * 4.5, seed) * instability
	local twitchRoll  = math.noise(clock * 4.5, seed + 17) * instability
	local settleSnap  = math.sin(smooth(0.82, 0.96, g) * PI) * 0.035 * (1 - finalLock)
	local workCF = baseCF
		* CFrame.new(0, settleSnap * growSign, 0)
		* CFrame.Angles(twitchPitch, 0, twitchRoll)

	local hideInternal = smooth(0.80, 0.96, g)

	-- ATUALIZA OSSOS E SEGMENTOS POR TIPO DE MEMBRO
	if aType == "Torso" then
		local vCount = #rig.bones
		for i, vPart in ipairs(rig.bones) do
			local vStart = (i - 1) / vCount * 0.35
			local vp = smoother(vStart, vStart + 0.28, g)
			local fracY = (i - 0.5) / vCount
			local yPos = -sz.Y * 0.5 + sz.Y * fracY * boneProg
			local vSize = Vector3.new(sz.X * 0.24 * vp, (sz.Y / vCount) * 0.82 * vp, sz.Z * 0.32 * vp)
			Put(vPart, workCF * CFrame.new(0, yPos, sz.Z * 0.08), vSize, hideInternal)
		end
		-- Arcos costais se abrindo
		for i, rib in ipairs(rig.joints) do
			local rp = spring(inv(0.10 + i * 0.06, 0.50 + i * 0.05, g))
			local yPos = (-0.15 + (i - 1) * 0.26) * sz.Y
			local ribW = sz.X * (0.58 + 0.12 * (3 - i)) * rp
			local ribD = sz.Z * 0.68 * rp
			Put(rib, workCF * CFrame.new(0, yPos, 0), Vector3.new(ribW, sz.Y * 0.13, ribD), hideInternal)
		end

	elseif aType == "Head" then
		local cerv = rig.bones[1]
		local skull = rig.bones[2]
		local jaw = rig.bones[3]
		local neckRing = rig.joints[1]

		-- Eixo cervical subindo do pescoço
		local cLen = sz.Y * 0.55 * boneProg
		Put(cerv, workCF * CFrame.new(0, -sz.Y * 0.5 + cLen * 0.5, 0.05), Vector3.new(sz.X * 0.28, cLen, sz.Z * 0.28), hideInternal)

		-- Crânio expandindo
		local skScale = spring(inv(0.14, 0.52, g))
		Put(skull, workCF * CFrame.new(0, sz.Y * 0.1 * skScale, -0.02),
			Vector3.new(sz.X * 0.72 * skScale, sz.Y * 0.62 * skScale, sz.Z * 0.76 * skScale), hideInternal)

		-- Mandíbula articulada (começa aberta e fecha com encaixe)
		local jawGrow = smoother(0.20, 0.55, g)
		local jawClose = smoother(0.45, 0.78, g)
		local jawAngle = lerp(0.48, 0, jawClose)
		local jawCF = workCF * CFrame.new(0, -sz.Y * 0.22, -sz.Z * 0.06) * CFrame.Angles(jawAngle, 0, 0)
		Put(jaw, jawCF, Vector3.new(sz.X * 0.58 * jawGrow, sz.Y * 0.26 * jawGrow, sz.Z * 0.62 * jawGrow), hideInternal)

		if neckRing then
			Put(neckRing, workCF * CFrame.new(0, -sz.Y * 0.46, 0) * CFrame.Angles(0, 0, PI * 0.5),
				Vector3.new(0.08, sz.X * 0.55 * segProg, sz.Z * 0.55 * segProg), hideInternal)
		end

	else
		-- Braços e Pernas: hastes ósseas duplas + epífises articulares
		local bLen = sz.Y * boneProg
		local centerOffset = anchorY + growSign * (bLen * 0.5)
		local b1 = rig.bones[1]
		local b2 = rig.bones[2]
		if b1 then
			Put(b1, workCF * CFrame.new(-sz.X * 0.11, centerOffset, 0),
				Vector3.new(sz.X * 0.22, bLen, sz.Z * 0.26), hideInternal)
		end
		if b2 then
			local b2Len = bLen * smoother(0.08, 0.46, g)
			local center2 = anchorY + growSign * (b2Len * 0.5)
			Put(b2, workCF * CFrame.new(sz.X * 0.12, center2, sz.Z * 0.04),
				Vector3.new(sz.X * 0.16, b2Len, sz.Z * 0.20), hideInternal)
		end
		-- Anéis de cartilagem nas juntas proximal e distal
		local jProx = rig.joints[1]
		local jDist = rig.joints[2]
		if jProx then
			local jp = spring(segProg)
			Put(jProx, workCF * CFrame.new(0, anchorY + growSign * 0.06, 0),
				Vector3.new(sz.X * 0.56 * jp, sz.Y * 0.12, sz.Z * 0.56 * jp), hideInternal)
		end
		if jDist then
			local jd = smoother(0.32, 0.62, g)
			local tipY = anchorY + growSign * bLen
			Put(jDist, workCF * CFrame.new(0, tipY, 0),
				Vector3.new(sz.X * 0.48 * jd, sz.Y * 0.10 * jd, sz.Z * 0.48 * jd), hideInternal)
		end
	end

	-- ATUALIZA TENDÕES DE CONEXÃO PROXIMAL
	for i, tPart in ipairs(rig.tendons) do
		local tp = smoother(0.05, 0.65, g)
		local sideSign = (i == 1) and -1 or 1
		local tLen = sz.Y * 0.42 * tp
		local tY = anchorY + growSign * (tLen * 0.35)
		local tilt = sideSign * 0.14 * (1 - finalLock)
		Put(tPart, workCF * CFrame.new(sideSign * sz.X * 0.26, tY, 0) * CFrame.Angles(0, 0, tilt),
			Vector3.new(sz.X * 0.13, tLen, sz.Z * 0.13), hideInternal)
	end

	-- ATUALIZA CAMADAS MUSCULARES GEOMÉTRICAS E EXPANSÃO DE VOLUME
	if musProg > 0 then
		local mLen = sz.Y * outCubic(musProg)
		local mCenterY = anchorY + growSign * (mLen * 0.5)
		local swell = spring(volProg, 5.5, 10.0)
		local pulse = 1 + 0.045 * math.sin(clock * 12 + seed) * (1 - finalLock)

		for idx, m in ipairs(rig.muscles) do
			local stagger = (idx - 1) * 0.06
			local localM = clamp01((musProg - stagger) / (1 - stagger))
			if localM <= 0 then
				m.part.Transparency = 1
			else
				local radialDist = lerp(0.12, 0.24, swell) * pulse
				local offset = Vector3.new(
					m.dir.X * sz.X * radialDist,
					mCenterY,
					m.dir.Z * sz.Z * radialDist
				)
				local bundleW = (math.abs(m.dir.X) > 0 and sz.X * 0.48 or sz.X * 0.72) * swell * pulse
				local bundleD = (math.abs(m.dir.Z) > 0 and sz.Z * 0.48 or sz.Z * 0.72) * swell * pulse
				local bundleH = mLen * localM * (1 - 0.04 * bell(volProg))
				local col = COL.Marrow:Lerp(m.baseCol, smooth(0, 0.5, localM)):Lerp(COL.MuscleMid, 0.35 * bell(volProg))
				Put(m.part, workCF * CFrame.new(offset), Vector3.new(bundleW, bundleH, bundleD), hideInternal, col)
			end
		end
	else
		for _, m in ipairs(rig.muscles) do
			m.part.Transparency = 1
		end
	end

	-- ATUALIZA SUPERFÍCIE EXTERNA (FECHAMENTO DÉRMICO) E PARTE REAL
	if skinProg > 0 and finalLock < 1 then
		local sLen = sz.Y * outCubic(skinProg)
		local sCenterY = anchorY + growSign * (sLen * 0.5)
		local sWidth = lerp(0.86, 1.0, skinProg)
		local skinColor = COL.MuscleMid:Lerp(part.Color, smoother(0.0, 0.75, skinProg))
		local skinAlpha = lerp(0.25, origTrans, skinProg)
		Put(rig.skin, workCF * CFrame.new(0, sCenterY, 0),
			Vector3.new(sz.X * sWidth, sLen, sz.Z * sWidth), skinAlpha, skinColor)
	else
		rig.skin.Transparency = 1
	end

	-- Transição contínua para a peça real do personagem
	if g >= 0.78 then
		local realReveal = smoother(0.78, 0.96, g)
		part.Transparency = origTrans + (1 - origTrans) * (1 - realReveal)
	else
		part.Transparency = 1
	end
end

-- Executa a reconstrução anatômica coordenada para múltiplos grupos
-- entries: { { parts = {...}, t0 = 0.0, dur = 1.6, anatomy = "Leg"|"Arm"|"Torso"|"Head", stagger = 0.25 }, ... }
local function RebuildAnatomy(ctx, origVis, entries, onFrame)
	local jobs = {}
	local totalDuration = 0

	for eIdx, entry in ipairs(entries) do
		local stagger = entry.stagger or 0.22
		for pIdx, part in ipairs(entry.parts) do
			local startT = entry.t0 + (pIdx - 1) * stagger
			local dur = entry.dur
			local rig = BuildAnatomicalRigForPart(ctx, part, entry.anatomy or "Limb")
			table.insert(jobs, {
				part = part,
				rig = rig,
				t0 = startT,
				dur = dur,
				orig = origVis[part] or 0,
				seed = eIdx * 13.7 + pIdx * 5.3,
				mistFired = false,
				lockFired = false,
			})
			totalDuration = math.max(totalDuration, startT + dur)
		end
	end

	ctx.maid:Add(function()
		for _, j in ipairs(jobs) do
			DestroyAnatomicalRig(j.rig)
		end
	end)

	Animate(ctx, totalDuration, function(_, elapsed, dt)
		for _, j in ipairs(jobs) do
			local g = (elapsed - j.t0) / j.dur
			UpdateAnatomicalRig(ctx, j.rig, g, j.orig, j.seed)

			if not j.mistFired and g >= 0.28 and j.part.Parent then
				j.mistFired = true
				EmitTissueMist(ctx, j.part.Position, 4)
			end
			if not j.lockFired and g >= 0.88 and j.part.Parent then
				j.lockFired = true
				SpawnPhysicalDrop(ctx, j.part.Position, Vector3.new(rand(-3, 3), rand(1, 4), rand(-3, 3)), 0.11)
			end
		end
		if onFrame then
			onFrame(elapsed, totalDuration, dt)
		end
	end)

	for _, j in ipairs(jobs) do
		DestroyAnatomicalRig(j.rig)
		if j.part and j.part.Parent then
			j.part.Transparency = j.orig
		end
	end
end

--------------------------------------------------------------------------------
-- HABILIDADE 1: JUMP (IMPULSO, PERNAS PARA TRÁS, QUEDA FÍSICA, RASTEJAMENTO COM BRAÇOS E INÉRCIA)
--------------------------------------------------------------------------------
local function AbilityJump(ctx)
	local hum, root = S.hum, S.root
	local pose = CreatePoseController(ctx)
	pose:SuppressDefaultAnimations(true)

	local lLeg = Group("LLeg")
	local rLeg = Group("RLeg")
	local legs = Concat(lLeg, rLeg)
	local origLegs = CaptureVisibility(legs, "attached")

	ctx.maid:Add(function()
		SetVisibility(origLegs, 0)
		if root and root.Parent then
			root.Anchored = false
		end
		if hum and hum.Parent then
			hum.PlatformStand = false
			hum.AutoRotate = true
		end
	end)

	local standOffset = S.r6 and 3.0 or (hum.HipHeight + root.Size.Y * 0.5)
	local look = flat(root.CFrame.LookVector)
	local ground0 = GroundBelow(ctx, root.Position)

	-- 1. IMPULSO PREPARATÓRIO ANTES DO SALTO (Agachamento profundo + braços para trás)
	root.Anchored = true
	local startCF = root.CFrame
	Animate(ctx, 0.28, function(p)
		local k = outCubic(p)
		root.CFrame = startCF * CFrame.new(0, -0.95 * k, -0.15 * k) * CFrame.Angles(-0.32 * k, 0, 0)
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(-0.85 * k, 0, 0.18 * k))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(-0.85 * k, 0, -0.18 * k))
		pose:SetJoint("RHip", Vector3.zero, CFrame.Angles(0.65 * k, 0, 0))
		pose:SetJoint("LHip", Vector3.zero, CFrame.Angles(0.65 * k, 0, 0))
		pose:SetJoint("RKnee", Vector3.zero, CFrame.Angles(-0.95 * k, 0, 0))
		pose:SetJoint("LKnee", Vector3.zero, CFrame.Angles(-0.95 * k, 0, 0))
	end)

	-- Explosão muscular de lançamento
	EmitDust(ctx, ground0, 16)
	ShakeCamera(hum, 0.28, 0.25)
	root.Anchored = false
	hum.PlatformStand = true
	hum.AutoRotate = false

	-- Salto de grande altura e força
	local launchVel = look * CFG.Jump.ForwardSpeed + Vector3.new(0, CFG.Jump.UpVelocity, 0)
	root.AssemblyLinearVelocity = launchVel

	-- Impulso de extensão no início da subida
	Animate(ctx, 0.11, function(p)
		local k = outCubic(p)
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(lerp(-0.85, 2.3, k), 0, 0.12))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(lerp(-0.85, 2.3, k), 0, -0.12))
		pose:SetJoint("RHip", Vector3.zero, CFrame.Angles(lerp(0.65, -0.45, k), 0, 0))
		pose:SetJoint("LHip", Vector3.zero, CFrame.Angles(lerp(0.65, -0.45, k), 0, 0))
	end)

	-- 2. PERNAS FICAM PARA TRÁS DURANTE A SUBIDA
	SetVisibility(origLegs, 1)
	local detachedLegs = {}
	local lowerTorso = GetLowerTorso()

	for _, p in ipairs(legs) do
		local clone = p:Clone()
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Motor6D") or d:IsA("Weld") then
				d:Destroy()
			end
		end
		clone.Transparency = origLegs[p] or 0
		clone.Anchored = false
		clone.CanCollide = true
		clone.CanQuery = false
		clone.CanTouch = false
		clone.Massless = false
		clone.CFrame = p.CFrame
		clone.Parent = ctx.folder

		-- As pernas perdem o impulso ascendente e caem para trás com gravidade e rotação natural
		clone.AssemblyLinearVelocity = Vector3.new(launchVel.X * 0.18 + rand(-4, 4), -12 + rand(-6, 2), launchVel.Z * 0.18 + rand(-4, 4))
		clone.AssemblyAngularVelocity = Vector3.new(rand(-7, 7), rand(-4, 4), rand(-7, 7))
		table.insert(detachedLegs, clone)

		-- Selo anatômico no topo da perna desprendida
		local cap = Instance.new("Part")
		cap.Size = Vector3.new(p.Size.X * 0.78, 0.14, p.Size.Z * 0.78)
		cap.Color = COL.MuscleDeep
		cap.Material = Enum.Material.SmoothPlastic
		cap.CanCollide = false
		cap.Massless = true
		cap.CFrame = clone.CFrame * CFrame.new(0, p.Size.Y * 0.5, 0)
		cap.Parent = clone
		local w = Instance.new("WeldConstraint")
		w.Part0 = clone
		w.Part1 = cap
		w.Parent = cap

		local hipPos = (p.CFrame * CFrame.new(0, p.Size.Y * 0.5, 0)).Position
		EmitTissueMist(ctx, hipPos, 6)
		for _ = 1, 4 do
			SpawnPhysicalDrop(ctx, hipPos, Vector3.new(rand(-7, 7), rand(-2, 8), rand(-7, 7)))
		end
	end

	-- Tocos anatômicos no quadril + tendões curtos pendurados durante o voo
	local hipStumpL = FXPart(ctx, COL.MuscleDeep, Enum.Material.SmoothPlastic)
	local hipStumpR = FXPart(ctx, COL.MuscleDeep, Enum.Material.SmoothPlastic)
	local hipBoneL  = FXPart(ctx, COL.Bone, Enum.Material.Slate)
	local hipBoneR  = FXPart(ctx, COL.Bone, Enum.Material.Slate)

	local function UpdateHipStumps(alpha)
		if not lowerTorso or not lowerTorso.Parent then return end
		local cf = lowerTorso.CFrame
		local sx, sy, sz = lowerTorso.Size.X, lowerTorso.Size.Y, lowerTorso.Size.Z
		Put(hipStumpL, cf * CFrame.new(-sx * 0.25, -sy * 0.52, 0), Vector3.new(sx * 0.42, 0.18, sz * 0.78), alpha)
		Put(hipStumpR, cf * CFrame.new( sx * 0.25, -sy * 0.52, 0), Vector3.new(sx * 0.42, 0.18, sz * 0.78), alpha)
		Put(hipBoneL,  cf * CFrame.new(-sx * 0.25, -sy * 0.62, 0), Vector3.new(0.22, 0.28, 0.22), alpha)
		Put(hipBoneR,  cf * CFrame.new( sx * 0.25, -sy * 0.62, 0), Vector3.new(0.22, 0.28, 0.22), alpha)
	end

	-- Fibras se rompendo entre o quadril e as pernas que ficaram para trás (primeiros 0.32s)
	local snapTendonL = NewTendonBundle(ctx, 2)
	local snapTendonR = NewTendonBundle(ctx, 2)

	-- 3. SUBIDA E QUEDA COM FÍSICA CONVINCENTE
	local rp = RayParams(ctx, detachedLegs)
	local landedHit = nil
	local flightStart = os.clock()
	local currentYaw = math.atan2(-look.X, -look.Z)
	local pitchAngle = -0.25
	local rollAngle = 0

	Animate(ctx, 4.5, function(_, elapsed, dt)
		UpdateHipStumps(0)

		-- Fibras esticando e se rompendo das pernas que ficaram para trás
		if elapsed < 0.34 and #detachedLegs >= 2 and lowerTorso then
			local snapAlpha = smooth(0.18, 0.34, elapsed)
			local hL = (lowerTorso.CFrame * CFrame.new(-0.5, -lowerTorso.Size.Y * 0.5, 0)).Position
			local hR = (lowerTorso.CFrame * CFrame.new( 0.5, -lowerTorso.Size.Y * 0.5, 0)).Position
			DrawTendonBundle(snapTendonL, hL, detachedLegs[1].Position, 0.15, 0.22, 0.11, snapAlpha)
			DrawTendonBundle(snapTendonR, hR, detachedLegs[#detachedLegs].Position, 0.15, 0.22, 0.11, snapAlpha)
		else
			DrawTendonBundle(snapTendonL, Vector3.zero, Vector3.zero, 0, 0, 0, 1)
			DrawTendonBundle(snapTendonR, Vector3.zero, Vector3.zero, 0, 0, 0, 1)
		end

		local vel = root.AssemblyLinearVelocity
		local vy = vel.Y

		-- Rotação física aerodinâmica: inclina conforme a parábola do salto e prepara o corpo na descida
		local targetPitch = math.clamp(lerp(-1.35, 0.45, inv(-95, 95, vy)), -1.45, 0.55)
		pitchAngle = lerp(pitchAngle, targetPitch, 1 - math.exp(-dt * 6.5))
		rollAngle = math.sin(elapsed * 5.5) * 0.14 * clamp01(math.abs(vy) / 70)

		-- Mantém orientação física convincente sem travar a velocidade linear
		root.AssemblyAngularVelocity = Vector3.zero
		root.CFrame = CFrame.new(root.Position)
			* CFrame.Angles(0, currentYaw, 0)
			* CFrame.Angles(pitchAngle, 0, rollAngle)

		-- Animação secundária dos braços reagindo ao vento/queda
		local armFlail = math.sin(elapsed * 11) * 0.22
		local armLift = clamp01(-vy / 75)
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(lerp(1.7, 1.15, armLift) + armFlail, 0, 0.35 + 0.2 * armLift))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(lerp(1.7, 1.15, armLift) - armFlail, 0, -0.35 - 0.2 * armLift))
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(lerp(-0.2, 0.45, armLift), 0, 0))

		if math.random() < 0.22 then
			SpawnPhysicalDrop(ctx, hipBoneL.Position, Vector3.new(rand(-2, 2), rand(0, 3), rand(-2, 2)), 0.10)
		end

		-- Detecção de impacto com o solo na descida
		if elapsed > 0.28 and vy <= 2 then
			local castDist = math.max(2.6, math.abs(vy) * dt * 1.45 + 1.8)
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -castDist, 0), rp)
			if hit then
				landedHit = hit
				return true
			end
		end
	end)

	-- 4. ATERRISSAGEM DEITADO COM IMPACTO FÍSICO E DERRAPAGEM
	local groundPos = landedHit and landedHit.Position or GroundBelow(ctx, root.Position)
	local horizVel = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local crawlDir = horizVel.Magnitude > 2 and horizVel.Unit or look

	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	-- CFrame deitado de bruços (barriga para baixo, apoiado nos braços para rastejar)
	local function ProneCF(pos, dir, torsoRoll, torsoPitch, torsoYaw)
		local fDir = flat(dir)
		-- Para ficar deitado de bruços: UpVector da RootPart aponta para frente (fDir), LookVector aponta para cima (Vector3.yAxis)
		local base = CFrame.lookAt(pos, pos + Vector3.yAxis, -fDir)
		return base * CFrame.Angles(torsoPitch or 0, torsoYaw or 0, torsoRoll or 0)
	end

	local impactPos = Vector3.new(root.Position.X, groundPos.Y + 0.68, root.Position.Z)
	EmitDust(ctx, groundPos, 24)
	EmitTissueMist(ctx, impactPos, 10)
	ShakeCamera(hum, 0.55, 0.38)
	for _ = 1, 7 do
		SpawnPhysicalDrop(ctx, impactPos, Vector3.new(rand(-9, 9), rand(3, 10), rand(-9, 9)))
	end

	-- Quique de impacto e derrapagem por inércia no solo
	local skidDist = math.clamp(horizVel.Magnitude * 0.08, 0.6, 2.8)
	local impactStartCF = root.CFrame
	Animate(ctx, 0.32, function(p)
		UpdateHipStumps(0)
		local skid = outCubic(p) * skidDist
		local bounce = math.sin(p * PI) * 0.42 * (1 - p)
		local curGround = GroundBelow(ctx, impactPos + crawlDir * skid, 12)
		local pPos = Vector3.new(impactPos.X + crawlDir.X * skid, curGround.Y + 0.62 + bounce, impactPos.Z + crawlDir.Z * skid)
		local targetProne = ProneCF(pPos, crawlDir, math.sin(p * PI * 2) * 0.08 * (1 - p), -0.08 * (1 - p), 0)
		root.CFrame = impactStartCF:Lerp(targetProne, outCubic(clamp01(p * 1.6)))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(1.35, 0, 0.35))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(1.35, 0, -0.35))
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(-0.55, 0, 0))
	end)

	-- 5. RASTEJAMENTO INTERATIVO COM OS BRAÇOS, ROTAÇÃO DO TORSO E INÉRCIA
	-- Enquanto está sem pernas, o jogador controla direção e velocidade usando os braços
	local crawlPos = Vector3.new(root.Position.X, groundPos.Y + 0.62, root.Position.Z)
	local crawlVel = Vector3.zero
	local crawlPhase = 0
	local lastStrokeSide = 0

	-- Durante a segunda metade do rastejamento, os primeiros tendões e ossos começam a brotar dos quadris
	local earlyTendonL = NewTendonBundle(ctx, 2)
	local earlyTendonR = NewTendonBundle(ctx, 2)

	Animate(ctx, CFG.Jump.CrawlDuration, function(p, elapsed, dt)
		UpdateHipStumps(0)

		-- Desvanece as pernas antigas descartadas ao longe
		for _, c in ipairs(detachedLegs) do
			if c and c.Parent then
				local fade = smooth(0.4, 0.95, p)
				c.Transparency = lerp(0, 1, fade)
				if fade >= 1 then c:Destroy() end
			end
		end

		-- Direção desejada pelo jogador (WASD / Analógico Mobile)
		local moveInput = hum.MoveDirection
		local inputMag = clamp01(moveInput.Magnitude)

		if inputMag > 0.05 then
			local desiredDir = flat(moveInput)
			-- Curva suave da direção do rastejamento
			crawlDir = safeUnit(crawlDir:Lerp(desiredDir, 1 - math.exp(-dt * 7.5)), crawlDir)
		end

		-- Avança o ciclo alternado dos braços proporcionalmente ao comando e à velocidade
		local cycleRate = lerp(0.8, 7.2, inputMag)
		if inputMag > 0.04 then
			crawlPhase += dt * cycleRate
		else
			-- Desacelera suavemente até uma postura de apoio
			crawlPhase += dt * 0.35 * clamp01(crawlVel.Magnitude / CFG.Jump.CrawlSpeed)
		end

		-- Cada braço puxa o corpo alternadamente (Esquerdo em sin > 0, Direito em sin < 0)
		local armWave = math.sin(crawlPhase)
		local pullImpulse = math.abs( math.cos(crawlPhase) ) -- Pico de tração quando a mão puxa o chão

		-- Emite poeira discreta quando cada mão apoia e puxa o chão
		local currentSide = armWave >= 0 and 1 or -1
		if inputMag > 0.15 and currentSide ~= lastStrokeSide then
			lastStrokeSide = currentSide
			local handOffset = crawlDir * 1.3 + crawlDir:Cross(Vector3.yAxis) * (currentSide * 0.75)
			EmitDust(ctx, Vector3.new(crawlPos.X + handOffset.X, crawlPos.Y - 0.55, crawlPos.Z + handOffset.Z), 4)
		end

		-- Física de Inércia: impulso cíclico das puxadas dos braços + atrito com o solo
		local targetSpeed = CFG.Jump.CrawlSpeed * inputMag * (0.55 + 0.65 * pullImpulse)
		local targetVel = crawlDir * targetSpeed
		local accelRate = inputMag > 0.05 and 8.5 or 5.0 -- Inércia ao parar ou mudar de direção
		crawlVel = crawlVel:Lerp(targetVel, 1 - math.exp(-dt * accelRate))

		-- Colisão frontal e adaptação ao relevo do chão durante o rastejamento
		local stepVec = Vector3.new(crawlVel.X, 0, crawlVel.Z) * dt
		if stepVec.Magnitude > 1e-4 then
			local wallHit = Workspace:Raycast(crawlPos + Vector3.new(0, 0.3, 0), stepVec.Unit * (stepVec.Magnitude + 1.4), rp)
			if not wallHit then
				crawlPos += stepVec
			else
				crawlVel = crawlVel * 0.25
			end
		end

		local curGPos = GroundBelow(ctx, crawlPos, 14)
		crawlPos = Vector3.new(crawlPos.X, lerp(crawlPos.Y, curGPos.Y + 0.62, 1 - math.exp(-dt * 14)), crawlPos.Z)

		-- Rotação do torso, balanço de ombros e respiração
		local speedFrac = clamp01(crawlVel.Magnitude / CFG.Jump.CrawlSpeed)
		local torsoRoll  = armWave * 0.22 * speedFrac
		local torsoYaw   = -armWave * 0.16 * speedFrac
		local torsoPitch = -0.06 + math.abs(armWave) * 0.09 * speedFrac + math.sin(elapsed * 4.5) * 0.025
		local verticalHeave = math.abs(armWave) * 0.14 * speedFrac

		root.CFrame = ProneCF(crawlPos + Vector3.new(0, verticalHeave, 0), crawlDir, torsoRoll, torsoPitch, torsoYaw)

		-- Animação alternada dos braços (alcance à frente -> crava no chão -> puxa para trás)
		local lReach = math.sin(crawlPhase)
		local rReach = math.sin(crawlPhase + PI)
		local lLift  = math.max(0, math.cos(crawlPhase))
		local rLift  = math.max(0, math.cos(crawlPhase + PI))

		pose:SetJoint("LShoulder",
			Vector3.new(0, 0.12 * lReach * speedFrac, -0.15 * lLift * speedFrac),
			CFrame.Angles(1.45 + 0.65 * lReach * speedFrac, 0.18 * lReach * speedFrac, -0.32 - 0.18 * lLift)
		)
		pose:SetJoint("RShoulder",
			Vector3.new(0, 0.12 * rReach * speedFrac, -0.15 * rLift * speedFrac),
			CFrame.Angles(1.45 + 0.65 * rReach * speedFrac, -0.18 * rReach * speedFrac, 0.32 + 0.18 * rLift)
		)
		pose:SetJoint("LElbow", Vector3.zero, CFrame.Angles(0.55 + 0.45 * (1 - lReach) * speedFrac, 0, 0))
		pose:SetJoint("RElbow", Vector3.zero, CFrame.Angles(0.55 + 0.45 * (1 - rReach) * speedFrac, 0, 0))

		-- Cabeça acompanha a direção do olhar / movimento
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(-0.62 - 0.08 * speedFrac, -torsoYaw * 0.7, 0))

		-- Brotamento inicial de tendões nos tocos do quadril no final do rastejamento
		if p > 0.55 and lowerTorso then
			local sprout = smooth(0.55, 1.0, p)
			local hL = hipBoneL.Position
			local hR = hipBoneR.Position
			local backDir = -crawlDir
			DrawTendonBundle(earlyTendonL, hL, hL + backDir * (1.25 * sprout) - Vector3.new(0, 0.12, 0), 0.05, 0.08, 0.10, 0.1)
			DrawTendonBundle(earlyTendonR, hR, hR + backDir * (1.10 * sprout) - Vector3.new(0, 0.12, 0), 0.05, 0.08, 0.10, 0.1)
		end
	end)

	DrawTendonBundle(earlyTendonL, Vector3.zero, Vector3.zero, 0, 0, 0, 1)
	DrawTendonBundle(earlyTendonR, Vector3.zero, Vector3.zero, 0, 0, 0, 1)

	-- 6. RECONSTRUÇÃO PROGRESSIVA E DETALHADA DAS PERNAS + LEVANTAMENTO
	pose:Reset(0.18)
	local finalGround = GroundBelow(ctx, crawlPos, 14)
	local baseProne = ProneCF(Vector3.new(crawlPos.X, finalGround.Y + 0.62, crawlPos.Z), crawlDir, 0, -0.05, 0)

	RebuildAnatomy(ctx, origLegs, {
		{ parts = lLeg, t0 = 0.00, dur = 1.85, anatomy = "Leg", stagger = 0.34 },
		{ parts = rLeg, t0 = 0.22, dur = 1.85, anatomy = "Leg", stagger = 0.34 },
	}, function(t, tEnd)
		local k = clamp01(t / tEnd)
		UpdateHipStumps(smooth(0.55, 0.90, k))
		-- Apoia nas mãos e arqueia o tronco enquanto as pernas se formam e ganham volume
		local pushUp = smooth(0.35, 0.95, k)
		local breath = math.sin(t * 6.5) * 0.03 * (1 - pushUp)
		root.CFrame = baseProne * CFrame.new(0, 0, -breath - 0.18 * pushUp) * CFrame.Angles(-0.22 * pushUp + breath, 0, 0)
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(lerp(1.35, 0.65, pushUp), 0, -0.25))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(lerp(1.35, 0.65, pushUp), 0,  0.25))
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(lerp(-0.55, -0.15, pushUp), 0, 0))
	end)

	SetVisibility(origLegs, 0)
	UpdateHipStumps(1)

	-- Sequência natural de impulsão com os braços e encaixe de pé
	local standPos = Vector3.new(crawlPos.X, finalGround.Y + standOffset, crawlPos.Z)
	local standCF = CFrame.lookAt(standPos, standPos + crawlDir)
	local crouchMidCF = CFrame.lookAt(
		Vector3.new(crawlPos.X, finalGround.Y + standOffset * 0.58, crawlPos.Z),
		Vector3.new(crawlPos.X, finalGround.Y + standOffset * 0.58, crawlPos.Z) + crawlDir
	) * CFrame.Angles(-0.32, 0, 0)

	local fromCF = root.CFrame
	Animate(ctx, 0.34, function(p)
		local k = outCubic(p)
		root.CFrame = fromCF:Lerp(crouchMidCF, k)
		pose:SetJoint("RHip", Vector3.zero, CFrame.Angles(0.75 * (1 - k * 0.3), 0, 0))
		pose:SetJoint("LHip", Vector3.zero, CFrame.Angles(0.45 * (1 - k * 0.3), 0, 0))
	end)

	EmitDust(ctx, finalGround, 6)
	Animate(ctx, 0.38, function(p)
		local k = outBack(p, 1.2)
		root.CFrame = crouchMidCF:Lerp(standCF, k)
		local rem = 1 - clamp01(p)
		pose:SetJoint("RHip", Vector3.zero, CFrame.Angles(0.5 * rem, 0, 0))
		pose:SetJoint("LHip", Vector3.zero, CFrame.Angles(0.3 * rem, 0, 0))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(0.4 * rem, 0, 0))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(0.4 * rem, 0, 0))
	end)

	pose:Reset(0.1)
	pose:SuppressDefaultAnimations(false)
	root.Anchored = false
	hum.PlatformStand = false
	hum.AutoRotate = true
	hum:ChangeState(Enum.HumanoidStateType.GettingUp)
end

--------------------------------------------------------------------------------
-- HABILIDADE 2: NOCLIP (100% LOCAL SEM REMOTES, DESINTEGRAÇÃO ORGÂNICA E RECONSTRUÇÃO)
--------------------------------------------------------------------------------
local function IsBoxBlocked(ctx, cf, size)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { S.char, ctx.folder }
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf, size, op)) do
		if p.CanCollide then
			return true
		end
	end
	return false
end

local function AbilityNoclip(ctx)
	local hum, root = S.hum, S.root
	local pose = CreatePoseController(ctx)
	pose:SuppressDefaultAnimations(true)

	local body = Concat(Group("Torso"), Group("Head"), Group("LArm"), Group("RArm"), Group("LLeg"), Group("RLeg"))
	local origBody = CaptureVisibility(body, true)
	local standOffset = S.r6 and 3.0 or (hum.HipHeight + root.Size.Y * 0.5)
	local charBoxSize = Vector3.new(2.0, standOffset * 2 - 0.4, 1.2)

	-- Colisão local desativada a cada passo físico (Stepped roda antes da física do Roblox)
	local allCharParts = {}
	for _, d in ipairs(S.char:GetDescendants()) do
		if d:IsA("BasePart") then
			allCharParts[d] = d.CanCollide
		end
	end
	local noclipActive = true
	ctx.maid:Add(RunService.Stepped:Connect(function()
		if not noclipActive then return end
		for part, _ in pairs(allCharParts) do
			if part and part.Parent then
				part.CanCollide = false
			end
		end
	end))

	local function RestoreCollisions()
		noclipActive = false
		for part, origCollide in pairs(allCharParts) do
			if part and part.Parent then
				part.CanCollide = origCollide
			end
		end
	end

	ctx.maid:Add(RestoreCollisions)
	ctx.maid:Add(function()
		SetVisibility(origBody, 0)
		if root and root.Parent then
			root.Anchored = false
		end
		if hum and hum.Parent then
			hum.PlatformStand = false
			hum.AutoRotate = true
		end
	end)

	-- 1. Contração Anatômica Interna (Sem Highlight, Sem Neon)
	root.Anchored = true
	local baseCF = root.CFrame
	Animate(ctx, 0.30, function(p)
		local k = outCubic(p)
		local tremor = 0.045 * p
		root.CFrame = baseCF
			* CFrame.new(rand(-tremor, tremor), -0.35 * k, rand(-tremor, tremor))
			* CFrame.Angles(-0.22 * k, 0, 0)
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(0.75 * k, 0, -0.35 * k))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(0.75 * k, 0,  0.35 * k))
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(-0.35 * k, 0, 0))
	end)

	ShakeCamera(hum, 0.32, 0.25)
	EmitTissueMist(ctx, root.Position, 14)

	-- 2. Desintegração progressiva das extremidades para o núcleo em fragmentos físicos
	table.sort(body, function(a, b)
		return (a.Position - root.Position).Magnitude > (b.Position - root.Position).Magnitude
	end)

	for _, p in ipairs(body) do
		local o = origBody[p] or 0
		p.Transparency = 1
		for i = 1, QUALITY.frags do
			local f = Instance.new("Part")
			f.Size = p.Size * rand(0.24, 0.38)
			f.Color = (i == 1) and COL.Bone or (i % 2 == 0 and COL.Muscle or p.Color)
			f.Material = (i == 1) and Enum.Material.Slate or Enum.Material.SmoothPlastic
			f.Transparency = o
			f.CanCollide = true
			f.CanQuery = false
			f.CanTouch = false
			f.CastShadow = false
			f.Massless = true
			f.CFrame = p.CFrame * CFrame.new(rand(-0.35, 0.35) * p.Size.X, rand(-0.35, 0.35) * p.Size.Y, 0)
			f.Parent = ctx.folder
			f.AssemblyLinearVelocity = Vector3.new(rand(-7, 7), rand(-4, 5), rand(-7, 7))
			f.AssemblyAngularVelocity = Vector3.new(rand(-9, 9), rand(-9, 9), rand(-9, 9))
			TweenService:Create(f, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = Vector3.new(0.05, 0.05, 0.05),
				Transparency = 1,
			}):Play()
			Debris:AddItem(f, 0.6)
		end
		Wait(ctx, 0.022)
	end
	SetVisibility(origBody, 1)

	-- 3. Formação da Poça Orgânica e Concentração em Massa Viscosa
	local groundPos = GroundBelow(ctx, root.Position)
	local puddleOuter = FXPart(ctx, COL.BloodDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local puddleInner = FXPart(ctx, COL.MuscleDeep, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local dropShell   = FXPart(ctx, COL.Blood, Enum.Material.Glass, Enum.PartType.Ball)
	local dropCore    = FXPart(ctx, COL.Muscle, Enum.Material.SmoothPlastic, Enum.PartType.Ball)

	local function CylinderFloorCF(pos)
		return CFrame.new(pos) * CFrame.Angles(0, 0, PI * 0.5)
	end

	Animate(ctx, 0.36, function(p)
		local d = lerp(0.5, 4.4, outBack(p, 1.2))
		Put(puddleOuter, CylinderFloorCF(groundPos + Vector3.new(0, 0.03, 0)), Vector3.new(0.06, d, d), 0.04)
		Put(puddleInner, CylinderFloorCF(groundPos + Vector3.new(0, 0.045, 0)), Vector3.new(0.07, d * 0.68, d * 0.68), 0.02)
	end)

	local R = 1.22
	Animate(ctx, 0.42, function(p)
		local k = outCubic(p)
		local d = lerp(4.4, 1.2, k)
		Put(puddleOuter, CylinderFloorCF(groundPos + Vector3.new(0, 0.03, 0)), Vector3.new(0.06, d, d), 0.04 + 0.5 * k)
		Put(puddleInner, CylinderFloorCF(groundPos + Vector3.new(0, 0.045, 0)), Vector3.new(0.07, d * 0.65, d * 0.65), 0.02 + 0.6 * k)
		local r = R * spring(p)
		local wob = 0.22 * bell(p)
		local cPos = groundPos + Vector3.new(0, r * 0.42, 0)
		Put(dropShell, CFrame.new(cPos), Vector3.new(r * (1 + wob), r * (0.82 - wob * 0.5), r * (1 + wob)), 0.12)
		Put(dropCore,  CFrame.new(cPos), Vector3.new(r * 0.62, r * 0.52, r * 0.62), 0.0)
	end)
	puddleOuter.Transparency = 1
	puddleInner.Transparency = 1

	-- 4. Controle Livre da Massa Orgânica (Atravessa Paredes Localmente)
	root.Anchored = false
	hum.PlatformStand = true
	hum.AutoRotate = false

	local att = ctx.maid:Add(Instance.new("Attachment"))
	att.Parent = root
	local lv = ctx.maid:Add(Instance.new("LinearVelocity"))
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = ctx.maid:Add(Instance.new("AlignOrientation"))
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = CFrame.lookAt(Vector3.zero, flat(baseCF.LookVector))
	ao.Parent = root

	local lockY = root.Position.Y
	local vel = Vector3.zero
	local dropPos = dropShell.Position
	local dropVel = Vector3.zero
	local lastDir = flat(baseCF.LookVector)
	local trailTimer = 0

	local function StepDropletVisual(dt, targetPos)
		local acc = (targetPos - dropPos) * 125 - dropVel * 16
		dropVel += acc * dt
		dropPos += dropVel * dt

		local horizSpd = Vector3.new(dropVel.X, 0, dropVel.Z).Magnitude
		local spdFrac = clamp01(horizSpd / CFG.Noclip.Speed)
		if spdFrac > 0.04 then
			lastDir = flat(dropVel)
		end

		local clock = os.clock()
		local wob = 0.06 * math.sin(clock * 9.5) + 0.035 * math.sin(clock * 15.2)
		local jig = clamp01(acc.Magnitude / 850) * 0.14
		local sx = R * (1 - 0.18 * spdFrac + wob + jig)
		local sy = math.max(0.28, R * (0.78 - 0.22 * spdFrac - wob * 0.75))
		local sz = R * (1 + 0.55 * spdFrac + jig)

		local dropCF = CFrame.lookAt(dropPos, dropPos + lastDir) * CFrame.Angles(-0.22 * spdFrac, 0, 0)
		Put(dropShell, dropCF, Vector3.new(sx, sy, sz), 0.14)
		Put(dropCore,  dropCF * CFrame.new(0, -0.04, 0.05 * spdFrac), Vector3.new(sx * 0.64, sy * 0.64, sz * 0.64), 0.0)
		return spdFrac
	end

	Animate(ctx, CFG.Noclip.Duration, function(_, _, dt)
		local desired = hum.MoveDirection * CFG.Noclip.Speed
		vel = vel:Lerp(desired, 1 - math.exp(-dt * 6.5))
		lv.VectorVelocity = Vector3.new(vel.X, (lockY - root.Position.Y) * 10, vel.Z)
		if vel.Magnitude > 0.5 then
			ao.CFrame = CFrame.lookAt(Vector3.zero, flat(vel))
		end

		local floorAt = GroundBelow(ctx, Vector3.new(root.Position.X, lockY, root.Position.Z), 24)
		groundPos = Vector3.new(root.Position.X, floorAt.Y, root.Position.Z)
		local targetDrop = Vector3.new(root.Position.X, groundPos.Y + R * 0.38, root.Position.Z)
		local spdFrac = StepDropletVisual(dt, targetDrop)

		trailTimer += dt * spdFrac
		if trailTimer > 0.085 then
			trailTimer = 0
			local tr = FXPart(ctx, COL.BloodDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			local d0 = rand(0.42, 0.82)
			Put(tr, CylinderFloorCF(Vector3.new(dropPos.X, groundPos.Y + 0.02, dropPos.Z)), Vector3.new(0.03, d0, d0), 0.15)
			TweenService:Create(tr, TweenInfo.new(0.85), {
				Size = Vector3.new(0.03, 0.05, 0.05),
				Transparency = 1,
			}):Play()
			Debris:AddItem(tr, 0.9)
		end
	end)

	-- 5. Saída Segura de Geometrias Sólidas
	local function StandCFAt(pos)
		local gPos = GroundBelow(ctx, Vector3.new(pos.X, lockY + 1.5, pos.Z), 32)
		return CFrame.new(Vector3.new(pos.X, gPos.Y + standOffset, pos.Z)), gPos
	end

	local exitCF, exitGround = StandCFAt(root.Position)
	if IsBoxBlocked(ctx, exitCF, charBoxSize) then
		local found = nil
		for radius = 2, 18, 2 do
			for step = 0, 11 do
				local ang = (step / 12) * TAU
				local testPos = root.Position + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
				local c2, g2 = StandCFAt(testPos)
				if not IsBoxBlocked(ctx, c2, charBoxSize) then
					found = { c2, g2 }
					break
				end
			end
			if found then break end
		end
		if found then
			exitCF, exitGround = found[1], found[2]
			local startRoot = root.Position
			Animate(ctx, 0.42, function(p, _, dt)
				local interp = startRoot:Lerp(Vector3.new(exitCF.X, lockY, exitCF.Z), smooth(0, 1, p))
				lv.VectorVelocity = (interp - root.Position) * 22
				StepDropletVisual(dt, Vector3.new(root.Position.X, exitGround.Y + R * 0.38, root.Position.Z))
			end)
		end
	end

	lv:Destroy()
	ao:Destroy()
	groundPos = exitGround

	-- 6. Reconstrução Corporal Completa a partir da Base Orgânica
	local finalLook = lastDir
	local standCF = CFrame.lookAt(exitCF.Position, exitCF.Position + finalLook)
	root.Anchored = true
	root.CFrame = standCF
	RestoreCollisions()

	local dpStart = dropShell.Position
	Animate(ctx, 0.32, function(p)
		local k = outCubic(p)
		local cPos = dpStart:Lerp(groundPos + Vector3.new(0, 0.08, 0), k)
		Put(dropShell, CFrame.new(cPos), Vector3.new(R * (1 + k), R * (0.8 - 0.7 * k), R * (1 + k)), 0.14 + 0.85 * k)
		Put(dropCore,  CFrame.new(cPos), Vector3.new(R * 0.6 * (1 + k), R * 0.5 * (1 - 0.8 * k), R * 0.6 * (1 + k)), 0.95 * k)
		local d = lerp(1.1, 3.6, outBack(p))
		Put(puddleOuter, CylinderFloorCF(Vector3.new(standCF.X, groundPos.Y + 0.03, standCF.Z)), Vector3.new(0.06, d, d), 0.05)
		Put(puddleInner, CylinderFloorCF(Vector3.new(standCF.X, groundPos.Y + 0.045, standCF.Z)), Vector3.new(0.07, d * 0.68, d * 0.68), 0.04)
	end)
	dropShell.Transparency = 1
	dropCore.Transparency = 1

	-- Tendões ascendentes ancorando a poça ao torso em reconstrução
	local anchorTendonL = NewTendonBundle(ctx, 2)
	local anchorTendonR = NewTendonBundle(ctx, 2)

	RebuildAnatomy(ctx, origBody, {
		{ parts = Group("Torso"), t0 = 0.00, dur = 1.45, anatomy = "Torso", stagger = 0.20 },
		{ parts = Group("LLeg"),  t0 = 0.55, dur = 1.45, anatomy = "Leg",   stagger = 0.22 },
		{ parts = Group("RLeg"),  t0 = 0.65, dur = 1.45, anatomy = "Leg",   stagger = 0.22 },
		{ parts = Group("LArm"),  t0 = 0.75, dur = 1.40, anatomy = "Arm",   stagger = 0.22 },
		{ parts = Group("RArm"),  t0 = 0.85, dur = 1.40, anatomy = "Arm",   stagger = 0.22 },
		{ parts = Group("Head"),  t0 = 1.55, dur = 1.05, anatomy = "Head",  stagger = 0.15 },
	}, function(t, tEnd)
		local k = smooth(0, tEnd * 0.88, t)
		local d = lerp(3.6, 0.15, k)
		Put(puddleOuter, CylinderFloorCF(Vector3.new(standCF.X, groundPos.Y + 0.03, standCF.Z)), Vector3.new(0.06, d, d), 0.05 + 0.92 * k)
		Put(puddleInner, CylinderFloorCF(Vector3.new(standCF.X, groundPos.Y + 0.045, standCF.Z)), Vector3.new(0.07, d * 0.68, d * 0.68), 0.04 + 0.92 * k)

		-- Tendões alimentando o torso a partir da poça
		if k < 0.75 then
			local tAlpha = smooth(0.5, 0.75, k)
			local pBase = Vector3.new(standCF.X, groundPos.Y + 0.05, standCF.Z)
			DrawTendonBundle(anchorTendonL, pBase + Vector3.new(-0.6, 0, 0), root.Position + Vector3.new(-0.4, -0.4, 0), 0.05, 0.12, 0.10, tAlpha)
			DrawTendonBundle(anchorTendonR, pBase + Vector3.new( 0.6, 0, 0), root.Position + Vector3.new( 0.4, -0.4, 0), 0.05, 0.12, 0.10, tAlpha)
		else
			DrawTendonBundle(anchorTendonL, Vector3.zero, Vector3.zero, 0, 0, 0, 1)
			DrawTendonBundle(anchorTendonR, Vector3.zero, Vector3.zero, 0, 0, 0, 1)
		end

		-- Movimento secundário de subida e respiração
		local rise = smooth(0, 0.65, k)
		local breath = math.sin(t * 5.5) * 0.04 * (1 - k)
		root.CFrame = standCF * CFrame.new(0, -0.25 * (1 - rise), 0) * CFrame.Angles(breath, 0, 0)
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(0.25 * (1 - k), 0, 0.18 * (1 - k)))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(0.25 * (1 - k), 0, -0.18 * (1 - k)))
	end)

	-- Revelação contínua dos acessórios e detalhes faciais
	Animate(ctx, 0.28, function(p)
		SetVisibility(origBody, 1 - smooth(0, 1, p), function(inst)
			return not inst:IsA("BasePart") or (inst.Parent and inst.Parent:IsA("Accessory"))
		end)
	end)

	SetVisibility(origBody, 0)
	pose:Reset(0.12)
	pose:SuppressDefaultAnimations(false)
	root.Anchored = false
	hum.PlatformStand = false
	hum.AutoRotate = true
end

--------------------------------------------------------------------------------
-- HABILIDADE 3: GANCHO (LANÇAMENTO DE BRAÇO COM TENDÕES, TRAÇÃO FÍSICA E RECONSTRUÇÃO)
--------------------------------------------------------------------------------
local aimCallback = nil

local function AbilityGrapple(ctx, setAimBanner)
	local hum, root = S.hum, S.root
	local cam = Workspace.CurrentCamera

	-- Fase de Mira (clique do mouse ou toque na tela)
	local chosenScreenPos = nil
	aimCallback = function(screenPos)
		chosenScreenPos = screenPos
	end
	ctx.maid:Add(function()
		aimCallback = nil
	end)

	setAimBanner(true, "SELECIONE UM PONTO PARA O GANCHO")
	ctx.maid:Add(function()
		setAimBanner(false)
	end)

	Animate(ctx, 5.5, function()
		if chosenScreenPos or S.cancelAim then
			return true
		end
	end)
	setAimBanner(false)

	if not chosenScreenPos or S.cancelAim then
		return false
	end

	local ray = cam:ScreenPointToRay(chosenScreenPos.X, chosenScreenPos.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 550, RayParams(ctx))
	if not hit or (hit.Position - root.Position).Magnitude > CFG.Grapple.Range then
		return false
	end

	local targetPos, targetNormal = hit.Position, hit.Normal
	local pose = CreatePoseController(ctx)
	pose:SuppressDefaultAnimations(true)

	local rArm = Group("RArm")
	local origArm = CaptureVisibility(rArm, "attached")
	ctx.maid:Add(function()
		SetVisibility(origArm, 0)
		if hum and hum.Parent then
			hum.PlatformStand = false
			hum.AutoRotate = true
		end
	end)

	local topArm = rArm[1]
	local armLen = 0
	for _, p in ipairs(rArm) do
		armLen += p.Size.Y
	end
	local armW, armD = topArm.Size.X, topArm.Size.Z

	local function GetShoulderWorldPos()
		local ut = GetUpperTorso()
		return (ut.CFrame * CFrame.new(ut.Size.X * 0.5 + armW * 0.35, ut.Size.Y * 0.32, 0)).Position
	end

	local function BuildArmCFrame(basePos, dirVec, roll)
		local right = dirVec:Cross(Vector3.yAxis)
		right = right.Magnitude > 1e-3 and right.Unit or Vector3.xAxis
		local center = basePos + dirVec * (armLen * 0.5)
		return CFrame.fromMatrix(center, right, dirVec) * CFrame.Angles(0, roll or 0, 0)
	end

	-- Peças anatômicas do braço lançado
	local projArm   = FXPart(ctx, topArm.Color, topArm.Material)
	local projHand  = FXPart(ctx, topArm.Color:Lerp(COL.Muscle, 0.15), topArm.Material)
	local projBone  = FXPart(ctx, COL.Bone, Enum.Material.Slate)
	local woundRing = FXPart(ctx, COL.MuscleDeep, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local gripPad   = FXPart(ctx, COL.Muscle, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local tendons   = NewTendonBundle(ctx)

	local function DrawLaunchedArm(basePos, dirVec, roll, stretch, trans)
		local cf = BuildArmCFrame(basePos, dirVec, roll)
		local sLen = armLen * (stretch or 1)
		Put(projArm,  cf, Vector3.new(armW, sLen, armD), trans)
		Put(projHand, cf * CFrame.new(0, sLen * 0.5 - 0.18, 0), Vector3.new(armW * 1.08, 0.36, armD * 1.08), trans)
		Put(projBone, cf * CFrame.new(0, -sLen * 0.5 - 0.12, 0), Vector3.new(armW * 0.34, 0.28, armD * 0.34), trans)
	end

	local function DrawShoulderWound(trans)
		local sh = GetShoulderWorldPos()
		local dir = safeUnit(targetPos - sh, root.CFrame.LookVector)
		Put(woundRing, CFrame.lookAt(sh, sh + dir) * CFrame.Angles(0, PI * 0.5, 0), Vector3.new(0.08, armW * 0.88, armD * 0.88), trans)
	end

	-- 1. Antecipação: gira o tronco e prepara o disparo do braço
	SetVisibility(origArm, 1)
	local initDir = safeUnit(targetPos - GetShoulderWorldPos(), root.CFrame.LookVector)
	EmitTissueMist(ctx, GetShoulderWorldPos(), 6)

	Animate(ctx, 0.15, function(p)
		local k = outCubic(p)
		local sh = GetShoulderWorldPos()
		pose:SetJoint("Waist", Vector3.zero, CFrame.Angles(0, -0.35 * k, 0))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(-0.45 * k, 0, -0.25 * k))
		DrawLaunchedArm(sh - initDir * (0.45 * k), safeUnit(targetPos - sh, initDir), 0, 1 - 0.1 * k, 0)
		DrawShoulderWound(0.05)
	end)

	-- 2. Disparo Balístico do Braço com Feixes de Tendões
	local distToTarget = (targetPos - GetShoulderWorldPos()).Magnitude
	local flightDur = math.clamp(distToTarget / 105, 0.16, 0.42)
	local startShoulder = GetShoulderWorldPos()
	local currentArmBase = startShoulder

	Animate(ctx, flightDur, function(p)
		local sh = GetShoulderWorldPos()
		local k = outCubic(p)
		local dirToTarg = safeUnit(targetPos - sh, initDir)
		local endBase = targetPos - dirToTarg * armLen
		currentArmBase = (startShoulder - initDir * 0.45):Lerp(endBase, k) + Vector3.new(0, distToTarget * 0.05 * bell(p), 0)
		local curDir = safeUnit(targetPos - currentArmBase, dirToTarg)

		pose:SetJoint("Waist", Vector3.zero, CFrame.Angles(-0.15 * k, 0.35 * k, 0))
		DrawLaunchedArm(currentArmBase, curDir, (1 - k) * 8, 1 + 0.14 * bell(p), 0)
		DrawShoulderWound(0.05)
		local pts = DrawTendonBundle(tendons, sh, currentArmBase, 0.18 * (1 - k), lerp(0.42, 0.14, k), 0.13, 0.02)
		if #pts > 0 and math.random() < 0.45 then
			local pt = pts[math.random(1, #pts)]
			SpawnPhysicalDrop(ctx, pt, Vector3.new(rand(-3, 3), rand(1, 4), rand(-3, 3)), 0.10)
		end
	end)

	-- 3. Ancoragem Firme na Superfície
	EmitDust(ctx, targetPos, 12)
	EmitTissueMist(ctx, targetPos, 8)
	ShakeCamera(hum, 0.22, 0.18)
	for _ = 1, 5 do
		SpawnPhysicalDrop(ctx, targetPos + targetNormal * 0.2, targetNormal * rand(3, 7) + Vector3.new(rand(-3, 3), rand(1, 5), rand(-3, 3)))
	end

	local gripCF = CFrame.lookAt(targetPos + targetNormal * 0.04, targetPos + targetNormal * 2) * CFrame.Angles(0, PI * 0.5, 0)
	Animate(ctx, 0.12, function(p)
		local sh = GetShoulderWorldPos()
		local dir = safeUnit(targetPos - sh, initDir)
		currentArmBase = targetPos - dir * (armLen * (1 - 0.12 * bell(p)))
		DrawLaunchedArm(currentArmBase, dir, 0, 1 - 0.12 * bell(p), 0)
		DrawShoulderWound(0.05)
		local gd = lerp(0.3, armW * 2.1, outBack(p))
		Put(gripPad, gripCF, Vector3.new(0.06, gd, gd), 0.05)
		DrawTendonBundle(tendons, sh, currentArmBase, 0.04, 0.10, 0.13, 0.02)
	end)

	-- 4. Tração Física de Alta Velocidade com Pêndulo e Inércia
	hum.PlatformStand = true
	hum.AutoRotate = false
	local att = ctx.maid:Add(Instance.new("Attachment"))
	att.Parent = root
	local lv = ctx.maid:Add(Instance.new("LinearVelocity"))
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e6
	lv.Parent = root

	local ao = ctx.maid:Add(Instance.new("AlignOrientation"))
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 20
	ao.MaxTorque = 1e6
	ao.Parent = root

	local destPos = targetPos + targetNormal * 2.6
	local totalPullDist = math.max((destPos - root.Position).Magnitude, 0.1)
	local pullDir0 = safeUnit(destPos - root.Position, initDir)

	Animate(ctx, 2.6, function(_, elapsed)
		local toDest = destPos - root.Position
		local remDist = toDest.Magnitude
		local q = clamp01(1 - remDist / totalPullDist)
		if remDist < 3.2 or elapsed > 2.4 then
			return true
		end

		local speed = CFG.Grapple.PullSpeed * smooth(0, 0.2, q) * (0.32 + 0.68 * (1 - smooth(0.72, 1, q)))
		speed = math.max(speed, 16)
		local side = pullDir0:Cross(Vector3.yAxis)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis
		local sway = side * (math.sin(elapsed * 6.5) * 6.5 * bell(q)) + Vector3.new(0, math.sin(elapsed * 4.2) * 2.8 * bell(q), 0)

		lv.VectorVelocity = toDest.Unit * speed + sway
		ao.CFrame = CFrame.lookAt(Vector3.zero, flat(toDest)) * CFrame.Angles(-0.45 * bell(q), 0, math.sin(elapsed * 6.5) * 0.22 * bell(q))

		local sh = GetShoulderWorldPos()
		DrawLaunchedArm(currentArmBase, safeUnit(targetPos - currentArmBase, initDir), 0, 1, 0)
		DrawShoulderWound(0.05)
		DrawTendonBundle(tendons, sh, currentArmBase, 0.02, 0.05 + 0.07 * (1 - q), 0.12, 0.02)
		Put(gripPad, gripCF, Vector3.new(0.06, armW * 2.1, armW * 2.1), 0.05)
	end)

	lv:Destroy()
	ao:Destroy()
	hum.PlatformStand = false
	hum.AutoRotate = true
	root.AssemblyLinearVelocity = pullDir0 * 15 + Vector3.new(0, 22, 0)

	-- 5. Retração e Reconstrução Progressiva do Braço no Ombro
	local retractStart = currentArmBase
	Animate(ctx, 0.24, function(p)
		local sh = GetShoulderWorldPos()
		local k = smooth(0, 1, p)
		local curBase = retractStart:Lerp(sh, k)
		local dir = safeUnit(targetPos - curBase, -topArm.CFrame.UpVector)
		DrawLaunchedArm(curBase, dir, k * 3.5, 1 - 0.15 * k, k * 0.85)
		DrawTendonBundle(tendons, sh, curBase, 0, 0.16 * bell(p), 0.11 * (1 - 0.6 * k), k * 0.9)
		Put(gripPad, gripCF, Vector3.new(0.06, armW * 2.1 * (1 - k), armW * 2.1 * (1 - k)), 0.05 + 0.95 * k)
		DrawShoulderWound(0.05)
	end)

	projArm.Transparency = 1
	projHand.Transparency = 1
	projBone.Transparency = 1
	gripPad.Transparency = 1
	DrawTendonBundle(tendons, Vector3.zero, Vector3.zero, 0, 0, 0, 1)

	-- Reconstrução anatômica rápida dos segmentos do braço direito para encaixe perfeito
	RebuildAnatomy(ctx, origArm, {
		{ parts = rArm, t0 = 0.0, dur = 0.65, anatomy = "Arm", stagger = 0.12 },
	}, function(t, tEnd)
		local k = clamp01(t / tEnd)
		DrawShoulderWound(smooth(0.4, 0.9, k))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(0.35 * bell(k), 0, 0.2 * bell(k)))
	end)

	woundRing.Transparency = 1
	SetVisibility(origArm, 0)
	pose:Reset(0.12)
	pose:SuppressDefaultAnimations(false)
	return true
end

--------------------------------------------------------------------------------
-- HABILIDADE 4: HEAD THROW (SEGURA A CABEÇA, LANÇA COM FÍSICA/CÂMERA E REGENERA)
--------------------------------------------------------------------------------
local function AbilityHeadThrow(ctx)
	local hum, root = S.hum, S.root
	local cam = Workspace.CurrentCamera
	local pose = CreatePoseController(ctx)
	pose:SuppressDefaultAnimations(true)

	local headGroup = Group("Head")
	local realHead = headGroup[1]
	if not realHead then return end

	local origHeadVis = CaptureVisibility(headGroup, "attached")
	local origCamSubject = cam.CameraSubject
	local origCamType = cam.CameraType

	ctx.maid:Add(function()
		SetVisibility(origHeadVis, 0)
		if cam then
			cam.CameraType = origCamType
			if S.hum and S.hum.Parent then
				cam.CameraSubject = S.hum
			else
				cam.CameraSubject = origCamSubject
			end
		end
	end)

	local upperTorso = GetUpperTorso()
	local function GetNeckWorldCF()
		if not upperTorso or not upperTorso.Parent then return root.CFrame end
		return upperTorso.CFrame * CFrame.new(0, upperTorso.Size.Y * 0.5, 0)
	end

	-- Peças anatômicas do toco do pescoço (visíveis quando sem cabeça)
	local neckWound = FXPart(ctx, COL.MuscleDeep, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local neckBone  = FXPart(ctx, COL.Bone, Enum.Material.Slate)
	local function UpdateNeckStump(trans)
		local ncf = GetNeckWorldCF()
		Put(neckWound, ncf * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, PI * 0.5), Vector3.new(0.09, 0.72, 0.72), trans)
		Put(neckBone,  ncf * CFrame.new(0, 0.14, 0.04), Vector3.new(0.24, 0.24, 0.24), trans)
	end

	-- 1. PERSONAGEM SEGURA A PRÓPRIA CABEÇA E TRACIONA O PESCOÇO
	local strainTendons = NewTendonBundle(ctx, 2)
	Animate(ctx, 0.44, function(p)
		-- Fase A (0 -> 0.55): Braços sobem e mãos agarram as laterais da cabeça
		-- Fase B (0.55 -> 1.0): Tronco inclina para trás, braços puxam a cabeça para cima esticando os tendões cervicais
		local grab = smooth(0.0, 0.55, p)
		local pull = smooth(0.50, 1.0, p)
		local tremor = pull * 0.035

		pose:SetJoint("RShoulder",
			Vector3.new(-0.18 * grab, 0.22 * grab + 0.18 * pull, 0),
			CFrame.Angles(2.55 * grab + 0.2 * pull, -0.35 * grab, -0.48 * grab)
		)
		pose:SetJoint("LShoulder",
			Vector3.new( 0.18 * grab, 0.22 * grab + 0.18 * pull, 0),
			CFrame.Angles(2.55 * grab + 0.2 * pull,  0.35 * grab,  0.48 * grab)
		)
		pose:SetJoint("RElbow", Vector3.zero, CFrame.Angles(1.15 * grab, 0, 0))
		pose:SetJoint("LElbow", Vector3.zero, CFrame.Angles(1.15 * grab, 0, 0))
		pose:SetJoint("Waist", Vector3.zero, CFrame.Angles(0.22 * pull, 0, 0))
		pose:SetJoint("Root", Vector3.zero, CFrame.Angles(0.14 * pull, 0, 0))

		-- Cabeça sendo descolada gradualmente do pescoço
		pose:SetJoint("Neck",
			Vector3.new(rand(-tremor, tremor), 0.48 * pull, rand(-tremor, tremor)),
			CFrame.Angles(0.18 * pull, math.sin(p * PI * 6) * 0.08 * pull, 0)
		)

		if pull > 0.05 then
			UpdateNeckStump(0.05)
			local nPos = GetNeckWorldCF().Position
			local hBase = realHead.Position - realHead.CFrame.UpVector * (realHead.Size.Y * 0.42)
			DrawTendonBundle(strainTendons, nPos, hBase, 0.02, 0.09 * pull, 0.12, 0.05)
		end
	end)

	DrawTendonBundle(strainTendons, Vector3.zero, Vector3.zero, 0, 0, 0, 1)

	-- 2. REMOVE E LANÇA A CABEÇA NA DIREÇÃO DA MIRA
	local aimDir = safeUnit(cam.CFrame.LookVector + Vector3.new(0, 0.10, 0), root.CFrame.LookVector)
	local flatAim = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + flatAim)

	-- Oculta a cabeça real e seus acessórios no personagem
	SetVisibility(origHeadVis, 1)
	UpdateNeckStump(0)
	EmitTissueMist(ctx, realHead.Position, 12)
	ShakeCamera(hum, 0.32, 0.24)
	for _ = 1, 6 do
		SpawnPhysicalDrop(ctx, GetNeckWorldCF().Position, Vector3.new(rand(-6, 6), rand(3, 9), rand(-6, 6)))
	end

	-- Constrói o projétil físico da cabeça (com rosto e todos os acessórios da cabeça presos)
	local thrownModel = Instance.new("Model")
	thrownModel.Name = "ThrownHeadModel"
	thrownModel.Parent = ctx.folder

	local headClone = realHead:Clone()
	for _, d in ipairs(headClone:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	headClone.Transparency = origHeadVis[realHead] or 0
	headClone.Anchored = true
	headClone.CanCollide = false
	headClone.CanQuery = false
	headClone.CanTouch = false
	headClone.CFrame = realHead.CFrame
	headClone.Parent = thrownModel

	-- Base anatômica na parte inferior da cabeça lançada (osso cervical + músculo)
	local neckCap = Instance.new("Part")
	neckCap.Size = Vector3.new(realHead.Size.X * 0.55, 0.14, realHead.Size.Z * 0.55)
	neckCap.Color = COL.MuscleDeep
	neckCap.Material = Enum.Material.SmoothPlastic
	neckCap.Anchored = true
	neckCap.CanCollide = false
	neckCap.CanQuery = false
	neckCap.CanTouch = false
	neckCap.Parent = thrownModel

	-- Clona acessórios presos à cabeça (cabelo, chapéu, etc.) mantendo offset relativo
	local accAttachments = {
		{ inst = neckCap, relCF = CFrame.new(0, -realHead.Size.Y * 0.48, 0) }
	}
	for _, acc in ipairs(S.char:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			if handle and origHeadVis[handle] ~= nil then
				local hClone = handle:Clone()
				for _, d in ipairs(hClone:GetDescendants()) do
					if d:IsA("JointInstance") or d:IsA("Weld") or d:IsA("Motor6D") or d:IsA("Constraint") then
						d:Destroy()
					end
				end
				hClone.Transparency = origHeadVis[handle] or 0
				hClone.Anchored = true
				hClone.CanCollide = false
				hClone.CanQuery = false
				hClone.CanTouch = false
				hClone.Parent = thrownModel
				table.insert(accAttachments, {
					inst = hClone,
					relCF = realHead.CFrame:ToObjectSpace(handle.CFrame),
				})
			end
		end
	end

	local function SetThrownHeadCFrame(cf)
		headClone.CFrame = cf
		for _, item in ipairs(accAttachments) do
			if item.inst and item.inst.Parent then
				item.inst.CFrame = cf * item.relCF
			end
		end
	end

	-- Impulso de arremesso dos braços para frente
	Animate(ctx, 0.10, function(p)
		local k = outCubic(p)
		UpdateNeckStump(0)
		pose:SetJoint("Waist", Vector3.zero, CFrame.Angles(lerp(0.22, -0.38, k), 0, 0))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(lerp(2.75, 1.15, k), 0, lerp(-0.48, 0.15, k)))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(lerp(2.75, 1.15, k), 0, lerp( 0.48, -0.15, k)))
		pose:SetJoint("RElbow", Vector3.zero, CFrame.Angles(lerp(1.15, 0.15, k), 0, 0))
		pose:SetJoint("LElbow", Vector3.zero, CFrame.Angles(lerp(1.15, 0.15, k), 0, 0))
		SetThrownHeadCFrame(GetNeckWorldCF() * CFrame.new(0, 0.75, -0.65 * k))
	end)

	-- 3. TRAJETÓRIA FÍSICA, ROTAÇÃO NATURAL E ACOMPANHAMENTO PELA CÂMERA
	local headPos = headClone.Position
	local headVel = aimDir * CFG.HeadThrow.Speed + Vector3.new(0, CFG.HeadThrow.UpwardBias, 0)
	local headRot = headClone.CFrame.Rotation
	local angVel = Vector3.new(-13.5, rand(-5.5, 5.5), rand(-4.5, 4.5))
	local headRadius = math.max(realHead.Size.X, realHead.Size.Y, realHead.Size.Z) * 0.52

	local rp = RayParams(ctx, { thrownModel })
	local bounces = 0
	local settledTime = nil

	-- Câmera acompanha a trajetória da cabeça suavemente com proteção de colisão
	cam.CameraType = Enum.CameraType.Scriptable
	local camFocus = headPos
	local camLookDir = aimDir

	Animate(ctx, CFG.HeadThrow.MaxFlightTime, function(_, elapsed, dt)
		UpdateNeckStump(0)

		-- Postura de follow-through do corpo sem cabeça
		local rec = smooth(0.0, 0.55, elapsed)
		pose:SetJoint("Waist", Vector3.zero, CFrame.Angles(lerp(-0.38, -0.08, rec), 0, 0))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(lerp(1.15, 0.15, rec), 0, 0.15))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(lerp(1.15, 0.15, rec), 0, -0.15))

		-- Integração física balística da cabeça
		headVel = headVel - Vector3.new(0, CFG.HeadThrow.Gravity * dt, 0)
		headVel = headVel * (1 - 0.18 * dt) -- Resistência do ar

		local step = headVel * dt
		local stepDist = step.Magnitude
		if stepDist > 1e-4 then
			local hit = Workspace:Raycast(headPos, step.Unit * (stepDist + headRadius), rp)
			if hit then
				bounces += 1
				headPos = hit.Position + hit.Normal * headRadius

				-- Reflexão física com restituição e atrito tangencial
				local vn = headVel:Dot(hit.Normal)
				local normalVel = hit.Normal * vn
				local tangVel = headVel - normalVel
				local restitution = (bounces == 1) and 0.42 or 0.28
				headVel = tangVel * 0.68 - normalVel * restitution

				-- Rotação natural induzida pelo torque do impacto na superfície
				local rollAxis = hit.Normal:Cross(safeUnit(tangVel, Vector3.xAxis))
				angVel = rollAxis * (tangVel.Magnitude / math.max(headRadius, 0.4))
					+ Vector3.new(rand(-3, 3), rand(-3, 3), rand(-3, 3))

				-- Efeitos físicos de impacto (poeira, fragmentos de superfície e gotas)
				EmitDust(ctx, hit.Position, bounces == 1 and 18 or 7)
				if bounces == 1 then
					EmitTissueMist(ctx, hit.Position, 10)
					for _ = 1, 6 do
						SpawnPhysicalDrop(ctx, hit.Position + hit.Normal * 0.2,
							hit.Normal * rand(5, 14) + Vector3.new(rand(-8, 8), rand(3, 10), rand(-8, 8)),
							rand(0.14, 0.24), hit.Material, hit.Instance and hit.Instance.Color or COL.Dust)
					end
				elseif bounces <= 3 then
					SpawnPhysicalDrop(ctx, hit.Position + hit.Normal * 0.15, hit.Normal * rand(2, 5), 0.12)
				end

				if headVel.Magnitude < 6.5 and hit.Normal.Y > 0.5 then
					settledTime = settledTime or elapsed
				end
			else
				headPos += step
			end
		end

		-- Atualiza rotação 3D contínua da cabeça
		local angSpeed = angVel.Magnitude
		if angSpeed > 1e-3 then
			headRot = CFrame.fromAxisAngle(angVel.Unit, angSpeed * dt) * headRot
		end
		angVel = angVel * (1 - 1.4 * dt)
		SetThrownHeadCFrame(CFrame.new(headPos) * headRot)

		if bounces == 0 and math.random() < 0.35 then
			SpawnPhysicalDrop(ctx, headPos, headVel * 0.15 + Vector3.new(rand(-2, 2), rand(0, 3), rand(-2, 2)), 0.10)
		end

		-- Atualiza câmera seguindo a cabeça lançada
		camFocus = camFocus:Lerp(headPos, 1 - math.exp(-dt * 18))
		local velDir = headVel.Magnitude > 4 and headVel.Unit or camLookDir
		camLookDir = safeUnit(camLookDir:Lerp(velDir, 1 - math.exp(-dt * 5)), camLookDir)

		local desiredCamOffset = -flat(camLookDir) * 8.5 + Vector3.new(0, 3.4, 0)
		local camHit = Workspace:Raycast(camFocus, desiredCamOffset, rp)
		local camPos = camHit and (camHit.Position - desiredCamOffset.Unit * 0.6) or (camFocus + desiredCamOffset)
		cam.CFrame = CFrame.lookAt(camPos, camFocus)

		-- Encerra o acompanhamento após um breve intervalo pós-impacto
		if settledTime and (elapsed - settledTime) >= CFG.HeadThrow.PostImpactWait then
			return true
		end
		if bounces >= 1 and elapsed > 1.35 and headVel.Magnitude < 12 then
			settledTime = settledTime or elapsed
		end
	end)

	-- Pequeno intervalo caso tenha encerrado no impacto imediato
	if not settledTime then
		Animate(ctx, CFG.HeadThrow.PostImpactWait, function(_, _, dt)
			UpdateNeckStump(0)
			headVel = headVel * (1 - 4 * dt) - Vector3.new(0, 30 * dt, 0)
			local gPos = GroundBelow(ctx, headPos, 6)
			headPos = Vector3.new(headPos.X + headVel.X * dt, math.max(gPos.Y + headRadius, headPos.Y + headVel.Y * dt), headPos.Z + headVel.Z * dt)
			SetThrownHeadCFrame(CFrame.new(headPos) * headRot)
			camFocus = camFocus:Lerp(headPos, 1 - math.exp(-dt * 12))
			local desiredCamOffset = -flat(camLookDir) * 8.0 + Vector3.new(0, 3.2, 0)
			local camHit = Workspace:Raycast(camFocus, desiredCamOffset, rp)
			local camPos = camHit and (camHit.Position - desiredCamOffset.Unit * 0.6) or (camFocus + desiredCamOffset)
			cam.CFrame = CFrame.lookAt(camPos, camFocus)
		end)
	end

	-- 4. TRANSIÇÃO SUAVE DA CÂMERA DE VOLTA AO CORPO + DESINTEGRAÇÃO DA CABEÇA LANÇADA
	local returnStartCam = cam.CFrame
	local charCamLook = flat(root.CFrame.LookVector)
	Animate(ctx, 0.36, function(p)
		local k = smoother(0, 1, p)
		UpdateNeckStump(0)
		local neckFocus = GetNeckWorldCF().Position + Vector3.new(0, 0.6, 0)
		local targetCamOffset = -charCamLook * 9.5 + Vector3.new(0, 2.8, 0)
		local camHit = Workspace:Raycast(neckFocus, targetCamOffset, rp)
		local targetCamPos = camHit and (camHit.Position - targetCamOffset.Unit * 0.5) or (neckFocus + targetCamOffset)
		local goalCamCF = CFrame.lookAt(targetCamPos, neckFocus)
		cam.CFrame = returnStartCam:Lerp(goalCamCF, k)

		-- Cabeça lançada se desfaz em tecido orgânico
		for _, d in ipairs(thrownModel:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.Transparency = clamp01(lerp(d.Transparency, 1, k))
			end
		end
	end)

	thrownModel:Destroy()
	cam.CameraType = origCamType
	cam.CameraSubject = S.hum

	-- 5. RECONSTRUÇÃO PROGRESSIVA DA CABEÇA E ENCAIXE NATURAL NO PESCOÇO
	RebuildAnatomy(ctx, origHeadVis, {
		{ parts = headGroup, t0 = 0.0, dur = 1.35, anatomy = "Head", stagger = 0.1 },
	}, function(t, tEnd)
		local k = clamp01(t / tEnd)
		UpdateNeckStump(smooth(0.55, 0.92, k))

		-- Mãos sobem nas laterais do pescoço/cabeça para guiar e encaixar a cabeça recém-formada
		local touchBell = bell(smooth(0.25, 0.95, k))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(1.95 * touchBell, -0.25 * touchBell, -0.32 * touchBell))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(1.95 * touchBell,  0.25 * touchBell,  0.32 * touchBell))
		pose:SetJoint("RElbow", Vector3.zero, CFrame.Angles(0.95 * touchBell, 0, 0))
		pose:SetJoint("LElbow", Vector3.zero, CFrame.Angles(0.95 * touchBell, 0, 0))

		-- Ajuste cervical progressivo
		local neckTilt = (1 - smooth(0.4, 1.0, k)) * 0.28
		pose:SetJoint("Neck", Vector3.new(0, -0.12 * (1 - k), 0), CFrame.Angles(-neckTilt, math.sin(k * PI * 3) * 0.12 * (1 - k), 0))
	end)

	-- Revela acessórios da cabeça (cabelo/chapéu/rosto) e faz o giro final de encaixe no pescoço
	UpdateNeckStump(1)
	ShakeCamera(hum, 0.14, 0.16)
	Animate(ctx, 0.26, function(p)
		local k = outBack(p, 1.4)
		SetVisibility(origHeadVis, 1 - smooth(0, 0.7, p))
		local snapRoll = math.sin(p * PI) * 0.18 * (1 - p)
		local snapPitch = -0.14 * bell(p) * (1 - p)
		pose:SetJoint("Neck", Vector3.zero, CFrame.Angles(snapPitch, 0, snapRoll))
		pose:SetJoint("RShoulder", Vector3.zero, CFrame.Angles(0.4 * (1 - k), 0, 0))
		pose:SetJoint("LShoulder", Vector3.zero, CFrame.Angles(0.4 * (1 - k), 0, 0))
	end)

	SetVisibility(origHeadVis, 0)
	pose:Reset(0.10)
	pose:SuppressDefaultAnimations(false)
end

--------------------------------------------------------------------------------
-- INTERFACE MINIMALISTA PROFISSIONAL (4 BOTÕES COMPACTOS, TOUCH E MOUSE)
--------------------------------------------------------------------------------
local UI = { buttons = {} }

local BUTTON_DEFS = {
	{ id = "Jump",      label = "JUMP",       icon = "▲", key = Enum.KeyCode.Q, keyText = "Q" },
	{ id = "Noclip",    label = "NOCLIP",     icon = "●", key = Enum.KeyCode.E, keyText = "E" },
	{ id = "Grapple",   label = "GANCHO",     icon = "↗", key = Enum.KeyCode.R, keyText = "R" },
	{ id = "HeadThrow", label = "HEAD THROW", icon = "◉", key = Enum.KeyCode.F, keyText = "F" },
}

local UI_PALETTE = {
	Bg         = Color3.fromRGB(18, 19, 22),
	BgActive   = Color3.fromRGB(32, 34, 40),
	Border     = Color3.fromRGB(62, 66, 74),
	BorderAct  = Color3.fromRGB(215, 220, 228),
	TextMain   = Color3.fromRGB(238, 240, 244),
	TextMuted  = Color3.fromRGB(142, 146, 156),
	CooldownBg = Color3.fromRGB(8, 9, 11),
}

local TryUseAbility -- declaração antecipada

function UI.Build()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("RegenMovesetUI")
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "RegenMovesetUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	-- Aviso discreto para mira do Gancho
	local banner = Instance.new("TextLabel")
	banner.Name = "AimBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 48)
	banner.Size = UDim2.fromOffset(290, 30)
	banner.BackgroundColor3 = UI_PALETTE.Bg
	banner.BackgroundTransparency = 0.15
	banner.TextColor3 = UI_PALETTE.TextMain
	banner.Font = Enum.Font.GothamMedium
	banner.TextSize = 12
	banner.Text = "SELECIONE UM PONTO PARA O GANCHO"
	banner.Visible = false
	banner.Parent = gui
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 6)
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Thickness = 1
	bannerStroke.Color = UI_PALETTE.Border
	bannerStroke.Parent = banner
	UI.banner = banner

	-- Barra compacta e limpa com os 4 botões
	local bar = Instance.new("Frame")
	bar.Name = "ActionBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = IS_MOBILE and UDim2.new(0.5, 0, 1, -18) or UDim2.new(0.5, 0, 1, -22)
	bar.Size = IS_MOBILE and UDim2.fromOffset(278, 60) or UDim2.fromOffset(302, 64)
	bar.BackgroundTransparency = 1
	bar.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	table.clear(UI.buttons)

	for idx, def in ipairs(BUTTON_DEFS) do
		local btnSize = IS_MOBILE and 62 or 68
		local b = Instance.new("TextButton")
		b.Name = def.id
		b.LayoutOrder = idx
		b.Text = ""
		b.AutoButtonColor = false
		b.Size = UDim2.fromOffset(btnSize, btnSize)
		b.BackgroundColor3 = UI_PALETTE.Bg
		b.BackgroundTransparency = 0.12
		b.ClipsDescendants = true
		b.Parent = bar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.2
		stroke.Color = UI_PALETTE.Border
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b

		local scale = Instance.new("UIScale")
		scale.Parent = b

		-- Atalho de tecla discreto no canto superior esquerdo (em PC)
		if not IS_MOBILE then
			local keyLbl = Instance.new("TextLabel")
			keyLbl.BackgroundTransparency = 1
			keyLbl.Position = UDim2.fromOffset(6, 4)
			keyLbl.Size = UDim2.fromOffset(16, 12)
			keyLbl.Font = Enum.Font.GothamBold
			keyLbl.TextSize = 10
			keyLbl.TextXAlignment = Enum.TextXAlignment.Left
			keyLbl.TextColor3 = UI_PALETTE.TextMuted
			keyLbl.Text = def.keyText
			keyLbl.ZIndex = 2
			keyLbl.Parent = b
		end

		-- Ícone minimalista central
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.40, 0)
		icon.Size = UDim2.fromOffset(32, 26)
		icon.Font = Enum.Font.GothamBold
		icon.TextSize = IS_MOBILE and 18 or 20
		icon.TextColor3 = UI_PALETTE.TextMain
		icon.Text = def.icon
		icon.ZIndex = 2
		icon.Parent = b

		-- Rótulo compacto inferior
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.AnchorPoint = Vector2.new(0.5, 1)
		lbl.Position = UDim2.new(0.5, 0, 1, -5)
		lbl.Size = UDim2.new(1, -4, 0, 13)
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 8
		lbl.TextScaled = false
		lbl.TextTruncate = Enum.TextTruncate.None
		lbl.TextColor3 = UI_PALETTE.TextMuted
		lbl.Text = def.label
		lbl.ZIndex = 2
		lbl.Parent = b

		-- Máscara de recarga vertical limpa
		local cdFill = Instance.new("Frame")
		cdFill.AnchorPoint = Vector2.new(0, 1)
		cdFill.Position = UDim2.fromScale(0, 1)
		cdFill.Size = UDim2.fromScale(1, 0)
		cdFill.BackgroundColor3 = UI_PALETTE.CooldownBg
		cdFill.BackgroundTransparency = 0.28
		cdFill.BorderSizePixel = 0
		cdFill.ZIndex = 3
		cdFill.Parent = b

		local cdText = Instance.new("TextLabel")
		cdText.BackgroundTransparency = 1
		cdText.Size = UDim2.fromScale(1, 1)
		cdText.Font = Enum.Font.GothamBold
		cdText.TextSize = 15
		cdText.TextColor3 = UI_PALETTE.TextMain
		cdText.Text = ""
		cdText.ZIndex = 4
		cdText.Parent = b

		local entry = {
			def = def,
			b = b,
			stroke = stroke,
			scale = scale,
			icon = icon,
			lbl = lbl,
			cdFill = cdFill,
			cdText = cdText,
		}
		UI.buttons[def.id] = entry

		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(scale, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.93 }):Play()
			end
		end)

		local function releaseScale()
			TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
		end
		b.InputEnded:Connect(releaseScale)
		b.MouseLeave:Connect(releaseScale)
		b.Activated:Connect(function()
			TryUseAbility(def.id)
		end)
	end
end

function UI.DenyFeedback(id)
	local entry = UI.buttons[id]
	if not entry then return end
	TweenService:Create(entry.scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	task.delay(0.07, function()
		if entry.scale and entry.scale.Parent then
			TweenService:Create(entry.scale, TweenInfo.new(0.12), { Scale = 1.0 }):Play()
		end
	end)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for id, entry in pairs(UI.buttons) do
		local rem = (S.cd[id] or 0) - now
		local maxCd = CFG.Cooldown[id] or 1
		local frac = clamp01(rem / maxCd)
		entry.cdFill.Size = UDim2.fromScale(1, frac)
		entry.cdText.Text = rem > 0 and string.format("%.1f", rem) or ""

		local isActive = (S.busy == id)
		local isLocked = (S.busy ~= nil and S.busy ~= id)

		entry.b.BackgroundColor3 = isActive and UI_PALETTE.BgActive or UI_PALETTE.Bg
		entry.b.BackgroundTransparency = isLocked and 0.45 or 0.12
		entry.stroke.Color = isActive and UI_PALETTE.BorderAct or UI_PALETTE.Border
		entry.stroke.Thickness = isActive and 1.8 or 1.2
		entry.icon.TextTransparency = (isLocked or rem > 0) and 0.55 or 0
		entry.lbl.TextTransparency = isLocked and 0.6 or 0
	end
end)

--------------------------------------------------------------------------------
-- DESPACHO DE HABILIDADES, ENTRADAS E SUPORTE A RESPAWN
--------------------------------------------------------------------------------
local ABILITY_HANDLERS = {
	Jump      = AbilityJump,
	Noclip    = AbilityNoclip,
	Grapple   = AbilityGrapple,
	HeadThrow = AbilityHeadThrow,
}

TryUseAbility = function(id)
	-- Permite cancelar a mira do Gancho clicando novamente no botão
	if S.busy == "Grapple" and id == "Grapple" and aimCallback then
		aimCallback = nil
		S.cancelAim = true
		return
	end

	if S.busy ~= nil or os.clock() < (S.cd[id] or 0) or not alive(S.gen) then
		UI.DenyFeedback(id)
		return
	end

	if id == "Jump" and S.hum.FloorMaterial == Enum.Material.Air then
		UI.DenyFeedback(id)
		return
	end

	S.busy = id
	S.cancelAim = false
	local ctx = NewCtx(S.gen)

	task.spawn(function()
		local ok, result = pcall(ABILITY_HANDLERS[id], ctx, function(visible, text)
			if UI.banner then
				if text then UI.banner.Text = text end
				UI.banner.Visible = visible and true or false
			end
		end)
		ctx.maid:Clean()

		if not ok and result ~= "CANCEL" then
			warn("[RegenMovesetV2] Erro em " .. tostring(id) .. ": " .. tostring(result))
		end

		-- Não aplica tempo de recarga se o Gancho foi cancelado ou clicou fora de alcance
		if not (id == "Grapple" and ok and result == false) then
			S.cd[id] = os.clock() + (CFG.Cooldown[id] or 5)
		end

		S.busy = nil
	end)
end

UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if aimCallback and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		aimCallback(Vector2.new(input.Position.X, input.Position.Y))
		return
	end

	for _, def in ipairs(BUTTON_DEFS) do
		if input.KeyCode == def.key then
			TryUseAbility(def.id)
			return
		end
	end
end)

local function OnCharacterAdded(char)
	S.gen += 1
	S.busy = nil
	S.char = char
	S.hum = char:WaitForChild("Humanoid")
	S.root = char:WaitForChild("HumanoidRootPart")
	S.r6 = (S.hum.RigType == Enum.HumanoidRigType.R6)

	if not S.r6 then
		char:WaitForChild("UpperTorso", 5)
		char:WaitForChild("RightHand", 5)
		char:WaitForChild("LeftFoot", 5)
	end

	S.hum.Died:Connect(function()
		S.gen += 1
		S.busy = nil
	end)
end

UI.Build()
if player.Character then
	task.spawn(OnCharacterAdded, player.Character)
end
player.CharacterAdded:Connect(OnCharacterAdded)
