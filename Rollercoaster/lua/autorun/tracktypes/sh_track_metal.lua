include("autorun/sh_enums.lua")
include( "autorun/mesh_beams.lua")

local TRACK = TRACK && TRACK:Create()
if !TRACK then return end

TRACK.Name = "Metal Track"
TRACK.Description = "A nice metal coaster"
TRACK.PhysWidth = 30 //How wide the physics mesh should be

trackmanager.Register( EnumNames.Tracks[COASTER_TRACK_METAL], TRACK )
if !CLIENT then return end

TRACK.Material = Material( "coaster/track_metal")

local StrutOffset = 1 //Space between coaster struts
local Offset = 20  //Downwards offset of large center beam
local RailOffset = 25 //Distance track beams away from eachother
local Radius = 10 	//radius of the circular track beams
local PointCount = 7 //how many points make the cylinder of the track mesh

/******************************
Generate function. Generate the IMeshes.
******************************/
function TRACK:Generate( controller )
	if !IsValid( controller ) || !controller:GetIsController() then return end

	self.Cylinder = Cylinder:Create()
	-- Cylinder.Start( Radius, PointCount ) //We're starting up making a beam of cylinders

	local LastAng = nil
	for i = 1, #controller.CatmullRom.Spline do
		-- Double check things
		if #controller.CatmullRom.PointsList < 4 or #controller.CatmullRom.Spline < 4 then continue end 
		if !controller.CatmullRom.PointsList[ #controller.CatmullRom.PointsList ] then continue end 


		local NexterSegment = controller.Nodes[ controller:GetSplineSegment(i) + 2]
		local NextSegment = controller.Nodes[controller:GetSplineSegment(i) + 1]
		local ThisSegment = controller.Nodes[ controller:GetSplineSegment(i) ]

		local AngVec = Vector( 0, 0, 0 )
		local AngVec2 = Vector( 0, 0, 0 )

		if #controller.CatmullRom.Spline >= i + 1 then		
			AngVec = controller.CatmullRom.Spline[i] - controller.CatmullRom.Spline[i + 1]
			AngVec:Normalize()
		else
			AngVec = controller.CatmullRom.Spline[i] - controller.CatmullRom.PointsList[ #controller.CatmullRom.PointsList ]
			AngVec:Normalize()
		end

		if #controller.CatmullRom.Spline >= i + 2 then
			AngVec2 = controller.CatmullRom.Spline[i+1] - controller.CatmullRom.Spline[i+2]
			AngVec2:Normalize()
		else
			AngVec2 = AngVec
		end


		local ang = AngVec:Angle()
		local ang2 = AngVec2:Angle()
		if IsValid( ThisSegment ) && IsValid( NextSegment ) then
			//Get the percent along this node
			local perc = controller:PercAlongNode( i )

			local Roll = -Lerp( perc, math.NormalizeAngle( ThisSegment:GetRoll() ) ,NextSegment:GetRoll())	
			ang:RotateAroundAxis( AngVec, Roll )

			//For shits and giggles get it for this one too
			local perc2 = controller:PercAlongNode( i + 1, true )
			local Roll2 = -Lerp( perc2, math.NormalizeAngle( ThisSegment:GetRoll() ), NextSegment:GetRoll() )
			ang2:RotateAroundAxis( AngVec2, Roll2 )
		end


		if #controller.CatmullRom.Spline >= i+1 then
			local posL = controller.CatmullRom.Spline[i] + ang:Right() * -RailOffset
			local posR = controller.CatmullRom.Spline[i] + ang:Right() * RailOffset
			local nPosL = controller.CatmullRom.Spline[i+1] + ang2:Right() * -RailOffset
			local nPosR = controller.CatmullRom.Spline[i+1] + ang2:Right() * RailOffset

			local vec = controller.CatmullRom.Spline[i] - controller.CatmullRom.Spline[i+1]

			local vec2 = vec

			if #controller.CatmullRom.Spline >= i+2 then
				vec2 = controller.CatmullRom.Spline[i+1] - controller.CatmullRom.Spline[i+2]
			end
			//vec:Normalize() //new
			NewAng = vec:Angle()
			NewAng:RotateAroundAxis( vec:Angle():Right(), 90 )
			NewAng:RotateAroundAxis( vec:Angle():Up(), 270 )

			if LastAng == nil then LastAng = NewAng end

			local color = ThisSegment:GetActualTrackColor()
			//Draw the first segment
			if i==1 then
				local FirstLeft = controller:GetPos() + ang:Right() * -RailOffset
				local FirstRight = controller:GetPos() + ang:Right() * RailOffset
				local CenterBeam = controller:GetPos() +  ang:Up() * -Offset 

				if controller:GetLooped() then
					FirstLeft = controller.CatmullRom.PointsList[2] + ang:Right() * -RailOffset
					FirstRight = controller.CatmullRom.PointsList[2] + ang:Right() * RailOffset
					CenterBeam = controller.CatmullRom.PointsList[2] + ang:Up() * -Offset
				end

				self.Cylinder:AddBeam(CenterBeam, LastAng, controller.CatmullRom.Spline[i] + ang:Up() * -Offset, NewAng, Radius, color )

				self.Cylinder:AddBeam( FirstLeft, LastAng, posL, NewAng, 4, color)
				self.Cylinder:AddBeam( FirstRight, LastAng, posR, NewAng, 4, color  )
			end

			//vec:ANgle()
			self.Cylinder:AddBeam(controller.CatmullRom.Spline[i] + (ang:Up() * -Offset), LastAng, controller.CatmullRom.Spline[i+1] + (ang2:Up() * -Offset), NewAng, Radius, color)

			//Side rails
			self.Cylinder:AddBeam( posL, LastAng, nPosL, NewAng, 4, color )
			self.Cylinder:AddBeam( posR, LastAng, nPosR, NewAng, 4, color)

			if #self.Cylinder.Vertices > self:GetMaxVertices() then// some arbitrary limit to split up the verts into seperate meshes
				self:AddSubmesh( 1, self.Cylinder.Vertices )

				self.Cylinder.Vertices = {}
				self.Cylinder.TriCount = 1
			end
			LastAng = NewAng

			self:CoroutineCheck( controller, 1, nil, i / #controller.CatmullRom.Spline)
		end
	end	

	local verts = self.Cylinder:EndBeam()
	self:AddSubmesh( 1, verts )

	//Stage 2, create the struts in between the coaster rails
	local CurSegment = 2
	local Percent = 0
	local Multiplier = 1
	local StrutVerts = {} //mmm yeah strut those verts

	while CurSegment < #controller.CatmullRom.PointsList - 1 do
		local CurNode = controller.Nodes[CurSegment]
		local NextNode = controller.Nodes[CurSegment + 1]

		local Position = controller.CatmullRom:Point(CurSegment, Percent)

		local ang = controller:AngleAt(CurSegment, Percent)

		//Change the roll depending on the track
		local Roll = (IsValid(CurNode) && IsValid(NextNode)) && -Lerp( Percent, math.NormalizeAngle( CurNode:GetRoll() ), NextNode:GetRoll()) or 0
		
		//Set the roll for the current track peice
		ang.r = Roll
		//ang:RotateAroundAxis( controller:AngleAt(CurSegment, Percent), Roll ) //BAM

		//Now... manage moving throughout the track evenly
		//Each spline has a certain multiplier so the cart travel at a constant speed throughout the track
		Multiplier = controller:GetMultiplier(CurSegment, Percent)

		//Move ourselves forward along the track
		Percent = Percent + ( Multiplier * StrutOffset )

		//Manage moving between nodes
		if Percent > 1 then
			CurSegment = CurSegment + 1
			if CurSegment > #controller.Nodes - 2 then 			
				break
			end	
			Percent = 0
		end
		local verts = CreateStrutsMesh(Position, ang, CurNode:GetActualTrackColor() ) 
		table.Add( StrutVerts, verts ) //Combine the tables into da big table

		-- Split the model into multiple meshes if it gets large
		if #StrutVerts > self:GetMaxVertices() then
			self:AddSubmesh( 2, StrutVerts )
			StrutVerts = {}
		end

		self:CoroutineCheck( controller, 1, nil, CurSegment / (#controller.CatmullRom.PointsList - 1) )
	end

	-- Add any final vertices
	self:AddSubmesh( 2, StrutVerts )

	self:FinalizeTrack( controller )
end

//I can't retrieve the triangles from a compiled model, SO LET'S MAKE OUR OWN
//These are the triangular struts of the metal beam mesh track
function CreateStrutsMesh(pos, ang, TrackColor)
	local width = 5
	local Offset = 15
	local RailOffset = 25

	//Front tri
	local F_Right = pos + ang:Right() * RailOffset
	local F_Bottom = pos + ang:Up() * -Offset
	local F_Left = pos + ang:Right() * -RailOffset

	//Back tri
	local B_Right = F_Right + ( ang:Forward() * width )
	local B_Bottom = F_Bottom + ( ang:Forward() * width )
	local B_Left = F_Left + ( ang:Forward() * width )

	local Vertices = {}

	//Vars to get the proper normal of the left/right bits of the struts
	local angLeft = F_Bottom - F_Left
	angLeft:Normalize()
	local angRight = F_Bottom - F_Right
	angRight:Normalize()

	local NormTop = ang:Up()
	local NormFwd = -ang:Forward()
	local NormBkwd = ang:Forward()
	local NormLeft = angLeft
	local NormRight = angRight

	local colVec = Vector( 0, 0, 0 )

	//And the user selected color too
	local UserColor = Vector( 1, 1, 1 )
	if TrackColor then
		UserColor = Vector( TrackColor.r / 255, TrackColor.g / 255, TrackColor.b / 255 ) 
	end

	//Front triangle
	colVec = render.ComputeLighting(F_Right, NormFwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Right, NormFwd)
	Vertices[1] = {
		pos = F_Right,
		normal = NormFwd,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Bottom, NormFwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Bottom, NormFwd)
	Vertices[2] = {
		pos = F_Bottom,
		normal = NormFwd,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Left, NormFwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Left, NormFwd)
	Vertices[3] = {
		pos = F_Left,
		normal = NormFwd,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	//Back triangle
	colVec = render.ComputeLighting(B_Left, NormBkwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Left, NormBkwd)
	Vertices[4] = {
		pos = B_Left,
		normal = NormBkwd,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Bottom, NormBkwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Bottom, NormBkwd)
	Vertices[5] = {
		pos = B_Bottom,
		normal = NormBkwd,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Right, NormBkwd )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Right, NormBkwd)
	Vertices[6] = {
		pos = B_Right,
		normal = NormBkwd,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	//Top Quad
	colVec = render.ComputeLighting(B_Left, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Left, NormTop)
	Vertices[7] = {
		pos = B_Left,
		normal = NormTop,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Right, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Right, NormTop)
	Vertices[8] = {
		pos = B_Right,
		normal = NormTop,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Right, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Right, NormTop)
	Vertices[9] = {
		pos = F_Right,
		normal = NormTop,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	colVec = render.ComputeLighting(F_Right, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Right, NormTop)
	Vertices[10] = {
		pos = F_Right,
		normal = NormTop,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Left, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Left, NormTop)
	Vertices[11] = {
		pos = F_Left,
		normal = NormTop,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Left, NormTop )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Left, NormTop)
	Vertices[12] = {
		pos = B_Left,
		normal = NormTop,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	//Left Quad
	colVec = render.ComputeLighting(F_Bottom, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Bottom, NormLeft)
	Vertices[13] = {
		pos = F_Bottom,
		normal = NormLeft,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Bottom, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Bottom, NormLeft)
	Vertices[14] = {
		pos = B_Bottom,
		normal = NormLeft,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Left, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Left, NormLeft)
	Vertices[15] = {
		pos = B_Left,
		normal = NormLeft,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	colVec = render.ComputeLighting(B_Left, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Left, NormLeft)
	Vertices[16] = {
		pos = B_Left,
		normal = NormLeft,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Left, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Left, NormLeft)
	Vertices[17] = {
		pos = F_Left,
		normal = NormLeft,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Bottom, NormLeft )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Bottom, NormLeft)
	Vertices[18] = {
		pos = F_Bottom,
		normal = NormLeft,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	//Right Quad
	colVec = render.ComputeLighting(F_Bottom, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Bottom, NormRight)
	Vertices[19] = {
		pos = F_Bottom,
		normal = NormRight,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Right, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Right, NormRight)
	Vertices[20] = {
		pos = F_Right,
		normal = NormRight,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Right, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Right, NormRight)
	Vertices[21] = {
		pos = B_Right,
		normal = NormRight,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}

	colVec = render.ComputeLighting(B_Right, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Right, NormRight)
	Vertices[22] = {
		pos = B_Right,
		normal = NormRight,
		u = 0,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(B_Bottom, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(B_Bottom, NormRight)
	Vertices[23] = {
		pos = B_Bottom,
		normal = NormRight,
		u = 0.5,
		v = 1,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}
	colVec = render.ComputeLighting(F_Bottom, NormRight )
	colVec = colVec + render.GetAmbientLightColor()
	colVec = colVec + render.ComputeDynamicLighting(F_Bottom, NormRight)
	Vertices[24] = {
		pos = F_Bottom,
		normal = NormRight,
		u = 1,
		v = 0,
		color = Color( colVec.x*UserColor.x*255, colVec.y*UserColor.y*255, colVec.z*UserColor.z*255)
	}


	return Vertices
end

/****************************
Draw function. Draw the mesh
****************************/

function TRACK:Draw( meshdata )
	render.SetMaterial(self.Material)

	self:DrawSection( 1, meshdata )
	self:DrawSection( 2, meshdata ) 
end

