local Widget = require "widgets/widget"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local Text = require "widgets/text"
local UIAnim = require "widgets/uianim"
local TrueScrollList = require "widgets/truescrolllist"
local Grid = require "widgets/grid"
local Spinner = require "widgets/spinner"
local TrueScrollArea = require "widgets/truescrollarea"
local PopupDialogScreen = require "screens/popupdialog"

local TEMPLATES = require "widgets/redux/templates"

local function FindInTable(table, value)
	for i, table_value in ipairs(table) do
		if table_value == value then
			return true
		end
	end

	return false
end

local BestiaryMonstersPage = Class(Widget, function(self, owner)
	Widget._ctor(self, "BestiaryMonstersPage")

	self.parent_screen = owner

	self.all_monsters = {  }
	self.filtered_monsters = {  }
	self.sort = nil
	self.filter = nil

	local discovered_mobs = TheBestiary.discovered_mobs or {  }
	local learned_mobs = TheBestiary.learned_mobs or {  }

	local MonsterInfo = MONSTERDATA_BESTIARY

	for mob_prefab, mob_data in pairs(MonsterInfo) do
		local data = {  }

		if mob_data.forms then
			data = mob_data.forms[1]
			data.forms = mob_data.forms
			data.current_form = 1

			data.scale = mob_data.scale
			data.type = mob_data.type
			data.images = mob_data.images
			data.rotations = mob_data.rotations or data.rotations
		else
			data = mob_data
		end

		if DISCOVERABLE_MOBS_CONFIG then
			if FindInTable(discovered_mobs, data.prefab) then
				data.is_discovered = true
			else
				data.is_discovered = nil
			end

			if FindInTable(learned_mobs, data.prefab) then
				data.is_learned = true
			else
				data.is_learned = nil
			end
		else
			data.is_discovered = true
			data.is_learned = true
		end

		table.insert(self.all_monsters, data)
	end

	self.completion = self:AddChild(self:CreateCompletionStrip()) -- Needs to be above the page to display properly

	if DISCOVERABLE_MOBS_CONFIG and TheNet:GetServerGameMode() ~= "" then -- Add the bestiary clear button only if discovering is enabled and the players not in compendium
		self.dangly = self:AddChild(self:CreateDangly())
	end

	self.page = self:AddChild(Image("images/bestiary_page.xml", "bestiary_page.tex"))
	self.page:SetSize(970, 570)
	self.page:SetPosition(0, 40)

	self.gridroot = self:AddChild(Widget("grid_root"))
    self.gridroot:SetPosition(-120, -40)

    self.monster_grid = self.gridroot:AddChild(self:CreateMonsterGrid())
	self.monster_grid:SetPosition(0, 30)

	local grid_w, grid_h = self.monster_grid:GetScrollRegionSize()
	local grid_boarder = self.gridroot:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line.tex"))
    grid_boarder:SetPosition(0, grid_h/2 + 30)
	grid_boarder:SetScale(1.1, 1)
	grid_boarder = self.gridroot:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line.tex"))
	grid_boarder:SetPosition(0, -grid_h/2 - 2 + 30)
	grid_boarder:SetScale(1.1, -1)

	self.head_root = self:AddChild(self:CreateHeadRoot())
	self.side_root = self:AddChild(self:CreateSideRoot())

	self.details_root = self:AddChild(Widget("details_root"))

	self:ApplyFilters()
	self:_DoFocusHookups()
end)

