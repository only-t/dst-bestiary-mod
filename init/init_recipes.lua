local Ingredient = GLOBAL.Ingredient
local TECH = GLOBAL.TECH
local CRAFTING_FILTERS = GLOBAL.CRAFTING_FILTERS

if GLOBAL.BESTIARY_ITEM_CONFIG then
    AddRecipe2("bestiary", { Ingredient("papyrus", 1), Ingredient("monstermeat", 1) }, TECH.SCIENCE_ONE, { atlas = "images/bestiary.xml", image = "bestiary.tex" }, { "TOOLS" })
    table.remove(CRAFTING_FILTERS.TOOLS.recipes)
    table.insert(CRAFTING_FILTERS.TOOLS.recipes, 15.5, "bestiary")
end