--[[
	LobbyAudit — contrôle (et correction) des défauts d'affichage du lobby (Workspace.DClassBlock).

	À exécuter dans Studio, mode Édition (barre de commande, ou via MCP) :
		local Audit = loadstring(<ce fichier>)()   -- ou coller le contenu
		print(Audit.report())     -- liste les problèmes, ne modifie rien
		print(Audit.fix())        -- corrige ce qui peut l'être, puis renvoie le rapport

	Ce que le rapport liste :
	  1. paires de pièces ayant des faces coplanaires qui se superposent (même orientation → z-fighting) ;
	  2. pièces entièrement contenues dans une autre pièce opaque ;
	  3. pièces (ou groupes de pièces) qui flottent : aucun contact, même indirect, avec le sol.

	Ce que fix() corrige :
	  - décor fin (panneaux, affiches, moulures, plinthes, bandes…) : décollé à 0,05 stud de son support,
	    SurfaceGui tournée vers l'extérieur, CastShadow = false ;
	  - faces coplanaires entre pièces de structure : la plus petite pièce est rentrée de 0,04 stud ;
	  - pièces cachées dans une autre : supprimées (sauf si elles portent une lumière, un texte, un tag…) ;
	  - SurfaceGui à mise en page proportionnelle : PixelsPerStud = 50, TextScaled = true.
	Les pièces des portes coulissantes (tags CellDoor / SecurityDoor) ne sont jamais modifiées.
]]

local CollectionService = game:GetService("CollectionService")

local Audit = {}

local ROOT = workspace:FindFirstChild("DClassBlock")
local PLANE_EPS = 0.02 -- deux faces à moins de 0,02 stud l'une de l'autre = même plan
local AREA_MIN = 0.02 -- surface de recouvrement minimale signalée (stud²)
local DECOR_GAP = 0.05 -- distance entre un décor et son support
local RECESS = 0.04 -- retrait appliqué à la plus petite pièce d'une paire coplanaire
local TOUCH = 0.12 -- tolérance de contact pour le test « flotte »

local DECOR_NAMES = {
	"Sign", "Poster", "Label", "Stencil", "Number", "Matricule", "DoorFrame", "Trim", "Skirting",
	"Stripe", "Hazard", "Line", "Tally", "Calendar", "Paper", "Note", "Graffiti", "Clue", "Text",
	"Menu", "Arrow", "Patch", "Logo", "Notice", "Mark", "Molding", "Moulure", "Plaque",
}

-------------------------------------------------------------------------------- utilitaires

local AXES = { "X", "Y", "Z" }

local function isBox(p)
	return p:IsA("Part") and p.Shape == Enum.PartType.Block
end

local function visible(p)
	return p.Transparency < 0.95
end

local function opaque(p)
	return p.Transparency < 0.3 and p.Material ~= Enum.Material.Glass and p.Material ~= Enum.Material.ForceField
end

local function inDoor(p)
	local a = p.Parent
	while a and a ~= ROOT and a ~= workspace do
		if CollectionService:HasTag(a, "CellDoor") or CollectionService:HasTag(a, "SecurityDoor") then
			return true
		end
		a = a.Parent
	end
	return false
end

local function localAxes(cf)
	return { cf.RightVector, cf.UpVector, -cf.LookVector }
end

local function halves(p)
	local h = p.Size / 2
	return { h.X, h.Y, h.Z }
end

local function thinAxis(p)
	local s = p.Size
	local t = { s.X, s.Y, s.Z }
	local i = 1
	for k = 2, 3 do
		if t[k] < t[i] then
			i = k
		end
	end
	return i, t[i]
end

local function isDecor(p)
	-- un support invisible qui porte un texte peint (graffiti, pochoir) compte aussi : son texte ne doit pas être dans le plan du mur
	if not isBox(p) or not (visible(p) or p:FindFirstChildWhichIsA("SurfaceGui")) then
		return false
	end
	local _, mn = thinAxis(p)
	if mn > 0.35 then
		return false
	end
	if mn <= 0.12 then
		return true
	end
	if p:FindFirstChildWhichIsA("SurfaceGui") or p:FindFirstChildWhichIsA("Decal") then
		return true
	end
	for _, n in ipairs(DECOR_NAMES) do
		if string.find(p.Name, n, 1, true) then
			return true
		end
	end
	return false