function BestiaryMonstersPage:CreateMonsterGrid()
	local row_w = 200
    local row_h = 160
	local framescale = 0.60

	local function ScrollWidgetsCtor(context, index)
        local w = Widget("monster-cell-"..index)

		w.cell_root = w:AddChild(ImageButton("images/monstergrid_bg_basic.xml", "monstergrid_bg_basic.tex"))
		w.cell_root:SetNormalScale(framescale, framescale)
		w.cell_root:SetFocusScale(framescale + 0.02, framescale + 0.02)
		w.cell_root.image:SetTint(0.8, 0.8, 0.8, 1)

		w.cell_root.monster = w.cell_root:AddChild(UIAnim())
		w.cell_root.lock = w.cell_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
		w.cell_root.lock:ScaleToSize(45, 50)
		w.cell_root.lock:SetPosition(70, 40)

		w.cell_root.is_new = w.cell_root:AddChild(UIAnim())
		w.cell_root.is_new:SetScale(1.2, 1.2)
		w.cell_root.is_new:SetPosition(70, 40)
		w.cell_root.is_new:GetAnimState():SetBank("cookbook_newrecipe")
		w.cell_root.is_new:GetAnimState():SetBuild("cookbook_newrecipe")
		w.cell_root.is_new:GetAnimState():PlayAnimation("anim", true)
		w.cell_root.is_new:GetAnimState():SetTime(math.random()*w.cell_root.is_new:GetAnimState():GetCurrentAnimationLength())
		w.cell_root.is_new:Hide()

		w.focus_forward = w.cell_root

		w.cell_root.ongainfocusfn = function()
			w.cell_root.monster:GetAnimState():Resume()

			if TheBestiary.new_mobs then
				TheBestiary.new_mobs[w.data.prefab] = nil
				w.cell_root.is_new:Hide()
			end

			self.monster_grid:OnWidgetFocus(w)
		end

		return w
    end

	local function ScrollWidgetSetData(context, widget, data, index)
		widget.data = data

		if data then
			widget.cell_root:Show()
			widget.cell_root.monster:Show()

			if widget.data.is_discovered then
				widget.cell_root.lock:Hide()

				widget.cell_root:SetOnClick(function()
					self.details_root:AddChild(self:PopulateMonsterDetailPanel(widget.data))
					self.details_root:AddChild(self:PopulateMonsterInfoPanel(widget.data))
				end)

				if widget.data.images then
					widget.cell_root:SetTextures(widget.data.images.grid_atlas, widget.data.images.grid_image)
				end

				if TheBestiary:IsNew(widget.data.prefab) then
					widget.cell_root.is_new:Show()
				else
					widget.cell_root.is_new:Hide()
				end

				if widget.cell_root.monster:GetAnimState():GetBuild() ~= data.build then -- Change the whole UIAnim only at the last frame as it needs to replace the old one
					local time = widget.cell_root.monster:GetAnimState():GetCurrentAnimationTime() 	-- Since re-creating the UIAnim resets the animation it makes it look a bit... weird
																									-- We'll get the current animation time (from the last widget)
					widget.cell_root.monster:Kill() -- There is some serious tom foolery going on with the widgets data and it messes up things that it shouldn't even be able to access
					widget.cell_root.monster = widget:AddChild(UIAnim()) -- So we'll just re-create the UIAnim

					widget.cell_root.monster:GetAnimState():SetBank(data.bank)
					widget.cell_root.monster:GetAnimState():SetBuild(data.build)
					widget.cell_root.monster:SetFacing(data.rotations and data.rotations[1] or FACING_NONE)
					widget.cell_root.monster:GetAnimState():PlayAnimation(data.anim_idle, true)
					widget.cell_root.monster:GetAnimState():Pause() -- Pause here to stop at the first frame
					widget.cell_root.monster:GetAnimState():SetTime(time)-- And apply it to the new cell to make the transition smooooth
					widget.cell_root.monster:SetClickable(false)
					widget.cell_root.monster:SetScale(data.scale and data.scale*TUNING.MONSTER_SMALL_SCALING or 1, data.scale and data.scale*TUNING.MONSTER_SMALL_SCALING or 1)
					widget.cell_root.monster:SetPosition(0, -55)

					widget.cell_root.onlosefocusfn = function()
						widget.cell_root.monster:GetAnimState():PlayAnimation(data.anim_idle, true)
						widget.cell_root.monster:GetAnimState():Pause() -- Pause here to stop at the first frame
					end

					if widget.data.form_override_fn then
						widget.data.form_override_fn(widget.cell_root.monster:GetAnimState(), widget.data)
					end

					if data.prefab == "perd" then -- Some very specific cases (like, wth Klei, what's with the hat?)
						widget.cell_root.monster:GetAnimState():Hide("hat")
					elseif data.prefab == "krampus" then
						widget.cell_root.monster:GetAnimState():Hide("ARM")
					elseif data.prefab == "fireflies" then
						widget.cell_root.monster:SetPosition(0, 0)
					elseif data.prefab == "chester" or data.prefab == "hutch" then
						widget.cell_root.monster:SetPosition(0, -35)
					elseif (data.prefab == "tallbird") or (data.prefab == "teenbird") then
						widget.cell_root.monster:GetAnimState():Hide("beakfull")
					elseif data.prefab == "deciduoustree" then
						widget.cell_root.monster:GetAnimState():OverrideSymbol("swap_leaves", "tree_leaf_poison_build", "swap_leaves")
						widget.cell_root.monster:GetAnimState():OverrideSymbol("legs", "tree_leaf_poison_build", "legs")
						widget.cell_root.monster:GetAnimState():OverrideSymbol("legs_mouseover", "tree_leaf_poison_build", "legs_mouseover")
						widget.cell_root.monster:GetAnimState():OverrideSymbol("eye", "tree_leaf_poison_build", "eye")
						widget.cell_root.monster:GetAnimState():OverrideSymbol("mouth", "tree_leaf_poison_build", "mouth")
					elseif data.prefab == "gestalt" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "deer_blue" then
						widget.cell_root.monster:GetAnimState():OverrideSymbol("swap_antler_red", "deer_build", "swap_antler_blue")
					elseif data.prefab == "deer" then
						widget.cell_root.monster:GetAnimState():Hide("swap_antler")
						widget.cell_root.monster:GetAnimState():Hide("CHAIN")
						widget.cell_root.monster:GetAnimState():OverrideSymbol("swap_neck_collar", "deer_build", "swap_neck")
					elseif data.prefab == "cookiecutter" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "stalker_forest" then
						widget.cell_root.monster:GetAnimState():AddOverrideBuild("stalker_forest_build")
					elseif data.prefab == "stalker" then
						widget.cell_root.monster:GetAnimState():AddOverrideBuild("stalker_cave_build")
					elseif data.prefab == "stalker_atrium" then
						widget.cell_root.monster:GetAnimState():AddOverrideBuild("stalker_atrium_build")
					elseif data.prefab == "hermitcrab" then
						widget.cell_root.monster:GetAnimState():Hide("ARM_carry")
					elseif data.prefab == "crabking" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "dustmoth" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "gnarwail" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "wobster_moonglass_land" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "wobster_sheller_land" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "mole" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "pigking" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "stalker_minion1" then
						widget.cell_root.monster:SetPosition(0, -40)
					elseif data.prefab == "rabbit" and data.build ~= "beard_monster" then
						if TheWorld and TheWorld.state.iswinter then
							widget.cell_root.monster:GetAnimState():SetBuild("rabbit_winter_build")
						else
							widget.cell_root.monster:GetAnimState():SetBuild(data.build)
						end
					end
				end
			else
				widget.cell_root:SetOnClick(nil)
				widget.cell_root:SetTextures("images/monstergrid_bg_basic.xml", "monstergrid_bg_basic.tex")

				widget.cell_root.lock:Show()
				widget.cell_root.monster:Hide()
				widget.cell_root.is_new:Hide()
			end

			widget:Enable()
		else
			widget:Disable()
			widget.cell_root:Hide()
			widget.cell_root.monster:Hide()
			widget.cell_root.lock:Hide()
			widget.cell_root.is_new:Hide()
		end
    end

	local grid = TEMPLATES.ScrollingGrid(
		{  },
		{
			context = {  },
			widget_width = row_w,
			widget_height = row_h,
			force_peek = true,
			num_visible_rows = 2,
			num_columns = 3,
			item_ctor_fn = ScrollWidgetsCtor,
			apply_fn = ScrollWidgetSetData,
			scrollbar_offset = 20,
			scrollbar_height_offset = -100
		}
	)

	grid.up_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
	grid.up_button:SetScale(0.7)

	grid.down_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
	grid.down_button:SetScale(-0.7)

	grid.scroll_bar_line:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")
	grid.scroll_bar_line:SetScale(0.7, 0.5)

	grid.position_marker:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
	grid.position_marker.image:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
	grid.position_marker:SetScale(0.8)

	return grid
end

function BestiaryMonstersPage:PopulateMonsterDetailPanel(data)
	self.gridroot:Hide()
	self.head_root:Hide()
	self.side_root:Hide()
	self.details_root:Show()
	
	local details_root = self:AddChild(Widget("details_root"))
	details_root:SetPosition(235, 35)

	local details_decor = details_root:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_block.tex"))
	details_decor:ScaleToSize(400, 530)

	if data.images then
		self.monsterframe = details_root:AddChild(Image(data.images.atlas, data.images.image))
	end

	self.monsterframe:SetPosition(0, 90)
	self.monsterframe:SetScale(0.85, 0.85)

	self.details = details_root:AddChild(Widget("details"))

	if data.forms then
		self.details:SetPosition(0, -40)
	end

	local back = details_root:AddChild(ImageButton("images/button_icons.xml", "submit.tex"))
	back:SetOnClick(function()
		if self.page.texture == "bestiary_page_torn.tex" then
			self.page:SetTexture("images/bestiary_page.xml", "bestiary_page.tex")
			self.page:SetSize(970, 570)
			self.page:SetPosition(0, 40)
		end

		self.gridroot:Show()
		self.head_root:Show()
		self.side_root:Show()
		self.details_root:KillAllChildren()
		data.current_form = 1 -- Reset current form so it doesn't desync when viewing the same mob multiple times
	end)

	back:SetNormalScale(0.3, 0.3)
	back:SetFocusScale(0.33, 0.33)
	back:SetPosition(130, -210)

	self:CreateTheMob(data)
	self:CreateStats(data)

	return details_root
end

function BestiaryMonstersPage:PopulateMonsterInfoPanel(data)
	self.root = self:AddChild(Widget("info_root"))

	self.root:SetPosition(0, 10)

	self:CreateInformation(data)

    return self.root
end

local function CreateFormBullets(data)
	local grid = Grid()

	grid:InitSize(#data.forms, 1, 45, 40)
	grid:UseNaturalLayout()

	for i = 1, #data.forms, 1 do
		local bullet = Image("images/global_redux.xml", "radiobutton_filled_gold_off.tex")
		bullet:ScaleToSize(40, 40)

		grid:AddItem(bullet, i, 1)
	end

	grid:GetItemInSlot(data.current_form, 1):SetTexture("images/global_redux.xml", "radiobutton_filled_gold_on.tex") -- The grid is recreated every time the form is changed so we can just change the texture here

	return grid
end

function BestiaryMonstersPage:CreateTheMob(data)
	self.monsterframe:KillAllChildren() -- Reset monsterframe

	if data.intent == STRINGS.BESTIARY_AGGRESSIVE then
		local intenttext = self.monsterframe:AddChild(Text(HEADERFONT, 28, data.intent, UICOLOURS.RED))

		intenttext:SetPosition(-75, 90)
	elseif data.intent == STRINGS.BESTIARY_PASSIVE then
		local intenttext = self.monsterframe:AddChild(Text(HEADERFONT, 28, data.intent, { 0/255, 128/255, 0/255, 1 })) -- Why is there no UICOLOURS.GREEN, bruh...
	
		intenttext:SetPosition(-75, 90)
	elseif data.intent == STRINGS.BESTIARY_NEUTRAL then
		local intenttext = self.monsterframe:AddChild(Text(HEADERFONT, 28, data.intent, UICOLOURS.WHITE))
	
		intenttext:SetPosition(-75, 90)
	end

	self.monsterframe.light = self.monsterframe:AddChild(UIAnim())
	self.monsterframe.light:GetAnimState():SetBank("monsterdetail_fx")
	self.monsterframe.light:GetAnimState():SetBuild("monsterdetail_fx")
	self.monsterframe.light:GetAnimState():PushAnimation("idle", true)
	self.monsterframe.light:SetClickable(false)
	self.monsterframe.light:SetScale(0.2, 0.1)
	self.monsterframe.light:SetPosition(0, -100)
	self.monsterframe.light:GetAnimState():SetMultColour(1, 1, 1, 0.35)

	self.monsterframe.monster = self.monsterframe:AddChild(UIAnim())
	self.monsterframe.monster:GetAnimState():SetBank(data.bank)
	self.monsterframe.monster:GetAnimState():SetBuild(data.build)
	self.monsterframe.monster:SetFacing(data.rotations and data.rotations[1] or FACING_NONE)
	self.monsterframe.monster:GetAnimState():PushAnimation(data.anim_idle, true)
	self.monsterframe.monster:SetClickable(false)
	self.monsterframe.monster:SetScale(data.scale or 1, data.scale or 1)
	self.monsterframe.monster:SetPosition(0, -100)

	if data.prefab == "perd" then -- Some very specific cases (like wth Klei, what's with the hat?)
		self.monsterframe.monster:GetAnimState():Hide("hat")
	elseif data.prefab == "krampus" then
		self.monsterframe.monster:GetAnimState():Hide("ARM")
	elseif data.prefab == "fireflies" then
		self.monsterframe.monster:SetPosition(0, 0)
	elseif data.prefab == "chester" or data.prefab == "hutch" then
		self.monsterframe.monster:SetPosition(0, -80)
	elseif data.prefab == "tallbird" or data.prefab == "teenbird"then
		self.monsterframe.monster:GetAnimState():Hide("beakfull")
	elseif data.prefab == "deciduoustree" then
		self.monsterframe.monster:GetAnimState():OverrideSymbol("swap_leaves", "tree_leaf_poison_build", "swap_leaves")
		self.monsterframe.monster:GetAnimState():OverrideSymbol("legs", "tree_leaf_poison_build", "legs")
		self.monsterframe.monster:GetAnimState():OverrideSymbol("legs_mouseover", "tree_leaf_poison_build", "legs_mouseover")
		self.monsterframe.monster:GetAnimState():OverrideSymbol("eye", "tree_leaf_poison_build", "eye")
		self.monsterframe.monster:GetAnimState():OverrideSymbol("mouth", "tree_leaf_poison_build", "mouth")
	elseif data.prefab == "gestalt" then
		self.monsterframe.monster:SetPosition(0, -50)
	elseif data.prefab == "deer_blue" then
		self.monsterframe.monster:GetAnimState():OverrideSymbol("swap_antler_red", "deer_build", "swap_antler_blue")
	elseif data.prefab == "deer" then
		self.monsterframe.monster:GetAnimState():Hide("swap_antler")
		self.monsterframe.monster:GetAnimState():Hide("CHAIN")
		self.monsterframe.monster:GetAnimState():OverrideSymbol("swap_neck_collar", "deer_build", "swap_neck")
	elseif data.prefab == "cookiecutter" then
		self.monsterframe.monster:SetPosition(0, -50)
	elseif data.prefab == "stalker_forest" then
		self.monsterframe.monster:GetAnimState():AddOverrideBuild("stalker_forest_build")
	elseif data.prefab == "stalker" then
		self.monsterframe.monster:GetAnimState():AddOverrideBuild("stalker_cave_build")
	elseif data.prefab == "stalker_atrium" then
		self.monsterframe.monster:GetAnimState():AddOverrideBuild("stalker_atrium_build")
	elseif data.prefab == "hermitcrab" then
		self.monsterframe.monster:GetAnimState():Hide("ARM_carry")
	elseif data.prefab == "crabking" then
		self.monsterframe.monster:SetPosition(0, -70)
	elseif data.prefab == "dustmoth" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "pigking" then
		self.monsterframe.monster:SetPosition(0, -75)
	elseif data.prefab == "beefalo" then
		self.monsterframe.monster:GetAnimState():Hide("HEAT")
	elseif data.prefab == "gnarwail" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "wobster_moonglass_land" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "wobster_sheller_land" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "mole" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "stalker_minion1" then
		self.monsterframe.monster:SetPosition(0, -60)
	elseif data.prefab == "rabbit" then
		if TheWorld and TheWorld.state.iswinter then
			self.monsterframe.monster:GetAnimState():SetBuild("rabbit_winter_build")
		else
			self.monsterframe.monster:GetAnimState():SetBuild(data.build)
		end
	end

	if data.anim_action then
		self.monsterframe.clickyclick = self.monsterframe:AddChild(ImageButton("images/monster_bg_basic.xml", "monster_bg_basic.tex"))
		self.monsterframe.clickyclick.image:SetTint(1, 1, 1, 0)

		self.monsterframe.clickyclick:SetOnClick(function()
			self.monsterframe.monster:GetAnimState():PlayAnimation(data.anim_action)
			self.monsterframe.monster:GetAnimState():PushAnimation(data.anim_idle, true)
		end)

		self.monsterframe.clickyclick.scale_on_focus = false
		self.monsterframe.clickyclick.move_on_click = false
		self.monsterframe.clickyclick.image:SetTint(1, 1, 1, 0)
	end

	if data.rotations and type(data.rotations) == "table" then
		self.monsterframe.rot_left = self.monsterframe:AddChild(ImageButton("images/button_icons.xml", "undo.tex"))
		self.monsterframe.rot_left:SetScale(0.25, 0.15)
		self.monsterframe.rot_left:SetPosition(115, -80)
		self.monsterframe.rot_left:SetRotation(40)

		self.monsterframe.rot_right = self.monsterframe:AddChild(ImageButton("images/button_icons.xml", "undo.tex"))
		self.monsterframe.rot_right:SetScale(-0.25, 0.15)
		self.monsterframe.rot_right:SetPosition(-115, -80)
		self.monsterframe.rot_right:SetRotation(40)

		local iteration = 1

		self.monsterframe.rot_left:SetOnClick(function()
			iteration = iteration + 1

			if iteration > #data.rotations then
				iteration = 1
			end

			self.monsterframe.monster:SetFacing(data.rotations[iteration])
		end)

		self.monsterframe.rot_right:SetOnClick(function()
			iteration = iteration - 1

			if iteration < 1 then
				iteration = #data.rotations
			end

			self.monsterframe.monster:SetFacing(data.rotations[iteration])
		end)
	end

	if data.forms then
		local form_left = self.monsterframe:AddChild(ImageButton("images/button_icons.xml", "goto_url.tex"))
		form_left:SetOnClick(function()
			data.current_form = data.current_form - 1

			if data.current_form <= 0 then
				data.current_form = #data.forms
			end

			self:ApplyForm(data, data.current_form)
		end)

		form_left:SetNormalScale(-0.2, 0.15)
		form_left:SetFocusScale(-0.23, 0.18)
		form_left:SetPosition(-130, -150)
		form_left.image:SetTint(0.8, 0.8, 0.8, 1)

		local form_right = self.monsterframe:AddChild(ImageButton("images/button_icons.xml", "goto_url.tex"))
		form_right:SetOnClick(function()
			self.monsterframe.forms:GetItemInSlot(data.current_form, 1):SetTexture("images/global_redux.xml", "radiobutton_filled_gold_off.tex") -- Disable the last bullet

			data.current_form = data.current_form + 1

			if data.current_form > #data.forms then
				data.current_form = 1
			end

			self.monsterframe.forms:GetItemInSlot(data.current_form, 1):SetTexture("images/global_redux.xml", "radiobutton_filled_gold_on.tex") -- Enable the new bullet

			self:ApplyForm(data, data.current_form)
		end)

		form_right:SetNormalScale(0.2, 0.15)
		form_right:SetFocusScale(0.23, 0.18)
		form_right:SetPosition(130, -150)
		form_right.image:SetTint(0.8, 0.8, 0.8, 1)

		if data.form_override_fn then
			data.form_override_fn(self.monsterframe.monster:GetAnimState(), data)
		end

		self.monsterframe.forms = self.monsterframe:AddChild(CreateFormBullets(data))
		self.monsterframe.forms:SetPosition(-(self.monsterframe.forms.cols - 1)*45/2, -150)
	end
end

function BestiaryMonstersPage:CreateStats(data)
	self.details:KillAllChildren() -- Reset details

	self.details.health = self.details:AddChild(Image("images/bestiary_health.xml", "bestiary_health.tex"))
	self.details.damage = self.details:AddChild(Image("images/bestiary_dmg.xml", "bestiary_dmg.tex"))
	self.details.speed = self.details:AddChild(Image("images/bestiary_speed.xml", "bestiary_speed.tex"))

	self.details.health:ScaleToSize(60, 60)
	self.details.damage:ScaleToSize(60, 60)
	self.details.speed:ScaleToSize(60, 60)

	self.details.health:SetPosition(-100, -60)
	self.details.damage:SetPosition(0, -60)
	self.details.speed:SetPosition(100, -60)

	self.details.health_value = self.details:AddChild(Text(HEADERFONT, 32, nil, UICOLOURS.BROWN_DARK))
	self.details.damage_value = self.details:AddChild(Text(HEADERFONT, 32, nil, UICOLOURS.BROWN_DARK))
	self.details.speed_value = self.details:AddChild(Text(HEADERFONT, 32, nil, UICOLOURS.BROWN_DARK))

	self.details.health_value:SetAutoSizingString(data.stats.health, 100)
	self.details.damage_value:SetAutoSizingString(data.stats.damage, 100)
	self.details.speed_value:SetAutoSizingString(data.stats.speed, 100)

	self.details.health_value:SetPosition(-100, -115)
	self.details.damage_value:SetPosition(0, -115)
	self.details.speed_value:SetPosition(100, -115)
end

function BestiaryMonstersPage:CreateInformation(data)
	self.root:KillAllChildren()

	local sub_root = self.root:AddChild(Widget("text_root"))

	local width = 420
	local height = 0
	local title_space = 5
	local section_space = 32
	local font = 38

	if data.stats.diet and (type(data.stats.diet) == "table" and not data.stats.diet[1] ~= "none") then
		local diet = sub_root:AddChild(Text(HEADERFONT, font, "Diet", UICOLOURS.BROWN_DARK))
		local x, y = diet:GetRegionSize()
		diet:SetPosition(width/2, height - 0.5*y)
		height = height - y - section_space

		if data.is_learned then
			local diet_value = sub_root:AddChild(Grid())
			self:FillDietGrid(diet_value, data.stats.diet)
			y = diet_value.rows*70
			diet_value:SetPosition(width/2 - (diet_value.cols - 1)*70/2, height - 35) -- Note to self: cols are the vertical ones, idiot
			height = height - y - section_space
		else
			local locked_bg = sub_root:AddChild(Image("images/frontend.xml", "nav_bg_short.tex"))
			locked_bg:ScaleToSize(width - 80, 120*2)
			local x, y = locked_bg:GetSize()
			locked_bg:SetPosition(width/2, height - 0.5*y - 30)

			local lock = sub_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
			lock:ScaleToSize(110, 120)
			x, y = lock:GetSize()
			lock:SetPosition(width/2, height - 0.5*y)
			height = height - y - section_space
		end
	end

	if data.stats.drops and data.stats.drops ~= "none" then
		local drops = sub_root:AddChild(Text(HEADERFONT, font, "Drops", UICOLOURS.BROWN_DARK))
		local x, y = drops:GetRegionSize()
		drops:SetPosition(width/2, height - 0.5*y)
		height = height - y - section_space

		if data.is_learned then
			local drops_value = sub_root:AddChild(Grid())
			self:FillDropsGrid(drops_value, data.stats.drops)
			y = drops_value.rows*56
			drops_value:SetPosition(width/2 - (drops_value.cols - 1)*104/2, height - 28)
			height = height - y - section_space
		else
			local locked_bg = sub_root:AddChild(Image("images/frontend.xml", "nav_bg_short.tex"))
			locked_bg:ScaleToSize(width - 80, 120*2)
			local x, y = locked_bg:GetSize()
			locked_bg:SetPosition(width/2, height - 0.5*y - 30)

			local lock = sub_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
			lock:ScaleToSize(110, 120)
			x, y = lock:GetSize()
			lock:SetPosition(width/2, height - 0.5*y)
			height = height - y - section_space
		end
	end

	if data.stats.limited_drops then
		local limited_drops = sub_root:AddChild(Text(HEADERFONT, font, data.stats.limited_drops.amount..(data.stats.limited_drops.amount == 1 and " Drop Of" or " Drops Of"), UICOLOURS.BROWN_DARK))
		local x, y = limited_drops:GetRegionSize()
		limited_drops:SetPosition(width/2, height - 0.5*y)
		height = height - y - section_space

		if data.is_learned then
			local limited_drops_value = sub_root:AddChild(Grid())
			self:FillDropsGrid(limited_drops_value, data.stats.limited_drops.loot)
			y = limited_drops_value.rows*56
			limited_drops_value:SetPosition(width/2 - (limited_drops_value.cols - 1)*104/2, height - 28)
			height = height - y - section_space
		else
			local locked_bg = sub_root:AddChild(Image("images/frontend.xml", "nav_bg_short.tex"))
			locked_bg:ScaleToSize(width - 80, 120*2)
			local x, y = locked_bg:GetSize()
			locked_bg:SetPosition(width/2, height - 0.5*y - 30)

			local lock = sub_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
			lock:ScaleToSize(110, 120)
			x, y = lock:GetSize()
			lock:SetPosition(width/2, height - 0.5*y)
			height = height - y - section_space
		end
	end

	local desc = sub_root:AddChild(Text(CHATFONT, font, "Information", UICOLOURS.BROWN_DARK))
	local x, y = desc:GetRegionSize()
	desc:SetPosition(width/2, height - 0.5*y)
	height = height - y - section_space

	if data.name == "Moosegoose" then -- Setting the appropriate names for the title and info
		local name = math.random(1, 2) == 1 and "Moose" or "Goose"
		local info = subfmt(data.stats.info, { name = name })

		local title = self.root:AddChild(Text(HEADERFONT, 48, nil, UICOLOURS.BROWN_DARK))
		title:SetPosition(235, 255)
		title:SetAutoSizingString(name or "Unknown", 320)

		if data.is_learned then
			local desc_value = sub_root:AddChild(Text(CHATFONT, 20, nil, UICOLOURS.BROWN_DARK))
			desc_value:SetHAlign(ANCHOR_LEFT)
			desc_value:SetVAlign(ANCHOR_TOP)
			desc_value:SetMultilineTruncatedString(info, 60, width) -- 60 should be enough
	
			x, y = desc_value:GetRegionSize()
			desc_value:SetPosition(0.5*x, height - 0.5*y)
			height = height - y - section_space
		else
			local locked_bg = sub_root:AddChild(Image("images/frontend.xml", "nav_bg_short.tex"))
			locked_bg:ScaleToSize(width - 80, 120*2)
			x, y = locked_bg:GetSize()
			locked_bg:SetPosition(width/2, height - 0.5*y - 30)
	
			local lock = sub_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
			lock:ScaleToSize(110, 120)
			x, y = lock:GetSize()
			lock:SetPosition(width/2, height - 0.5*y)
			height = height - y - section_space
		end
	else
		local title = self.root:AddChild(Text(HEADERFONT, 48, nil, UICOLOURS.BROWN_DARK))
		title:SetPosition(235, 255)
		title:SetAutoSizingString(data.name or "Unknown", 320)

		if data.is_learned then
			local desc_value = sub_root:AddChild(Text(CHATFONT, 20, nil, UICOLOURS.BROWN_DARK))
			desc_value:SetHAlign(ANCHOR_LEFT)
			desc_value:SetVAlign(ANCHOR_TOP)
			desc_value:SetMultilineTruncatedString(data.stats.info, 60, width) -- 60 should be enough
	
			x, y = desc_value:GetRegionSize()
			desc_value:SetPosition(0.5*x, height - 0.5*y)
			height = height - y - section_space
		else
			local locked_bg = sub_root:AddChild(Image("images/frontend.xml", "nav_bg_short.tex"))
			locked_bg:ScaleToSize(width - 80, 120*2)
			x, y = locked_bg:GetSize()
			locked_bg:SetPosition(width/2, height - 0.5*y - 30)
	
			local lock = sub_root:AddChild(Image("images/bestiary_lock.xml", "bestiary_lock.tex"))
			lock:ScaleToSize(110, 120)
			x, y = lock:GetSize()
			lock:SetPosition(width/2, height - 0.5*y)
			height = height - y - section_space
		end
	end

	height = math.abs(height)

	local max_visible_height = 500
	local padding = 5

	local top = math.min(height, max_visible_height)/2 - padding

	local scissor_data = { x = 0, y = -max_visible_height/2, width = width, height = max_visible_height }
	local context = { widget = sub_root, offset = { x = 0, y = top }, size = { w = width, height = height + padding } }
	local scrollbar = { scroll_per_click = 10*3 }

	local scroll_area = self.root:AddChild(TrueScrollArea(context, scissor_data, scrollbar))
	scroll_area:SetPosition(-width, 20)

	scroll_area.up_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
	scroll_area.up_button:SetScale(0.75)

	scroll_area.down_button:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_arrow_hover.tex")
	scroll_area.down_button:SetScale(-0.75)

	scroll_area.scroll_bar_line:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_bar.tex")
	scroll_area.scroll_bar_line:SetScale(0.85, 1)

	scroll_area.position_marker:SetTextures("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
	scroll_area.position_marker.image:SetTexture("images/quagmire_recipebook.xml", "quagmire_recipe_scroll_handle.tex")
	scroll_area.position_marker:SetScale(0.75)
end

function BestiaryMonstersPage:ApplyForm(data, current_form)
	local forms = data.forms
	local scale = data.scale
	local type = data.type
	local rotations = data.rotations
	local is_learned = data.is_learned
	local images = data.images

	data = data.forms[data.current_form]
	data.forms = forms
	data.current_form = current_form
	data.scale = scale
	data.type = type
	data.is_learned = is_learned
	data.images = images

	if data.rotations == nil then
		data.rotations = rotations
	end

	self:CreateTheMob(data) -- Regenerate mob UIAnim
	self:CreateStats(data) -- Regenerate mobs stats
	self:CreateInformation(data) -- Regenerate mobs information

	if data.form_override_fn then
		data.form_override_fn(self.monsterframe.monster:GetAnimState(), data)
	end
end

function BestiaryMonstersPage:FillDropsGrid(grid, drops)
	if drops and grid then
		if type(drops) ~= "table" then
			print("The drops variable for the grid needs to be a table! Skipping filling the grid...")

			return
		end

		grid:InitSize(#drops <= 2 and #drops or 3, math.ceil(#drops/3), 104, 56) -- 96, 48
		grid:UseNaturalLayout()

		for i, drop in ipairs(drops) do
			local item = Widget("drop")

			local item_image_bg = item:AddChild(Image("images/quagmire_recipebook.xml", "ingredient_slot.tex"))
			item_image_bg:ScaleToSize(48, 48)
			item_image_bg:SetPosition(-28, 0)

			local chance = item:AddChild(Image("images/button_icons.xml", "diceroll.tex")) -- Might change the "chance" display in the future. TBA
			chance:SetScale(0.8, 0.8)
			chance:SetPosition(-36 + 28, 24)
			chance:SetHoverText((drop.chance*100).."%")

			local item_drop_name = (drop.name_override or drop.prefab)..".tex"
			local item_drop_atlas = GetInventoryItemAtlas(item_drop_name, true)
			local item_image = item:AddChild(Image(item_drop_atlas or "images/quagmire_recipebook.xml", item_drop_atlas ~= nil and item_drop_name or "cookbook_missing.tex"))
			item_image:SetPosition(item_image_bg:GetPosition())
			item_image:ScaleToSize(40, 40)

			if drop.name_override then
				if drop.name_override == "blueprint_rare" then
					item_image:SetHoverText(subfmt(STRINGS.NAMES.BLUEPRINT_RARE, { item = STRINGS.NAMES[string.upper(drop.prefab:gsub("%_blueprint", ""))] or STRINGS.NAMES.UNKNOWN }))
				elseif drop.name_override == "sketch" then
					item_image:SetHoverText(subfmt(STRINGS.NAMES.SKETCH, { item = STRINGS.NAMES[string.upper(drop.prefab:gsub("%_sketch", ""))] }))
				elseif  drop.name_override == "tacklesketch" then
					item_image:SetHoverText(subfmt(STRINGS.NAMES.TACKLESKETCH, { item = STRINGS.NAMES[string.upper(drop.prefab:gsub("%_tacklesketch", ""))] or STRINGS.NAMES.UNKNOWN }))
				else
					item_image:SetHoverText(STRINGS.NAMES[string.upper(drop.prefab)])
				end
			else
				item_image:SetHoverText(STRINGS.NAMES[string.upper(drop.prefab)])
			end

			local item_amount = item:AddChild(Text(CHATFONT, 48, nil, UICOLOURS.BROWN_DARK))
			item_amount:SetAutoSizingString("x"..(drop.amount or "1"), 48)
			item_amount:SetPosition(28, 0)

			grid:AddItem(item, i - 3*(math.ceil(i/3) - 1), math.ceil(i/3))
		end
	else
		print("The grid or the drops are empty! Skipping filling the grid...")
	end
end

function BestiaryMonstersPage:FillDietGrid(grid, diet)
	if diet and grid then
		if type(diet) == "table" then
			grid:InitSize(#diet <= 4 and #diet or 4, math.ceil(#diet/4), 70, 70)
			grid:UseNaturalLayout()

			for i, type in ipairs(diet) do
				local item = Image("images/diet_"..type..".xml", "diet_"..type..".tex")
				item:ScaleToSize(70, 70)
				item:SetHoverText(type:gsub("%l", string.upper, 1), nil)

				grid:AddItem(item, i - 4*(math.ceil(i/4) - 1), math.ceil(i/4))
			end
		else
			grid:InitSize(1, 1, 0, 0)

			local item = Image("images/diet_"..diet..".xml", "diet_"..diet..".tex")
			item:ScaleToSize(70, 70)
			item:SetHoverText(diet:gsub("%l", string.upper, 1), nil)

			grid:AddItem(item, 1, 1)
		end
	else
		print("The grid or the diet are empty! Skipping filling the grid...")
	end
end

function BestiaryMonstersPage:ApplySort(selected)
	local sortby = selected

	local function alphabetical(a, b)
		if type(a.name) == "function" then
			if type(b.name) == "function" then
				return ((a.name() < b.name()) and not (a.name() > b.name()))
			else
				return ((a.name() < b.name) and not (a.name() > b.name))
			end
		else
			if type(b.name) == "function" then
				return ((a.name < b.name()) and not (a.name > b.name()))
			else
				return ((a.name < b.name) and not (a.name > b.name))
			end
		end
	end

	local function alphabetical_rev(a, b)
		if type(a.name) == "function" then
			if type(b.name) == "function" then
				return ((a.name() > b.name()) and not (a.name() < b.name()))
			else
				return ((a.name() > b.name) and not (a.name() < b.name))
			end
		else
			if type(b.name) == "function" then
				return ((a.name > b.name()) and not (a.name < b.name()))
			else
				return ((a.name > b.name) and not (a.name < b.name))
			end
		end
	end

	local function checkType(string)
		if type(string) == "number" then
			return string
		end

		local start, finish = string.match(string, "(.*)%-(.*)")

		if finish then
			return tonumber(finish)
		elseif start then
			return tonumber(start)
		end
	end

	table.sort(self.filtered_monsters,
		(sortby == "alphabetical" or sortby == nil) and function(a, b) return a.is_discovered and not b.is_discovered or (a.is_discovered and b.is_discovered and alphabetical(a, b)) end
		or	sortby == "alphabetical_rev"	and function(a, b) return a.is_discovered and not b.is_discovered or (a.is_discovered and b.is_discovered and alphabetical_rev(a, b)) end
		or	sortby == "health"				and function(a, b) return a.is_discovered and not b.is_discovered or (a.is_discovered and b.is_discovered and ((checkType(a.stats.health) > checkType(b.stats.health)) or (checkType(a.stats.health) == checkType(b.stats.health) and alphabetical(a, b)))) end
		or	sortby == "damage"				and function(a, b) return a.is_discovered and not b.is_discovered or (a.is_discovered and b.is_discovered and ((checkType(a.stats.damage) > checkType(b.stats.damage)) or (checkType(a.stats.damage) == checkType(b.stats.damage) and alphabetical(a, b)))) end
		or	sortby == "speed"				and function(a, b) return a.is_discovered and not b.is_discovered or (a.is_discovered and b.is_discovered and ((checkType(a.stats.speed) > checkType(b.stats.speed)) or (checkType(a.stats.speed) == checkType(b.stats.speed) and alphabetical(a, b)))) end
	)

    self.monster_grid:SetItemsData(self.filtered_monsters)
	self:_DoFocusHookups()
end

function BestiaryMonstersPage:ApplyFilters(selected, text)
	local filterby = selected or "all"

	self.filtered_monsters = {  }

	for i, data in ipairs(self.all_monsters) do
		if (filterby == "all")
		or (filterby == "aggressive"	and data.intent == STRINGS.BESTIARY_AGGRESSIVE)
		or (filterby == "neutral"		and data.intent == STRINGS.BESTIARY_NEUTRAL)
		or (filterby == "passive"		and data.intent == STRINGS.BESTIARY_PASSIVE)
		or (filterby == "animal"		and data.type == STRINGS.BESTIARY_ANIMAL)
		or (filterby == "monster"		and data.type == STRINGS.BESTIARY_MONSTER)
		or (filterby == "boss"			and data.type == STRINGS.BESTIARY_BOSS)
		or (filterby == "raid"			and data.type == STRINGS.BESTIARY_RAIDBOSS)
		then
			if text then
				if string.find(string.lower(data.name), string.lower(text)) then
					table.insert(self.filtered_monsters, data)
				end
			else
				table.insert(self.filtered_monsters, data)
			end
		end
	end

	self:ApplySort(self.sort)
end

function BestiaryMonstersPage:CreateCompletionStrip()
	local strip = Image("images/bestiary_completion_strip.xml", "bestiary_completion_strip.tex")
	strip:SetPosition(350, -260)
	strip:SetScale(-0.8, 0.8)

	strip:SetTint(1, 1 - (self:GetCompletionPercent()/100), 1 - (self:GetCompletionPercent()/100), 1)

	return strip
end

function BestiaryMonstersPage:CreateDangly()
	local dangly = Image("images/bestiary_dangling_bit.xml", "bestiary_dangling_bit.tex")
	dangly:SetPosition(-350, -280)
	dangly:SetScale(0.8, 0.8)
	dangly:SetRotation(30)

	local reset_btn = dangly:AddChild(ImageButton("images/button_icons.xml", "delete.tex"))
	reset_btn:SetScale(0.25, 0.25)
	reset_btn:SetPosition(-5, -10)

	reset_btn:SetOnClick(function()
		local confirm = PopupDialogScreen(
			"Are you sure?", "You will lose all progress in your bestiary.",
			{
				{
					text = "Confirm", cb = function()
						TheBestiary:Forgor() -- Client sided
						SendModRPCToServer(GetModRPC("bestiarymod", "ForgetBestiary"), ThePlayer) -- Sent from client to server
						TheFrontEnd:PopScreen()
						TheFrontEnd:PopScreen() -- Pop twice, once for the notice, once for the bestiary
					end	
				},
				{
					text = "Cancel", cb = function()
						TheFrontEnd:PopScreen()
					end
				}
			}
		)

		TheFrontEnd:PushScreen(confirm)
	end)

	return dangly
end

function BestiaryMonstersPage:AddSearch()
    local searchbox = Widget("search")
    searchbox.textbox_root = searchbox:AddChild(TEMPLATES.StandardSingleLineTextEntry(nil, 500, 60, nil, 40))
    searchbox.textbox = searchbox.textbox_root.textbox
    searchbox.textbox:SetTextLengthLimit(50)
    searchbox.textbox:SetForceEdit(true)
    searchbox.textbox:EnableWordWrap(false)
    searchbox.textbox:EnableScrollEditWindow(true)
    searchbox.textbox:SetHelpTextEdit("")
    searchbox.textbox:SetHelpTextApply("Search")
    searchbox.textbox:SetTextPrompt("Search", UICOLOURS.GREY)
    searchbox.textbox.prompt:SetHAlign(ANCHOR_MIDDLE)
    searchbox.textbox.OnTextInputted = function()
		self.search_text = searchbox.textbox:GetLineEditString()
		self:ApplyFilters(self.filter, self.search_text)
    end

    searchbox:SetOnGainFocus(function() searchbox.textbox:OnGainFocus() end)
    searchbox:SetOnLoseFocus(function() searchbox.textbox:OnLoseFocus() end)

    searchbox.focus_forward = searchbox.textbox

    return searchbox
end

local filters = {
	{ text = "Everything", data = "all", atlas = CRAFTING_ICONS_ATLAS, image = "filter_none.tex" },
	{ text = "Intent: Neutral", data = "neutral", atlas = "images/intent_neutral.xml", image = "intent_neutral.tex" },
	{ text = "Intent: Passive", data = "passive", atlas = "images/intent_passive.xml", image = "intent_passive.tex" },
	{ text = "Intent: Aggressive", data = "aggressive", atlas = "images/intent_aggressive.xml", image = "intent_aggressive.tex" },
	{ text = "Type: Animal", data = "animal", atlas = "images/type_animal.xml", image = "type_animal.tex" },
	{ text = "Type: Monster", data = "monster", atlas = "minimap/minimap_data.xml", image = "spiderden.png" },
	{ text = "Type: Boss", data = "boss", atlas = "images/type_boss.xml", image = "type_boss.tex" },
	{ text = "Type: Raid Boss", data = "raid", atlas = "minimap/minimap_data.xml", image = "crabking.png" },
}

local filter_buttons = {  }

function BestiaryMonstersPage:CreateFilterButtons()
	local root = Widget("filter_buttons_root")
	root.grid = root:AddChild(Grid())

	local size = 28

	root.grid:InitSize(8, 1, size*1.2, size*1.2)
	root.grid:UseNaturalLayout()

	for i, filter in ipairs(filters) do
		local btn = ImageButton(CRAFTING_ATLAS, "filterslot_frame.tex", "filterslot_frame_highlight.tex", nil, nil, "filterslot_frame_select.tex")
		btn.image:ScaleToSize(size, size)
		btn:SetHoverText(filter.text, { offset_y = 30 })

		btn.filter_bg = btn:AddChild(Image(CRAFTING_ATLAS, i == 1 and "filterslot_bg_highlight.tex" or "filterslot_bg.tex"))
		btn.filter_bg:ScaleToSize(size + 6, size + 6)
		btn.filter_bg:MoveToBack()

		btn.filter_img = btn:AddChild(Image(filter.atlas, filter.image))
		btn.filter_img:ScaleToSize(size - size/10, size - size/10)

		btn:SetOnClick(function()
			self:ApplyFilters(filter.data, self.search_text)

			for i, filter_btn in ipairs(filter_buttons) do
				filter_btn.filter_bg:SetTexture(CRAFTING_ATLAS, "filterslot_bg.tex")
			end

			btn.filter_bg:SetTexture(CRAFTING_ATLAS, "filterslot_bg_highlight.tex")
		end)

		btn = root.grid:AddItem(btn, i, 1)
		local pos = btn:GetPosition()

		if i < 2 then
			btn:SetPosition(pos.x - 15, 0)
		elseif i < 5 then
			btn:SetPosition(pos.x - 5, 0)
		else
			btn:SetPosition(pos.x + 5, 0)
		end

		table.insert(filter_buttons, btn)
	end

	return root
end

local sorts = {
	{ text = "Sort: Alphabetically", data = "alphabetical", atlas = "images/button_icons.xml", image = "sort_name.tex" },
	{ text = "Sort: Reversed Alphabetically", data = "alphabetical_rev", atlas = "images/sort_rev_name.xml", image = "sort_rev_name.tex"  },
	{ text = "Sort: By Health", data = "health", atlas = "images/sort_health.xml", image = "sort_health.tex" },
	{ text = "Sort: By Damage", data = "damage", atlas = "images/sort_dmg.xml", image = "sort_dmg.tex" },
	{ text = "Sort: By Speed", data = "speed", atlas = "images/sort_speed.xml", image = "sort_speed.tex" },
}

function BestiaryMonstersPage:CreateHeadRoot()
	local head_root = Widget("head_root")
	head_root:SetPosition(0, 200)

	local mob_search = head_root:AddChild(self:AddSearch())
	mob_search:SetPosition(-120, 65)

	local decor_line = head_root:AddChild(Image("images/ui.xml", "line_horizontal_white.tex"))
    decor_line:SetTint(unpack(BROWN))
	decor_line:SetPosition(-120, 25)
	decor_line:ScaleToSize(600, 4)

	local filter_buttons = head_root:AddChild(self:CreateFilterButtons())
	filter_buttons:SetPosition(-120 - (28*1.2*8)/2 + 14*1.2, -5) -- Some serious math going on here

	local sort_index = 1
	local sort_button = head_root:AddChild(TEMPLATES.IconButton(sorts[1].atlas, sorts[1].image))
	sort_button:SetHoverText(sorts[1].text)
	sort_button:SetPosition(64, -5)
	sort_button:ForceImageSize(50, 50)
	sort_button:SetTextSize(math.ceil(50*0.45))
	sort_button:SetOnClick(function()
		sort_index = sort_index + 1

		if sort_index > #sorts then
			sort_index = 1
		end

		self.sort = sorts[sort_index].data
		self:ApplySort(self.sort)
		sort_button:SetHoverText(sorts[sort_index].text)

		sort_button.icon:SetTexture(sorts[sort_index].atlas, sorts[sort_index].image)
	end)
	
	return head_root
end

function BestiaryMonstersPage:GetCompletionPercent()
	local every = 0
	local discovered = 0
	
	for i, mob in ipairs(self.all_monsters) do
		if mob.is_discovered then
			discovered = discovered + 1
			every = every + 1
		else
			every = every + 1
		end
	end

	return math.ceil((discovered/every)*100)
end

function BestiaryMonstersPage:CreateSideRoot()
	local function GetMaxMobAmount(type)
		local amount = 0
		
		for i, mob in ipairs(self.all_monsters) do
			if mob.type == type then
				amount = amount + 1
			end
		end

		return amount
	end

	local function GetCurrentMobAmount(type)
		local amount = 0
		
		for i, mob in ipairs(self.all_monsters) do
			if mob.type == type and mob.is_discovered then
				amount = amount + 1
			end
		end

		return amount
	end

	local side_root = Widget("side_root")
	side_root.panel_width = 250
	side_root.panel_height = 500
	side_root:SetPosition(320, -20)

	local decor_area = side_root:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_menu_block.tex"))
	local grid_w, grid_h = self.monster_grid:GetScrollRegionSize()
	decor_area:ScaleToSize(210, 510)
	decor_area:SetPosition(0, 65)

	local height = 280

	local discovered = side_root:AddChild(Text(HEADERFONT, 40, "Discovered", UICOLOURS.BROWN_DARK))
	discovered:SetPosition(0, height)
	height = height - 40

	local decor_line = side_root:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line_break.tex"))
	decor_line:SetPosition(0, height)
	height = height - 40
	decor_line:SetScale(0.55, 0.55)

	local animals = side_root:AddChild(Text(HEADERFONT, 26, "Animals", UICOLOURS.BROWN_DARK))
	animals:SetPosition(0, height)
	height = height - 30
	local animals_amount = side_root:AddChild(Text(HEADERFONT, 26, nil, UICOLOURS.BROWN_DARK))
	animals_amount:SetPosition(0, height)
	height = height - 35
	animals_amount:SetString(GetCurrentMobAmount(STRINGS.BESTIARY_ANIMAL).."/"..GetMaxMobAmount(STRINGS.BESTIARY_ANIMAL))

	local monsters = side_root:AddChild(Text(HEADERFONT, 26, "Monsters", UICOLOURS.BROWN_DARK))
	monsters:SetPosition(0, height)
	height = height - 30
	local monsters_amount = side_root:AddChild(Text(HEADERFONT, 26, nil, UICOLOURS.BROWN_DARK))
	monsters_amount:SetPosition(0, height)
	height = height - 35
	monsters_amount:SetString(GetCurrentMobAmount(STRINGS.BESTIARY_MONSTER).."/"..GetMaxMobAmount(STRINGS.BESTIARY_MONSTER))

	local bosses = side_root:AddChild(Text(HEADERFONT, 26, "Bosses", UICOLOURS.BROWN_DARK))
	bosses:SetPosition(0, height)
	height = height - 30
	local bosses_amount = side_root:AddChild(Text(HEADERFONT, 26, nil, UICOLOURS.BROWN_DARK))
	bosses_amount:SetPosition(0, height)
	height = height - 35
	bosses_amount:SetString(GetCurrentMobAmount(STRINGS.BESTIARY_BOSS).."/"..GetMaxMobAmount(STRINGS.BESTIARY_BOSS))

	local raids = side_root:AddChild(Text(HEADERFONT, 26, "Raid Bosses", UICOLOURS.BROWN_DARK))
	raids:SetPosition(0, height)
	height = height - 30
	local raids_amount = side_root:AddChild(Text(HEADERFONT, 26, nil, UICOLOURS.BROWN_DARK))
	raids_amount:SetPosition(0, height)
	height = height - 35
	raids_amount:SetString(GetCurrentMobAmount(STRINGS.BESTIARY_RAIDBOSS).."/"..GetMaxMobAmount(STRINGS.BESTIARY_RAIDBOSS))

	decor_line = side_root:AddChild(Image("images/quagmire_recipebook.xml", "quagmire_recipe_line_break.tex"))
	decor_line:SetPosition(0, height)
	height = height - 50
	decor_line:SetScale(0.55, -0.55)

	local collection = side_root:AddChild(Text(HEADERFONT, 40, "Collection", UICOLOURS.BROWN_DARK))
	collection:SetPosition(0, height)
	height = height - 50

	local collection_percent = side_root:AddChild(Text(HEADERFONT, 44, self:GetCompletionPercent().."%", UICOLOURS.BROWN_DARK))
	collection_percent:SetPosition(0, height)

	return side_root
end

function BestiaryMonstersPage:_DoFocusHookups()
	if self.spinners then
		for i, v in ipairs(self.spinners) do
			v:ClearFocusDirs()

			if i > 1 then
				v:SetFocusChangeDir(MOVE_UP, self.spinners[i-1])
			end

			if i < #self.spinners then
				v:SetFocusChangeDir(MOVE_DOWN, self.spinners[i+1])
			end
		end

		if self.monster_grid.items and #self.monster_grid.items > 0 then
			self.spinners[#self.spinners]:SetFocusChangeDir(MOVE_DOWN, self.monster_grid)
			self.monster_grid:SetFocusChangeDir(MOVE_UP, self.spinners[#self.spinners])

			self.parent_default_focus = self.monster_grid
			self.focus_forward = self.monster_grid
		else
			self.parent_default_focus = self.spinners[1]
			self.focus_forward = self.spinners[1]
		end
	end
end

return BestiaryMonstersPage