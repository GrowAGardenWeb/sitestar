--[[
	Studs AI — Generador de modelos 3D estilo "studs" con IA para Roblox Studio
	---------------------------------------------------------------------------
	Describe un modelo (personaje, animal, vehículo...) y las animaciones que quieres.
	El plugin le pide a Claude una especificación JSON y construye en Studio:
	  • Partes con superficies de studs (estilo Roblox clásico)
	  • Un rig con HumanoidRootPart + Motor6D (animable)
	  • AnimationController + Animator
	  • KeyframeSequences dentro de "AnimSaves" (compatibles con el Animation Editor)

	Instalación: copia este archivo en tu carpeta de Plugins de Roblox Studio
	(Studio → pestaña Plugins → "Plugins Folder") y reinicia Studio.
]]

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")

local API_URL = "https://api.anthropic.com/v1/messages"
local DEFAULT_MODEL = "claude-opus-5-5"
local EFFORTS = { "low", "medium", "high" }
local SPEC_VALUE_NAME = "StudsAI_Spec"
local MAX_PARTS = 300

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

local SPEC_FORMAT = [[
COORDINATES: units are studs. +Y is up, the model stands on the ground (lowest point at y = 0).
The model FACES -Z (front = -Z). The model's RIGHT side is +X, its LEFT side is -X.

PART FIELDS:
  "name":     unique PascalCase ASCII name, no spaces (e.g. "LeftArm", "Head", "Tail1").
  "shape":    "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge".
              Cylinder's long axis is X (rotate it to change orientation).
  "size":     [x, y, z] in studs.
  "position": [x, y, z] center of the part in model space.
  "rotation": [x, y, z] degrees (Roblox Orientation). Optional, default [0,0,0].
  "color":    [r, g, b] 0-255.
  "material": "SmoothPlastic" (default, best for studs), "Plastic", "Neon", "Glass", "Wood", "Metal"...
  "studs":    true/false. Optional, default true: studs on top, inlets on the bottom.
  "transparency": 0-1. Optional.
  "face":     true to put a classic Roblox smiley face on the part's front (-Z). Use it on heads.
  "parent":   name of the part this part hangs from, or null for the main body part.
              Parts with parent null are attached to an invisible HumanoidRootPart.
              Use exactly ONE main body part with parent null (usually the torso/body).
  "joint":    "motor" (animatable joint, default) or "weld" (rigid decoration: eyes, buttons, details).
  "pivot":    [x, y, z] the joint point in model space, i.e. where the part rotates
              (top of an arm = shoulder, top of a leg = hip, base of the neck, base of a tail...).
              For the main body part use its center.

ANIMATION FIELDS:
  "name":     short name in the user's language (e.g. "Caminar", "Saltar", "Idle").
  "looped":   true/false.
  "priority": "Idle" | "Movement" | "Action" | "Core".
  "length":   total duration in seconds. If looped, the first pose is repeated at "length" automatically.
  "keyframes": list ordered by time. Each keyframe:
      "time":   seconds.
      "easing": "Linear" | "Constant" | "Cubic" | "Elastic" | "Bounce" (optional, default "Cubic").
      "direction": "In" | "Out" | "InOut" (optional, default "InOut").
      "poses":  { "PartName": { "rotation": [x, y, z], "position": [x, y, z] } }
                rotation in degrees (Euler XYZ) around the joint pivot, position offset in studs.
                Both are RELATIVE to the rest pose; [0,0,0] = rest pose.
                Only parts with joint "motor" can be posed. To move/bob/jump/turn the whole body,
                pose the main body part (parent null).
                Joints you omit keep the value they had in the previous keyframe.

ROTATION AXES (at rest, joint axes are aligned with the model axes):
  + X rotation swings a downward-hanging limb FORWARD (towards -Z); negative swings it backward.
  + Z rotation swings a downward-hanging limb towards the model's RIGHT (+X).
  + Y rotation turns a part towards the model's LEFT (e.g. head looks left).
  Walking: legs alternate about ±30° on X, arms opposite to legs, body bobs slightly on Y.
]]