end

local function short(p)
	return (p:GetFullName():gsub("^Workspace%.DClassBlock%.", ""))
end

local function allParts()
	local list = {}
	if not ROOT then
		return list
	end
	for _, d in ipairs(ROOT:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Faces d'une pièce : normale, centre, base du plan, demi-dimensions
local function facesOf(p)
	local cf = p.CFrame
	local w = localAxes(cf)
	local h = halves(p)
	local out = {}
	for i = 1, 3 do
		local j, k = i % 3 + 1, (i + 1) % 3 + 1
		for _, s in ipairs({ 1, -1 }) do
			local n = w[i] * s
			table.insert(out, {
				part = p, axis = i, sign = s, n = n,
				c = cf.Position + n * h[i], u = w[j], v = w[k], hu = h[j], hv = h[k],
			})
		end
	end
	return out
end

-- Surface de recouvrement de deux faces parallèles (approximation par boîte englobante dans le plan de A)
local function overlapArea(fa, fb)
	local d = fb.c - fa.c
	local dx, dy = d:Dot(fa.u), d:Dot(fa.v)
	local ex = math.abs(fb.u:Dot(fa.u)) * fb.hu + math.abs(fb.v:Dot(fa.u)) * fb.hv
	local ey = math.abs(fb.u:Dot(fa.v)) * fb.hu + math.abs(fb.v:Dot(fa.v)) * fb.hv
	local ox = math.min(fa.hu, dx + ex) - math.max(-fa.hu, dx - ex)
	local oy = math.min(fa.hv, dy + ey) - math.max(-fa.hv, dy - ey)
	if ox > 0.005 and oy > 0.005 then
		return ox * oy
	end
	return 0
end

local function normalKey(n)
	return string.format("%d,%d,%d", math.round(n.X * 200), math.round(n.Y * 200), math.round(n.Z * 200))
end

local function isInside(a, b)
	local hb = b.Size / 2 + Vector3.new(0.01, 0.01, 0.01)
	local ha = a.Size / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local wp = a.CFrame:PointToWorldSpace(Vector3.new(sx * ha.X, sy * ha.Y, sz * ha.Z))
				local lp = b.CFrame:PointToObjectSpace(wp)
				if math.abs(lp.X) > hb.X or math.abs(lp.Y) > hb.Y or math.abs(lp.Z) > hb.Z then
					return false
				end
			end
		end
	end
	return true
end

local function volume(p)
	return p.Size.X * p.Size.Y * p.Size.Z
end

local function precious(p)
	-- pièce qu'on ne supprime jamais automatiquement
	if #CollectionService:GetTags(p) > 0 then
		return true
	end
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Light") or c:IsA("SurfaceGui") or c:IsA("Decal") or c:IsA("Sound") or c:IsA("ParticleEmitter")
			or c:IsA("ProximityPrompt") or c:IsA("ClickDetector") or c:IsA("Attachment") then
			return true
		end
	end
	local m = p:FindFirstAncestorWhichIsA("Model")
	return m ~= nil and m.PrimaryPart == p
end

-------------------------------------------------------------------------------- détections

function Audit.coplanarPairs()
	local groups = {}
	for _, p in ipairs(allParts()) do
		if isBox(p) and visible(p) then
			for _, f in ipairs(facesOf(p)) do
				local key = normalKey(f.n)
				local g = groups[key]
				if not g then
					g = {}
					groups[key] = g
				end
				f.d = f.n:Dot(f.c)
				table.insert(g, f)
			end
		end
	end
	local pairsOut = {}
	for _, g in pairs(groups) do
		table.sort(g, function(a, b)
			return a.d < b.d
		end)
		for i = 1, #g do
			local fa = g[i]
			for j = i + 1, #g do
				local fb = g[j]
				if fb.d - fa.d > PLANE_EPS then
					break
				end
				if fa.part ~= fb.part then
					local area = overlapArea(fa, fb)
					if area > AREA_MIN then
						table.insert(pairsOut, { a = fa, b = fb, area = area })
					end
				end
			end
		end
	end
	table.sort(pairsOut, function(x, y)
		return x.area > y.area
	end)
	return pairsOut
end

function Audit.containedParts()
	local out = {}
	local params = OverlapParams.new()
	for i, a in ipairs(allParts()) do
		if visible(a) then
			for _, b in ipairs(workspace:GetPartBoundsInBox(a.CFrame, a.Size, params)) do
				if b ~= a and b:IsDescendantOf(ROOT) and isBox(b) and opaque(b) and volume(b) >= volume(a) and isInside(a, b) then
					table.insert(out, { part = a, host = b })
					break
				end
			end
		end
		if i % 300 == 0 then
			task.wait()
		end
	end
	return out
end

function Audit.floatingGroups()
	local parts = allParts()
	local index, grounded, adj = {}, {}, {}
	for i, p in ipairs(parts) do
		index[p] = i
		adj[i] = {}
	end
	local params = OverlapParams.new()
	local pad = Vector3.new(TOUCH, TOUCH, TOUCH) * 2
	for i, p in ipairs(parts) do
		for _, q in ipairs(workspace:GetPartBoundsInBox(p.CFrame, p.Size + pad, params)) do
			local j = index[q]
			if j then
				if j ~= i then
					table.insert(adj[i], j)
					table.insert(adj[j], i)
				end
			elseif q:IsA("BasePart") and q.Anchored then
				grounded[i] = true -- touche le Baseplate ou autre chose hors du lobby
			end
		end
		if i % 300 == 0 then
			task.wait()
		end
	end
	-- parcours depuis tout ce qui touche le sol
	local seen, queue = {}, {}
	for i in pairs(grounded) do
		seen[i] = true
		table.insert(queue, i)
	end
	local head = 1
	while queue[head] do
		local i = queue[head]
		head += 1
		for _, j in ipairs(adj[i]) do
			if not seen[j] then
				seen[j] = true
				table.insert(queue, j)
			end
		end
	end
	-- regroupe les pièces non atteintes en îlots
	local groupsOut = {}
	for i, p in ipairs(parts) do
		if not seen[i] and visible(p) then
			local group, stack = {}, { i }
			seen[i] = true
			while #stack > 0 do
				local k = table.remove(stack)
				table.insert(group, parts[k])
				for _, j in ipairs(adj[k]) do
					if not seen[j] then
						seen[j] = true
						table.insert(stack, j)
					end
				end
			end
			table.insert(groupsOut, group)
		end
	end
	return groupsOut
end

-------------------------------------------------------------------------------- corrections

-- Décolle un décor fin de son support (mur, sol, meuble) à DECOR_GAP
local function settleDecor(p)
	local i, thick = thinAxis(p)
	local w = localAxes(p.CFrame)
	local h = halves(p)
	local found = {} -- found[s] = face avant la plus saillante d'un support situé derrière le côté s
	for _, s in ipairs({ 1, -1 }) do
		local n = w[i] * s -- côté « avant » supposé
		local back = p.Position - n * h[i]
		local probeSize = p.Size * 0.8
		local sz = { probeSize.X, probeSize.Y, probeSize.Z }
		sz[i] = 0.7
		local probeCF = CFrame.new(back - n * 0.3) * p.CFrame.Rotation
		for _, wpart in ipairs(workspace:GetPartBoundsInBox(probeCF, Vector3.new(sz[1], sz[2], sz[3]), OverlapParams.new())) do
			if wpart ~= p and wpart:IsDescendantOf(ROOT) and isBox(wpart) and visible(wpart) and not inDoor(wpart) then
				-- le support doit avoir une face alignée sur n et être plus épais que le décor
				local wa = localAxes(wpart.CFrame)
				local wh = halves(wpart)
				for k = 1, 3 do
					local dot = wa[k]:Dot(n)
					if math.abs(dot) > 0.999 and wpart.Size[AXES[k]] > thick + 0.01 then
						local front = n:Dot(wpart.Position) + wh[k]
						local backD = n:Dot(back)
						if backD > front - 0.6 and backD < front + 0.04 then
							-- le décor doit être en face du support (recouvrement dans le plan)
							local fd = { c = back, u = w[i % 3 + 1], v = w[(i + 1) % 3 + 1], hu = h[i % 3 + 1], hv = h[(i + 1) % 3 + 1] }
							local j2, k2 = k % 3 + 1, (k + 1) % 3 + 1
							local fw = { c = wpart.Position + n * wh[k], u = wa[j2], v = wa[k2], hu = wh[j2], hv = wh[k2] }
							if overlapArea(fd, fw) > 0.3 * (fd.hu * fd.hv * 4) then
								if not found[s] or front > found[s].front then
									found[s] = { n = n, front = front }
								end
							end
						end
					end
				end
			end
		end
	end
	-- un seul côté doit avoir un support ; sinon (pris en sandwich) on ne touche à rien
	local best = found[1] or found[-1]
	if not best or (found[1] and found[-1]) then
		return false
	end
	local target = best.front + DECOR_GAP + h[i]
	local delta = target - best.n:Dot(p.Position)
	if math.abs(delta) < 0.001 or delta > 0.7 or delta < -0.3 then
		return false
	end
	p.Position += best.n * delta
	-- texte : doit être sur la face avant (côté opposé au support)
	for _, g in ipairs(p:GetChildren()) do
		if g:IsA("SurfaceGui") or g:IsA("Decal") then
			local fv = p.CFrame:VectorToWorldSpace(Vector3.FromNormalId(g.Face))
			if fv:Dot(best.n) < -0.99 then
				local axisName = AXES[i]
				local map = {
					X = { Enum.NormalId.Right, Enum.NormalId.Left },
					Y = { Enum.NormalId.Top, Enum.NormalId.Bottom },
					Z = { Enum.NormalId.Back, Enum.NormalId.Front },
				}
				local localSign = (p.CFrame:VectorToObjectSpace(best.n)[axisName] > 0) and 1 or 2
				g.Face = map[axisName][localSign]
			end
		end
	end
	return true
end

local function fixDecor(log)
	local decor = {}
	for _, p in ipairs(allParts()) do
		if isDecor(p) and not inDoor(p) then
			table.insert(decor, p)
		end
	end
	-- du plus épais au plus fin : un autocollant se pose sur sa plaque après que la plaque a bougé
	table.sort(decor, function(a, b)
		return select(2, thinAxis(a)) > select(2, thinAxis(b))
	end)
	local moved = 0
	for _, p in ipairs(decor) do
		p.CastShadow = false
		if settleDecor(p) then
			moved += 1
		end
	end
	table.insert(log, string.format("décor : %d pièces fines (ombres coupées), %d décollées de %.2f stud", #decor, moved, DECOR_GAP))
	return decor
end

local function fixCoplanar(log)
	local total = 0
	for pass = 1, 4 do
		local done = {}
		local n = 0
		for _, pr in ipairs(Audit.coplanarPairs()) do
			local fa, fb = pr.a, pr.b
			local pa, pb = fa.part, fb.part
			if not inDoor(pa) and not inDoor(pb) then
				-- on rentre la pièce dont la face est la plus petite (le « bout » qui dépasse dans le plan de l'autre)
				local f = (fa.hu * fa.hv <= fb.hu * fb.hv) and fa or fb
				local p = f.part
				local key = p:GetDebugId() .. f.axis .. f.sign
				if not done[key] and p.Size[AXES[f.axis]] > 0.2 then
					done[key] = true
					local s = p.Size
					local t = { s.X, s.Y, s.Z }
					t[f.axis] -= RECESS
					p.Size = Vector3.new(t[1], t[2], t[3])
					p.Position -= f.n * (RECESS / 2)
					n += 1
				elseif not done[key] and isDecor(p) then
					-- décor fin coplanaire avec une autre pièce : on l'avance
					done[key] = true
					p.Position += f.n * DECOR_GAP
					n += 1
				end
			end
		end
		total += n
		if n == 0 then
			break
		end
	end
	table.insert(log, string.format("faces coplanaires : %d faces rentrées / avancées", total))
end

local function fixContained(log)
	local removed, kept = 0, 0
	for _, it in ipairs(Audit.containedParts()) do
		local p = it.part
		-- le décor (bandes au sol, affiches…) est déjà recalé par fixDecor : on ne le supprime pas
		if p.Parent and not inDoor(p) and not precious(p) and not isDecor(p) then
			p:Destroy()
			removed += 1
		else
			kept += 1
		end
	end
	table.insert(log, string.format("pièces cachées dans une autre : %d supprimées, %d gardées (lumière, texte, tag…)", removed, kept))
end

-- Recolle chaque îlot flottant contre la surface la plus proche (à moins d'1 stud), dans l'une des 6 directions
local function fixFloating(log)
	local snapped, left = 0, {}
	local dirs = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }
	for _, group in ipairs(Audit.floatingGroups()) do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = group
		local bestD, bestDist = nil, 1.0
		for _, d in ipairs(dirs) do
			for _, p in ipairs(group) do
				local hit = workspace:Blockcast(p.CFrame, p.Size, d * 1.0, params)
				if hit and hit.Distance < bestDist and visible(hit.Instance) then
					bestD, bestDist = d, hit.Distance
				end
			end
		end
		if bestD and not inDoor(group[1]) then
			for _, p in ipairs(group) do
				p.Position += bestD * bestDist
			end
			snapped += 1
		else
			table.insert(left, short(group[1]))
		end
	end
	table.insert(log, string.format("îlots flottants recollés : %d%s", snapped,
		#left > 0 and (" ; sans support proche : " .. table.concat(left, ", ")) or ""))
end

local function scaleOnly(gui)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiObject") then
			if d.Size.X.Offset ~= 0 or d.Size.Y.Offset ~= 0 or d.Position.X.Offset ~= 0 or d.Position.Y.Offset ~= 0 then
				return false
			end
		end
	end
	return true
end

local function fixText(log)
	local fixed, skipped = 0, 0
	for _, g in ipairs(ROOT:GetDescendants()) do
		if g:IsA("SurfaceGui") and g.Adornee == nil then
			if scaleOnly(g) then
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = 50
				for _, l in ipairs(g:GetDescendants()) do
					if l:IsA("TextLabel") or l:IsA("TextBox") then
						l.TextScaled = true
						if string.find(l.Text, "\n") then
							l.TextWrapped = true
						end
					end
				end
				fixed += 1
			else
				skipped += 1
			end
		end
	end
	table.insert(log, string.format("textes : %d SurfaceGui en PixelsPerStud 50 + TextScaled, %d à mise en page fixe laissées telles quelles", fixed, skipped))
end

-------------------------------------------------------------------------------- rapport

function Audit.report(maxLines)
	maxLines = maxLines or 40
	if not ROOT then
		return "Workspace.DClassBlock introuvable"
	end
	local lines = {}
	local function add(s)
		table.insert(lines, s)
	end

	local cp = Audit.coplanarPairs()
	add(string.format("== FACES COPLANAIRES QUI SE SUPERPOSENT : %d paires", #cp))
	for i = 1, math.min(#cp, maxLines) do
		local pr = cp[i]
		add(string.format("  %s  <->  %s   (face %s%s, %.2f stud²)", short(pr.a.part), short(pr.b.part),
			pr.a.sign > 0 and "+" or "-", AXES[pr.a.axis], pr.area))
	end

	local ct = Audit.containedParts()
	add(string.format("== PIÈCES ENTIÈREMENT CONTENUES DANS UNE AUTRE : %d", #ct))
	for i = 1, math.min(#ct, maxLines) do
		add(string.format("  %s  dans  %s", short(ct[i].part), short(ct[i].host)))
	end

	local fl = Audit.floatingGroups()
	local n = 0
	for _, g in ipairs(fl) do
		n += #g
	end
	add(string.format("== PIÈCES QUI FLOTTENT : %d îlots, %d pièces", #fl, n))
	for i = 1, math.min(#fl, maxLines) do
		local g = fl[i]
		local p = g[1]
		add(string.format("  %s%s  à (%.1f, %.1f, %.1f)", short(p), #g > 1 and string.format(" (+%d pièces liées)", #g - 1) or "",
			p.Position.X, p.Position.Y, p.Position.Z))
	end
	return table.concat(lines, "\n")
end

function Audit.fix()
	local log = { "== CORRECTIONS" }
	fixDecor(log)
	fixContained(log)
	fixCoplanar(log)
	fixFloating(log)
	fixText(log)
	return table.concat(log, "\n") .. "\n\n" .. Audit.report()
end

return Audit
