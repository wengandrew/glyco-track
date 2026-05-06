#!/usr/bin/env python3
"""
Add carbs_per_100g values to gi_database.json entries that lack USDA matches.

Values sourced from USDA FoodData Central (public domain).
Run: python3 scripts/add_carbs_to_gi_db.py
"""

import json
import sys
from pathlib import Path

# Carbs per 100g for foods missing USDA data.
# Sources: USDA FoodData Central, nutrition databases.
# Zero-carb entries (meats, oils, teas) intentionally included to document
# that they were researched, not overlooked.
CARBS_LOOKUP = {
    # Meats / seafood / eggs (near-zero carbs)
    "abalone": 6.0,
    "beef liver": 3.9,
    "corned beef": 0.0,
    "duck confit": 0.0,
    "elk": 0.0,
    "fish roe": 2.0,
    "goat meat": 0.0,
    "ostrich": 0.0,
    "quail": 0.0,
    "rabbit": 0.0,
    "souvlaki": 2.0,
    "omelette": 1.6,
    "eggs benedict": 18.0,
    "frittata": 4.0,

    # Oils / fats (zero carbs)
    "avocado oil": 0.0,
    "flaxseed oil": 0.0,
    "pumpkin seed oil": 0.0,
    "sesame oil": 0.0,
    "walnut oil": 0.0,

    # Beverages (low/zero carbs)
    "black tea": 0.3,
    "green tea": 0.0,
    "herbal tea": 0.0,
    "matcha": 0.6,
    "sparkling water": 0.0,
    "lemon water": 0.5,
    "diet soda": 0.0,
    "aloe vera juice": 5.0,

    # Juices (moderate-high carbs)
    "apricot juice": 12.0,
    "beet juice": 10.0,
    "carrot juice": 9.3,
    "cranberry juice": 12.0,
    "grape juice": 15.3,
    "grapefruit juice": 9.2,
    "mango juice": 14.0,
    "peach juice": 11.0,
    "pineapple juice": 12.4,
    "pomegranate juice": 13.1,
    "prune juice": 17.5,
    "tomato juice": 3.9,
    "vegetable juice": 4.0,
    "watermelon juice": 7.6,
    "hot chocolate": 20.0,
    "milk tea": 8.5,

    # Dairy / dairy alternatives
    "crème fraîche": 3.0,
    "double cream": 2.8,
    "fromage blanc": 4.5,
    "goat milk": 4.5,
    "lactose free milk": 5.0,
    "labneh": 4.0,
    "coconut yogurt": 7.0,
    "soy yogurt": 6.0,
    "whey protein": 4.0,
    "soy protein isolate": 0.0,

    # Grains / cereals
    "amaranth": 65.3,
    "glutinous rice": 81.0,
    "puffed rice": 87.0,
    "puffed wheat": 80.0,
    "sorghum grain": 72.0,
    "spelt grain": 71.0,
    "teff": 73.0,
    "triticale": 72.0,
    "wheat berries": 72.0,
    "wheat bran": 64.5,
    "black rice": 76.0,
    "red rice": 76.0,
    "brown rice flour": 76.5,

    # Breakfast cereals
    "all bran": 46.0,
    "cinnamon toast crunch": 80.0,
    "cocoa puffs": 83.3,
    "cocoa krispies": 85.0,
    "captain crunch": 79.0,
    "cream of wheat": 73.3,
    "fiber one": 57.0,
    "froot loops": 83.0,
    "frosted flakes": 87.0,
    "frosted mini wheats": 80.0,
    "grape nuts": 72.0,
    "honey bunches of oats": 80.0,
    "kashi golean": 70.0,
    "lucky charms": 83.0,
    "raisin bran": 71.0,
    "shredded wheat": 79.0,
    "weetabix": 68.0,

    # Breads / crackers / baked goods
    "bread sticks": 68.0,
    "breadnut": 22.0,
    "crispbread": 65.0,
    "digestive biscuits": 62.0,
    "graham crackers": 77.0,
    "matzo": 84.0,
    "melba toast": 72.0,
    "oat crackers": 62.0,
    "crackers whole grain": 65.0,
    "rice crackers": 82.0,
    "rye crispbread": 62.0,
    "spelt bread": 47.0,
    "white pita": 55.0,
    "whole wheat tortilla": 43.0,
    "flour tortilla": 50.0,
    "yorkshire pudding": 29.0,

    # Pasta / noodles
    "soba noodles": 21.4,
    "cellophane noodles": 86.0,
    "chickpea pasta": 44.0,
    "lentil pasta": 53.0,
    "lo mein": 25.0,
    "spaetzle": 30.0,
    "shirataki noodles": 0.0,
    "udon noodles": 22.0,
    "japchae": 23.0,
    "chow mein": 30.0,

    # Rice dishes
    "risotto": 24.0,
    "nasi goreng": 26.0,
    "arroz con pollo": 18.0,
    "colcannon": 15.0,

    # Dumplings / wrapped
    "wonton": 28.0,
    "dim sum": 25.0,
    "pierogi": 35.0,
    "tamale": 18.0,
    "dolmades": 12.0,
    "spanakopita": 23.0,

    # Legumes / lentils
    "beluga lentils": 20.0,
    "butter beans": 20.0,
    "cannellini beans": 17.0,
    "cowpeas": 23.5,
    "dal": 18.0,
    "dried chickpeas": 61.0,
    "green lentils": 20.0,
    "pigeon peas": 23.0,
    "red lentils": 20.0,
    "refried beans": 14.5,
    "ful medames": 19.0,
    "mung bean soup": 15.0,

    # Soups / stews
    "borscht": 5.0,
    "bouillabaisse": 4.0,
    "black bean soup": 11.5,
    "celery root soup": 8.0,
    "clam chowder": 8.5,
    "corn chowder": 12.0,
    "french onion soup": 5.0,
    "gazpacho": 4.7,
    "goulash": 8.0,
    "laksa": 12.0,
    "lentil stew": 15.0,
    "lobster bisque": 6.0,
    "minestrone soup": 9.0,
    "pea soup": 11.0,
    "potato soup": 12.0,
    "pozole": 8.0,
    "tom kha": 5.0,
    "tom yum": 4.0,
    "vichyssoise": 8.0,

    # Meat dishes
    "beef bourguignon": 5.0,
    "beef bulgogi": 8.0,
    "beef stir fry": 5.0,
    "beef stroganoff": 8.0,
    "beef tacos": 15.0,
    "chicken caesar salad": 4.0,
    "chicken marsala": 5.0,
    "chicken stir fry": 5.0,
    "coq au vin": 3.0,
    "general tso chicken": 16.0,
    "kung pao chicken": 10.0,
    "massaman curry": 12.0,
    "osso buco": 3.0,
    "paneer tikka": 5.0,
    "rendang": 4.0,
    "satay": 10.0,
    "sweet and sour pork": 18.0,
    "tagine": 10.0,
    "shepherd's pie": 13.0,
    "fish tacos": 18.0,
    "quiche": 16.0,

    # Mexican / Latin
    "bean burrito": 25.0,
    "breakfast burrito": 20.0,
    "chilaquiles": 20.0,
    "chimichanga": 22.0,
    "enchilada": 18.0,
    "veggie tacos": 18.0,
    "ceviche": 3.0,

    # Asian dishes
    "banh mi": 30.0,

    # Candy / sweets
    "gummy candy": 77.0,
    "jelly beans": 93.0,
    "candy corn": 90.0,
    "peanut butter cups": 52.0,
    "milk chocolate": 57.0,
    "white chocolate": 59.0,
    "dark chocolate 85%": 24.0,

    # Baked desserts
    "angel food cake": 58.0,
    "beignets": 43.0,
    "black forest cake": 35.0,
    "cannoli": 32.0,
    "chocolate lava cake": 30.0,
    "churros": 44.0,
    "funnel cake": 40.0,
    "key lime pie": 32.0,
    "lemon bars": 50.0,
    "macaron": 67.0,
    "meringue": 80.0,
    "mousse": 18.0,
    "pavlova": 60.0,
    "pecan pie": 45.0,
    "profiteroles": 28.0,
    "shortbread": 65.0,
    "tres leches": 30.0,
    "mochi ice cream": 35.0,

    # Snacks
    "animal crackers": 72.0,
    "banana chips": 58.0,
    "cheese crackers": 58.0,
    "corn cakes": 79.0,
    "corn chips": 57.0,
    "corn tortilla chips": 59.0,
    "kale chips": 42.0,
    "pita chips": 55.0,
    "plantain chips": 55.0,
    "pork rinds": 0.0,
    "pretzel sticks": 79.0,
    "rice crackers": 82.0,
    "seaweed snacks": 25.0,
    "vanilla wafers": 70.0,
    "veggie straws": 60.0,

    # Sauces / condiments
    "alfredo sauce": 4.0,
    "apple cider vinegar": 0.9,
    "blue cheese dressing": 6.0,
    "chipotle sauce": 8.0,
    "coconut aminos": 10.0,
    "gochujang": 45.0,
    "harissa": 9.0,
    "hollandaise sauce": 1.0,
    "hot sauce": 3.0,
    "mango chutney": 35.0,
    "marinara sauce": 7.0,
    "miso paste": 26.0,
    "pesto": 4.0,
    "plum sauce": 38.0,
    "sweet chili sauce": 38.0,
    "thousand island dressing": 15.0,
    "worcestershire sauce": 19.0,
    "date syrup": 68.0,
    "bone broth": 0.5,

    # Syrups / sugars
    "brown sugar": 97.0,
    "corn syrup": 78.0,
    "monk fruit sweetener": 99.0,
    "powdered sugar": 100.0,
    "rice malt syrup": 80.0,

    # Fruits / vegetables
    "ackee": 1.0,
    "bitter melon": 3.7,
    "blood orange": 12.0,
    "boysenberries": 12.2,
    "cara cara orange": 11.8,
    "chayote": 4.5,
    "cherimoya": 17.7,
    "chicory": 4.7,
    "coconut flesh": 15.0,
    "currants": 14.0,
    "drumstick vegetable": 8.5,
    "elderberries": 18.4,
    "feijoa": 13.0,
    "lotus root": 17.2,
    "lotus seeds": 64.0,
    "mamey sapote": 32.0,
    "microgreens": 3.0,
    "napa cabbage": 2.2,
    "nettles": 7.5,
    "purple cabbage": 7.4,
    "purslane": 3.4,
    "quince": 15.3,
    "rambutan": 21.0,
    "samphire": 3.0,
    "sapodilla": 20.0,
    "savoy cabbage": 6.1,
    "tomatillo": 5.8,
    "ugli fruit": 9.0,

    # Dried fruit
    "dried cranberries": 82.0,
    "dried figs": 64.0,
    "dried mango": 78.0,

    # Salads
    "cobb salad": 4.0,
    "creamed spinach": 5.0,
    "fattoush": 12.0,
    "greek salad": 5.0,
    "macaroni salad": 18.0,
    "nicoise salad": 6.0,
    "pasta salad": 20.0,
    "tabbouleh": 18.0,
    "waldorf salad": 12.0,

    # Other
    "baba ganoush": 10.0,
    "polenta coarse": 22.0,
    "sunflower seed butter": 18.0,
    "tempeh bacon": 10.0,
    "vegetable stir fry": 6.0,
    "chai": 20.0,
}


def main():
    gi_path = Path("GlycoTrack/Resources/gi_database.json")
    usda_path = Path("GlycoTrack/Resources/usda_nutrition.json")

    with open(gi_path) as f:
        gi_entries = json.load(f)
    with open(usda_path) as f:
        usda_entries = json.load(f)

    usda_names = {e["name"].lower() for e in usda_entries}

    updated = 0
    missing_lookup = []

    for entry in gi_entries:
        name_lower = entry["name"].lower()
        if name_lower not in usda_names:
            if name_lower in CARBS_LOOKUP:
                entry["carbs"] = CARBS_LOOKUP[name_lower]
                updated += 1
            else:
                missing_lookup.append(entry["name"])

    if missing_lookup:
        print(f"WARNING: {len(missing_lookup)} entries still missing carbs lookup:", file=sys.stderr)
        for name in sorted(missing_lookup):
            print(f"  {name}", file=sys.stderr)
        sys.exit(1)

    with open(gi_path, "w") as f:
        json.dump(gi_entries, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Updated {updated} entries with carbs data")


if __name__ == "__main__":
    main()