local SYSTEM_PROMPT = [[
You are a Roblox 3D modeler and animator. You design blocky, classic "studs" style Roblox models
(like 2008-2012 Roblox and LEGO): chunky blocks, clean proportions, bright solid colors,
SmoothPlastic with studs, recognizable silhouettes, usually 8-60 parts. A humanoid is about
5-6 studs tall (classic: legs 1x2x1, torso 2x2x1, arms 1x2x1, head 2x1x1).

You answer ONLY with one JSON object and nothing else: no prose, no markdown fences.

Rules for a good rig:
- Every part that should move (limbs, head, tail, wings, wheels, jaw...) is a "motor" joint
  with a correct pivot at the point where it rotates.
- Decorative parts (eyes, nose, buttons, belt, spots) use "joint": "weld" and their parent is
  the part they sit on, so they follow it when it is animated.
- Chains (tail, neck, tentacles) are several motor parts, each parented to the previous one.
- Parts must touch or slightly overlap their parent; no floating parts.
- Animations must loop smoothly when looped, read clearly, and match the rig's anatomy.
- If the user doesn't ask for animations, create "Idle" and "Caminar" (walk) animations.
- Use the user's language for animation names.

]] .. SPEC_FORMAT

local CREATE_INSTRUCTIONS = [[
Create a new model. Return:
{"name": "...", "parts": [ ...part objects... ], "animations": [ ...animation objects... ]}

User request:
]]

local MODIFY_INSTRUCTIONS = [[
Here is the current model spec (JSON). Apply the user's change and return the COMPLETE updated
spec in the same format {"name", "parts", "animations"}. Keep everything the user didn't ask to
change. If you rename or remove parts, update the animations accordingly.

Current spec:
%s

User change:
%s
]]

local ANIMATE_INSTRUCTIONS = [[
Here is an existing rig (JSON). Each motor joint lists its parent and the pivot point in model space.
"jointFrameRotation" is the rotation (degrees, Roblox Orientation) of that joint's frame relative
to the model; when it is not [0,0,0] the rotation axes described above are rotated by it, so
compensate. Only parts listed in "joints" can be posed. The root body part's joint is named by its
part name too.

Create ONLY the animations the user asks for. Return:
{"animations": [ ...animation objects... ]}

Rig:
%s

User request:
%s
]]

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function getSetting(key, default)
	local ok, value = pcall(function()
		return plugin:GetSetting(key)
	end)
	if ok and value ~= nil then
		return value
	end
	return default
end

local function setSetting(key, value)
	pcall(function()
		plugin:SetSetting(key, value)
	end)
end

local state = {
	apiKey = getSetting("StudsAI_ApiKey", ""),
	model = getSetting("StudsAI_Model", DEFAULT_MODEL),
	effort = getSetting("StudsAI_Effort", "medium"),
	busy = false,
}

--------------------------------------------------------------------------------
-- Claude API
--------------------------------------------------------------------------------

local function supportsFallback(model)
	return model:match("^claude%-opus%-5") ~= nil
		or model == "claude-sonnet-5-5"
		or model:match("^claude%-fable%-5%-1") ~= nil
end

local function extractJson(text)
	local first = text:find("{", 1, true)
	local last
	for i = #text, 1, -1 do
		if text:sub(i, i) == "}" then
			last = i
			break
		end
	end
	if not first or not last or last < first then
		return nil, "La respuesta no contiene JSON."
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(text:sub(first, last))
	end)
	if not ok then
		return nil, "No se pudo leer el JSON de la respuesta: " .. tostring(data)
	end
	return data
end

-- Returns (decodedJson, nil) or (nil, errorMessage)
local function askClaude(userText)
	if state.apiKey == "" then
		return nil, "Pega tu API key de Anthropic arriba (console.anthropic.com)."
	end

	local body = {
		model = state.model,
		max_tokens = 16000,
		system = SYSTEM_PROMPT,
		output_config = { effort = state.effort },
		messages = {
			{ role = "user", content = userText },
		},
	}
	local headers = {
		["x-api-key"] = state.apiKey,
		["anthropic-version"] = "2023-06-01",
		["content-type"] = "application/json",
	}
	if supportsFallback(state.model) then
		-- If the model declines, the API retries automatically on Anthropic's recommended fallback model.
		body.fallbacks = "default"
		headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
	end

	local ok, response = pcall(function()
		return HttpService:RequestAsync({
			Url = API_URL,
			Method = "POST",
			Headers = headers,
			Body = HttpService:JSONEncode(body),
		})
	end)
	if not ok then
		return nil, "Error de conexión: " .. tostring(response)
			.. "\n(Acepta el permiso HTTP del plugin para api.anthropic.com. Si fue un timeout, prueba con esfuerzo 'low' o el modelo claude-sonnet-5-5.)"
	end

	local decodedOk, data = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)
	if not response.Success then
		local message = decodedOk and data and data.error and data.error.message or response.Body
		return nil, ("Error de la API (%d): %s"):format(response.StatusCode, tostring(message))
	end
	if not decodedOk then
		return nil, "Respuesta inválida de la API."
	end

	if data.stop_reason == "refusal" then
		return nil, "Claude rechazó esta petición. Prueba a reformularla."
	end

	local text = {}
	for _, block in ipairs(data.content or {}) do
		if block.type == "text" and block.text then
			table.insert(text, block.text)
		end
	end
	local fullText = table.concat(text)

	if data.stop_reason == "max_tokens" then
		return nil, "La respuesta se cortó por ser demasiado larga. Pide un modelo con menos piezas o menos animaciones."
	end

	return extractJson(fullText)
end

--------------------------------------------------------------------------------
-- Model building
--------------------------------------------------------------------------------

local function vec3(t, default)
	if type(t) ~= "table" then
		return default or Vector3.zero
	end
	return Vector3.new(tonumber(t[1]) or 0, tonumber(t[2]) or 0, tonumber(t[3]) or 0)
end

local function enumItem(enumType, name, default)
	if type(name) ~= "string" then
		return default
	end
	local ok, item = pcall(function()
		return enumType[name]
	end)
	return ok and item or default
end

local function color3(t, default)
	if type(t) ~= "table" then
		return default
	end
	local function c(v)
		return math.clamp(tonumber(v) or 0, 0, 255)
	end
	return Color3.fromRGB(c(t[1]), c(t[2]), c(t[3]))
end

local function makePart(p)
	local shape = p.shape or "Block"
	local part
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		part = Instance.new("CornerWedgePart")
	else
		part = Instance.new("Part")
		if shape == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif shape == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		end
	end

	local size = vec3(p.size, Vector3.new(1, 1, 1))
	part.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	local rot = vec3(p.rotation)
	part.CFrame = CFrame.new(vec3(p.position))
		* CFrame.fromOrientation(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
	part.Color = color3(p.color, Color3.fromRGB(163, 162, 165))
	part.Material = enumItem(Enum.Material, p.material, Enum.Material.SmoothPlastic)
	part.Transparency = math.clamp(tonumber(p.transparency) or 0, 0, 1)

	if p.studs ~= false then
		part.TopSurface = Enum.SurfaceType.Studs
		part.BottomSurface = Enum.SurfaceType.Inlet
	else
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end

	part.Anchored = false
	part.CanCollide = false
	part.CastShadow = true

	if p.face then
		local face = Instance.new("Decal")
		face.Name = "face"
		face.Face = Enum.NormalId.Front
		face.Texture = "rbxasset://textures/face.png"
		face.Parent = part
	end

	return part
end

-- Builds the rig from a spec. Returns (model, warnings)
local function buildModel(spec)
	local warnings = {}
	local model = Instance.new("Model")
	model.Name = (type(spec.name) == "string" and spec.name ~= "") and spec.name or "ModeloIA"

	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Transparency = 1
	hrp.CanCollide = false
	hrp.Anchored = true
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.TopSurface = Enum.SurfaceType.Smooth
	hrp.BottomSurface = Enum.SurfaceType.Smooth
	hrp.Parent = model
	model.PrimaryPart = hrp

	-- 1) Parts
	local parts, defs, order = {}, {}, {}
	for i, p in ipairs(spec.parts) do
		if i > MAX_PARTS then
			table.insert(warnings, ("Se ignoraron las piezas a partir de la %d."):format(MAX_PARTS + 1))
			break
		end
		local name = (type(p.name) == "string" and p.name ~= "") and p.name or ("Part" .. i)
		name = name:gsub("%s+", "")
		if name == "HumanoidRootPart" then
			name = "Body"
		end
		if parts[name] then
			local n = 2
			while parts[name .. n] do
				n += 1
			end
			table.insert(warnings, ("Nombre repetido '%s' → '%s'"):format(name, name .. n))
			name = name .. n
		end
		local part = makePart(p)
		part.Name = name
		part.Parent = model
		parts[name] = part
		defs[name] = p
		table.insert(order, name)
	end

	-- Root body position: the first part with parent null
	for _, name in ipairs(order) do
		local parentName = defs[name].parent
		if parentName == nil or parentName == "HumanoidRootPart" then
			hrp.CFrame = CFrame.new(parts[name].Position)
			break
		end
	end

	-- 2) Resolve parents (avoid missing parents and cycles)
	local parentOf = {}
	for _, name in ipairs(order) do
		local parentName = defs[name].parent
		if type(parentName) == "string" and parentName ~= "HumanoidRootPart" and parentName ~= name then
			if parts[parentName] then
				parentOf[name] = parentName
			else
				table.insert(warnings, ("'%s' tiene un padre inexistente '%s'; se une al cuerpo."):format(name, parentName))
			end
		end
	end
	for _, name in ipairs(order) do
		local seen, cur = { [name] = true }, parentOf[name]
		while cur do
			if seen[cur] then
				table.insert(warnings, ("Ciclo de padres en '%s'; se une al cuerpo."):format(name))
				parentOf[name] = nil
				break
			end
			seen[cur] = true
			cur = parentOf[cur]
		end
	end

	-- 3) Joints
	for _, name in ipairs(order) do
		local part = parts[name]
		local parentPart = parentOf[name] and parts[parentOf[name]] or hrp
		local def = defs[name]

		if def.joint == "weld" and parentPart ~= hrp then
			local weld = Instance.new("WeldConstraint")
			weld.Name = name .. "Weld"
			weld.Part0 = parentPart
			weld.Part1 = part
			weld.Parent = part
		else
			local pivotPos = def.pivot and vec3(def.pivot) or part.Position
			local pivot = CFrame.new(pivotPos)
			local motor = Instance.new("Motor6D")
			motor.Name = name
			motor.Part0 = parentPart
			motor.Part1 = part
			motor.C0 = parentPart.CFrame:Inverse() * pivot
			motor.C1 = part.CFrame:Inverse() * pivot
			motor.Parent = parentPart
		end
	end

	-- 4) Animation support
	local controller = Instance.new("AnimationController")
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller

	local animSaves = Instance.new("ObjectValue")
	animSaves.Name = "AnimSaves"
	animSaves.Parent = model

	local specValue = Instance.new("StringValue")
	specValue.Name = SPEC_VALUE_NAME
	specValue.Value = HttpService:JSONEncode(spec)
	specValue.Parent = model

	return model, warnings
end

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

-- childrenOf[parentName] = { childName, ... } following the Motor6D tree from HumanoidRootPart
local function motorTree(model)
	local childrenOf = {}
	for _, m in ipairs(model:GetDescendants()) do
		if m:IsA("Motor6D") and m.Part0 and m.Part1 then
			local list = childrenOf[m.Part0.Name] or {}
			table.insert(list, m.Part1.Name)
			childrenOf[m.Part0.Name] = list
		end
	end
	return childrenOf
end

local function poseCFrame(pose)
	if type(pose) ~= "table" then
		return CFrame.identity
	end
	local r = vec3(pose.rotation)
	return CFrame.new(vec3(pose.position)) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

local function buildKeyframeSequence(model, anim, warnings)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = (type(anim.name) == "string" and anim.name ~= "") and anim.name or "Animacion"
	kfs.Loop = anim.looped ~= false
	kfs.Priority = enumItem(Enum.AnimationPriority, anim.priority, Enum.AnimationPriority.Core)

	local rootName = model.PrimaryPart and model.PrimaryPart.Name or "HumanoidRootPart"
	local childrenOf = motorTree(model)
	local animatable = {}
	for _, list in pairs(childrenOf) do
		for _, n in ipairs(list) do
			animatable[n] = true
		end
	end

	local keyframes = {}
	for _, kf in ipairs(type(anim.keyframes) == "table" and anim.keyframes or {}) do
		if type(kf) == "table" then
			table.insert(keyframes, kf)
		end
	end
	table.sort(keyframes, function(a, b)
		return (tonumber(a.time) or 0) < (tonumber(b.time) or 0)
	end)
	if #keyframes == 0 then
		table.insert(warnings, ("La animación '%s' no tiene keyframes."):format(kfs.Name))
		return kfs
	end

	-- Close the loop: repeat the first keyframe at "length"
	local length = tonumber(anim.length)
	local lastTime = tonumber(keyframes[#keyframes].time) or 0
	if kfs.Loop and length and length > lastTime + 1e-3 then
		local first = keyframes[1]
		table.insert(keyframes, {
			time = length,
			easing = first.easing,
			direction = first.direction,
			poses = first.poses,
		})
	end

	local unknown = {}
	local current = {} -- partName -> CFrame (carried over between keyframes)

	for _, kfDef in ipairs(keyframes) do
		for partName, pose in pairs(type(kfDef.poses) == "table" and kfDef.poses or {}) do
			if animatable[partName] then
				current[partName] = poseCFrame(pose)
			else
				unknown[partName] = true
			end
		end

		local keyframe = Instance.new("Keyframe")
		keyframe.Time = math.max(tonumber(kfDef.time) or 0, 0)
		local easingStyle = enumItem(Enum.PoseEasingStyle, kfDef.easing, Enum.PoseEasingStyle.Cubic)
		local easingDirection = enumItem(Enum.PoseEasingDirection, kfDef.direction, Enum.PoseEasingDirection.InOut)

		local function addPoses(parentPose, parentName)
			for _, childName in ipairs(childrenOf[parentName] or {}) do
				local pose = Instance.new("Pose")
				pose.Name = childName
				pose.CFrame = current[childName] or CFrame.identity
				pose.Weight = 1
				pose.EasingStyle = easingStyle
				pose.EasingDirection = easingDirection
				pose.Parent = parentPose
				addPoses(pose, childName)
			end
		end

		local rootPose = Instance.new("Pose")
		rootPose.Name = rootName
		rootPose.Weight = 0
		rootPose.Parent = keyframe
		addPoses(rootPose, rootName)
		keyframe.Parent = kfs
	end

	for name in pairs(unknown) do
		table.insert(warnings, ("'%s': la pieza '%s' no es animable o no existe."):format(kfs.Name, name))
	end
	return kfs
end

local function addAnimations(model, animations, warnings)
	local animSaves = model:FindFirstChild("AnimSaves")
	if not animSaves then
		animSaves = Instance.new("ObjectValue")
		animSaves.Name = "AnimSaves"
		animSaves.Parent = model
	end
	local count = 0
	for _, anim in ipairs(type(animations) == "table" and animations or {}) do
		if type(anim) == "table" then
			local kfs = buildKeyframeSequence(model, anim, warnings)
			local existing = animSaves:FindFirstChild(kfs.Name)
			if existing then
				existing:Destroy()
			end
			kfs.Parent = animSaves
			count += 1
		end
	end
	return count
end

-- JSON description of any rig (also R6/R15) so Claude can animate it
local function describeRig(model)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	local base = root and root.CFrame or model:GetPivot()
	local function round(v)
		return math.floor(v * 100 + 0.5) / 100
	end
	local function arr(v)
		return { round(v.X), round(v.Y), round(v.Z) }
	end

	local rig = { name = model.Name, rootPart = root and root.Name, parts = {}, joints = {} }
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= root then
			local rel = base:ToObjectSpace(part.CFrame)
			local rx, ry, rz = rel:ToOrientation()
			table.insert(rig.parts, {
				name = part.Name,
				size = arr(part.Size),
				position = arr(rel.Position),
				rotation = arr(Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))),
			})
		elseif part:IsA("Motor6D") and part.Part0 and part.Part1 then
			local pivot = base:ToObjectSpace(part.Part0.CFrame * part.C0)
			local rx, ry, rz = pivot:ToOrientation()
			table.insert(rig.joints, {
				part = part.Part1.Name,
				parent = part.Part0.Name,
				pivot = arr(pivot.Position),
				jointFrameRotation = arr(Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))),
			})
		end
	end
	return HttpService:JSONEncode(rig)
end

--------------------------------------------------------------------------------
-- Preview
--------------------------------------------------------------------------------

local preview = { conn = nil, track = nil, model = nil }

local function stopPreview()
	if preview.conn then
		preview.conn:Disconnect()
		preview.conn = nil
	end
	if preview.track then
		pcall(function()
			preview.track:Stop(0)
			preview.track:Destroy()
		end)
		preview.track = nil
	end
	if preview.model then
		for _, m in ipairs(preview.model:GetDescendants()) do
			if m:IsA("Motor6D") then
				m.Transform = CFrame.identity
			end
		end
		preview.model = nil
	end
end

local function findAnimator(model)
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	if animator then
		return animator
	end
	local host = model:FindFirstChildWhichIsA("Humanoid") or model:FindFirstChildWhichIsA("AnimationController")
	if not host then
		host = Instance.new("AnimationController")
		host.Parent = model
	end
	animator = Instance.new("Animator")
	animator.Parent = host
	return animator
end

local function playPreview(model, kfs)
	stopPreview()
	local animator = findAnimator(model)
	local ok, err = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
		preview.track = animator:LoadAnimation(animation)
		preview.track.Looped = true
		preview.track:Play(0)
	end)
	if not ok then
		return false, err
	end
	preview.model = model
	preview.conn = RunService.Heartbeat:Connect(function(dt)
		local stepped = pcall(function()
			animator:StepAnimations(dt)
		end)
		if not stepped then
			stopPreview()
		end
	end)
	return true
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function selectedRig()
	local sel = Selection:Get()[1]
	while sel and sel ~= game do
		if sel:IsA("Model") and (sel:FindFirstChild("HumanoidRootPart") or sel:FindFirstChild(SPEC_VALUE_NAME)) then
			return sel
		end
		sel = sel.Parent
	end
	return nil
end

local function spawnCFrame()
	local camera = workspace.CurrentCamera
	if not camera then
		return CFrame.new(0, 0, 0)
	end
	local camPos = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local pos = camPos + flat.Unit * 20
	pos = Vector3.new(pos.X, 0, pos.Z)
	-- Face the camera (models face -Z, which is the LookVector of lookAt)
	return CFrame.lookAt(pos, Vector3.new(camPos.X, 0, camPos.Z))
end

local function recordUndo(name, fn)
	local recording
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording(name)
	end)
	local ok, err = pcall(fn)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			ok and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel
		)
	else
		ChangeHistoryService:SetWaypoint(name)
	end
	if not ok then
		error(err, 0)
	end
end

local function validSpec(spec)
	return type(spec) == "table" and type(spec.parts) == "table" and #spec.parts > 0
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local toolbar = plugin:CreateToolbar("Studs AI")
local toggleButton = toolbar:CreateButton("Studs AI", "Generar modelos 3D estilo studs con IA", "")
toggleButton.ClickableWhenViewportHidden = true

local widget = plugin:CreateDockWidgetPluginGui(
	"StudsAIWidget",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 360, 640, 300, 400)
)
widget.Title = "Studs AI – Generador 3D"
widget.Name = "StudsAI"

toggleButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggleButton:SetActive(widget.Enabled)
	if not widget.Enabled then
		stopPreview()
	end
end)

local themed = {}
local function bindTheme(inst, prop, styleColor)
	table.insert(themed, { inst, prop, styleColor })
	inst[prop] = settings().Studio.Theme:GetColor(styleColor)
end
settings().Studio.ThemeChanged:Connect(function()
	local theme = settings().Studio.Theme
	for _, t in ipairs(themed) do
		t[1][t[2]] = theme:GetColor(t[3])
	end
end)

local root = Instance.new("ScrollingFrame")
root.Size = UDim2.fromScale(1, 1)
root.BorderSizePixel = 0
root.ScrollBarThickness = 6
root.CanvasSize = UDim2.new()
root.AutomaticCanvasSize = Enum.AutomaticSize.Y
bindTheme(root, "BackgroundColor3", Enum.StudioStyleGuideColor.MainBackground)
root.Parent = widget

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 14)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = root

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = root

local nextOrder = 0
local function place(inst, parent)
	nextOrder += 1
	inst.LayoutOrder = nextOrder
	inst.Parent = parent or root
	return inst
end

local function corner(inst)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = inst
end

local function makeLabel(text, opts)
	opts = opts or {}
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, opts.height or 18)
	label.AutomaticSize = opts.autoHeight and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
	label.Font = opts.bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
	label.TextSize = opts.textSize or 15
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Text = text
	bindTheme(label, "TextColor3", opts.dim and Enum.StudioStyleGuideColor.DimmedText or Enum.StudioStyleGuideColor.MainText)
	return place(label, opts.parent)
end

local function makeTextBox(placeholder, height, multiline)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height)
	box.ClearTextOnFocus = false
	box.MultiLine = multiline or false
	box.TextWrapped = multiline or false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = multiline and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center
	box.Font = Enum.Font.SourceSans
	box.TextSize = 15
	box.PlaceholderText = placeholder
	box.Text = ""
	box.BorderSizePixel = 1
	bindTheme(box, "BackgroundColor3", Enum.StudioStyleGuideColor.InputFieldBackground)
	bindTheme(box, "BorderColor3", Enum.StudioStyleGuideColor.InputFieldBorder)
	bindTheme(box, "TextColor3", Enum.StudioStyleGuideColor.MainText)
	bindTheme(box, "PlaceholderColor3", Enum.StudioStyleGuideColor.DimmedText)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, multiline and 4 or 0)
	pad.Parent = box
	corner(box)
	return place(box)
end

local function makeButton(text, primary, parent, width)
	local button = Instance.new("TextButton")
	button.Size = width or UDim2.new(1, 0, 0, 30)
	button.Font = Enum.Font.SourceSansBold
	button.TextSize = 15
	button.Text = text
	button.AutoButtonColor = true
	button.BorderSizePixel = 0
	bindTheme(button, "BackgroundColor3", primary and Enum.StudioStyleGuideColor.DialogMainButton or Enum.StudioStyleGuideColor.Button)
	bindTheme(button, "TextColor3", primary and Enum.StudioStyleGuideColor.DialogMainButtonText or Enum.StudioStyleGuideColor.ButtonText)
	corner(button)
	return place(button, parent)
end

-- API key (masked when not focused)
makeLabel("API key de Anthropic", { bold = true })
local keyBox = makeTextBox("sk-ant-...", 28)
local function maskKey()
	keyBox.Text = state.apiKey ~= "" and string.rep("•", 24) or ""
end
maskKey()
keyBox.Focused:Connect(function()
	keyBox.Text = state.apiKey
end)
keyBox.FocusLost:Connect(function()
	state.apiKey = keyBox.Text:gsub("%s+", "")
	setSetting("StudsAI_ApiKey", state.apiKey)
	maskKey()
end)

-- Model + effort
makeLabel("Modelo de Claude", { bold = true })
local modelBox = makeTextBox(DEFAULT_MODEL, 28)
modelBox.Text = state.model
modelBox.FocusLost:Connect(function()
	local value = modelBox.Text:gsub("%s+", "")
	state.model = value ~= "" and value or DEFAULT_MODEL
	modelBox.Text = state.model
	setSetting("StudsAI_Model", state.model)
end)

local effortButton = makeButton("", false)
local function refreshEffort()
	effortButton.Text = "Esfuerzo: " .. state.effort .. "  (clic para cambiar)"
end
refreshEffort()
effortButton.MouseButton1Click:Connect(function()
	local index = table.find(EFFORTS, state.effort) or 1
	state.effort = EFFORTS[index % #EFFORTS + 1]
	setSetting("StudsAI_Effort", state.effort)
	refreshEffort()
end)

-- Prompt
makeLabel("¿Qué quieres crear o cambiar?", { bold = true })
local promptBox = makeTextBox(
	"Ej: un perro robot naranja con antena, cola de 3 segmentos. Animaciones: caminar, sentarse y mover la cola.",
	110,
	true
)

local createButton = makeButton("🧱  Crear modelo nuevo", true)
local modifyButton = makeButton("✏️  Modificar modelo seleccionado", false)
local animateButton = makeButton("🎬  Añadir animaciones al rig seleccionado", false)

local statusLabel = makeLabel("Listo.", { autoHeight = true, dim = true })

-- Animation list for the selected rig
makeLabel("Animaciones del rig seleccionado", { bold = true })
local animList = Instance.new("Frame")
animList.BackgroundTransparency = 1
animList.Size = UDim2.new(1, 0, 0, 0)
animList.AutomaticSize = Enum.AutomaticSize.Y
place(animList)
local animLayout = Instance.new("UIListLayout")
animLayout.Padding = UDim.new(0, 4)
animLayout.SortOrder = Enum.SortOrder.LayoutOrder
animLayout.Parent = animList

local stopButton = makeButton("⏹  Detener vista previa", false)
stopButton.MouseButton1Click:Connect(stopPreview)

makeLabel(
	"Para usar una animación en tu juego: clic derecho en la KeyframeSequence (dentro de AnimSaves) → \"Save to Roblox\", o ábrela con el Animation Editor y publícala.",
	{ autoHeight = true, dim = true, textSize = 13 }
)

local function setStatus(text, isError)
	statusLabel.Text = text
	if isError then
		warn("[Studs AI] " .. text)
	end
end

local function refreshAnimList()
	for _, child in ipairs(animList:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local model = selectedRig()
	local animSaves = model and model:FindFirstChild("AnimSaves")
	local sequences = {}
	if animSaves then
		for _, child in ipairs(animSaves:GetChildren()) do
			if child:IsA("KeyframeSequence") then
				table.insert(sequences, child)
			end
		end
	end
	if #sequences == 0 then
		makeLabel(model and "Este rig aún no tiene animaciones." or "Selecciona un modelo para ver sus animaciones.", {
			dim = true,
			parent = animList,
		})
		return
	end
	for _, kfs in ipairs(sequences) do
		local button = makeButton("▶  " .. kfs.Name, false, animList)
		button.MouseButton1Click:Connect(function()
			local ok, err = playPreview(model, kfs)
			setStatus(ok and ("Reproduciendo '" .. kfs.Name .. "'.") or ("No se pudo previsualizar: " .. tostring(err)), not ok)
		end)
	end
end

Selection.SelectionChanged:Connect(refreshAnimList)
refreshAnimList()

local function setBusy(busy)
	state.busy = busy
	for _, b in ipairs({ createButton, modifyButton, animateButton }) do
		b.Active = not busy
		b.AutoButtonColor = not busy
		b.TextTransparency = busy and 0.5 or 0
	end
end

local function runTask(working, fn)
	if state.busy then
		return
	end
	setBusy(true)
	setStatus(working)
	task.spawn(function()
		local ok, err = pcall(fn)
		if not ok then
			setStatus("Error: " .. tostring(err), true)
		end
		setBusy(false)
		refreshAnimList()
	end)
end

local function finishMessage(prefix, warnings)
	if #warnings > 0 then
		for _, w in ipairs(warnings) do
			warn("[Studs AI] " .. w)
		end
		return prefix .. ("\n⚠ %d avisos (ver Output)."):format(#warnings)
	end
	return prefix
end

createButton.MouseButton1Click:Connect(function()
	local request = promptBox.Text
	if request:match("^%s*$") then
		setStatus("Escribe primero qué modelo quieres.", true)
		return
	end
	runTask("Generando modelo con Claude… (puede tardar 30-90 s)", function()
		local spec, err = askClaude(CREATE_INSTRUCTIONS .. request)
		if not validSpec(spec) then
			setStatus(err or "Claude no devolvió piezas válidas. Inténtalo de nuevo.", true)
			return
		end
		recordUndo("Studs AI: crear modelo", function()
			stopPreview()
			local model, warnings = buildModel(spec)
			local animCount = addAnimations(model, spec.animations, warnings)
			model:PivotTo(spawnCFrame())
			model.Parent = workspace
			Selection:Set({ model })
			setStatus(finishMessage(
				("✅ '%s' creado: %d piezas, %d animaciones."):format(model.Name, #spec.parts, animCount),
				warnings
			))
		end)
	end)
end)

modifyButton.MouseButton1Click:Connect(function()
	local model = selectedRig()
	local specValue = model and model:FindFirstChild(SPEC_VALUE_NAME)
	if not specValue then
		setStatus("Selecciona un modelo creado con Studs AI para modificarlo.", true)
		return
	end
	local request = promptBox.Text
	if request:match("^%s*$") then
		setStatus("Escribe qué quieres cambiar.", true)
		return
	end
	runTask("Modificando '" .. model.Name .. "'…", function()
		local spec, err = askClaude(MODIFY_INSTRUCTIONS:format(specValue.Value, request))
		if not validSpec(spec) then
			setStatus(err or "Claude no devolvió piezas válidas. Inténtalo de nuevo.", true)
			return
		end
		recordUndo("Studs AI: modificar modelo", function()
			stopPreview()
			local pivot = model:GetPivot()
			local parent = model.Parent
			local newModel, warnings = buildModel(spec)
			local animCount = addAnimations(newModel, spec.animations, warnings)
			newModel:PivotTo(pivot)
			model.Parent = nil -- kept for undo
			newModel.Parent = parent
			Selection:Set({ newModel })
			setStatus(finishMessage(
				("✅ '%s' actualizado: %d piezas, %d animaciones."):format(newModel.Name, #spec.parts, animCount),
				warnings
			))
		end)
	end)
end)

animateButton.MouseButton1Click:Connect(function()
	local model = selectedRig()
	if not model then
		setStatus("Selecciona un rig (un modelo con HumanoidRootPart).", true)
		return
	end
	local request = promptBox.Text
	if request:match("^%s*$") then
		setStatus("Escribe qué animaciones quieres (ej: bailar, atacar con espada, saludar).", true)
		return
	end
	runTask("Creando animaciones para '" .. model.Name .. "'…", function()
		local result, err = askClaude(ANIMATE_INSTRUCTIONS:format(describeRig(model), request))
		if type(result) ~= "table" or type(result.animations) ~= "table" then
			setStatus(err or "Claude no devolvió animaciones. Inténtalo de nuevo.", true)
			return
		end
		recordUndo("Studs AI: añadir animaciones", function()
			stopPreview()
			local warnings = {}
			local count = addAnimations(model, result.animations, warnings)
			if model:FindFirstChild(SPEC_VALUE_NAME) then
				-- Keep the stored spec in sync so "Modificar" preserves these animations
				local specValue = model[SPEC_VALUE_NAME]
				local ok, spec = pcall(function()
					return HttpService:JSONDecode(specValue.Value)
				end)
				if ok and type(spec) == "table" then
					local merged = {}
					local replaced = {}
					for _, anim in ipairs(result.animations) do
						if type(anim) == "table" and anim.name then
							replaced[anim.name] = true
						end
					end
					for _, anim in ipairs(type(spec.animations) == "table" and spec.animations or {}) do
						if type(anim) == "table" and not replaced[anim.name] then
							table.insert(merged, anim)
						end
					end
					for _, anim in ipairs(result.animations) do
						table.insert(merged, anim)
					end
					spec.animations = merged
					specValue.Value = HttpService:JSONEncode(spec)
				end
			end
			setStatus(finishMessage(("✅ %d animaciones añadidas a '%s'."):format(count, model.Name), warnings))
		end)
	end)
end)

plugin.Unloading:Connect(stopPreview)
