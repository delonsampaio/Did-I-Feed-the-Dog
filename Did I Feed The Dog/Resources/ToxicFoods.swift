import Foundation

struct SafetyEntry: Identifiable {
    let id = UUID()
    let name: String
    let danger: String
}

let toxicFoods: [SafetyEntry] = [
    SafetyEntry(name: "Chocolate",        danger: "Contains theobromine, which dogs can't metabolize. Can cause seizures and death even in small amounts."),
    SafetyEntry(name: "Grapes & Raisins", danger: "Can cause sudden kidney failure. Even small amounts are potentially fatal."),
    SafetyEntry(name: "Xylitol",          danger: "Artificial sweetener found in gum, candy, and peanut butter. Causes rapid insulin release and liver failure."),
    SafetyEntry(name: "Onions & Garlic",  danger: "Damages red blood cells, causing hemolytic anemia. All forms (raw, cooked, powdered) are toxic."),
    SafetyEntry(name: "Macadamia Nuts",   danger: "Causes weakness, vomiting, tremors, and hyperthermia within 12 hours."),
    SafetyEntry(name: "Avocado",          danger: "Persin in the fruit and pit can cause vomiting and diarrhea."),
    SafetyEntry(name: "Alcohol",          danger: "Even small amounts cause vomiting, disorientation, and can be fatal."),
    SafetyEntry(name: "Caffeine",         danger: "Found in coffee, tea, and energy drinks. Causes rapid heart rate, tremors, and seizures."),
    SafetyEntry(name: "Raw Yeast Dough",  danger: "Expands in the stomach and produces alcohol as it ferments, causing bloat and alcohol poisoning."),
    SafetyEntry(name: "Cooked Bones",     danger: "Splinter easily and can puncture the digestive tract. Raw bones are generally safer."),
    SafetyEntry(name: "Nutmeg",           danger: "Contains myristicin, causing disorientation, increased heart rate, and seizures."),
    SafetyEntry(name: "Salt",             danger: "Large amounts cause sodium ion poisoning — excessive thirst, vomiting, tremors, and seizures."),
    SafetyEntry(name: "Corn on the Cob",  danger: "The cob cannot be digested and causes intestinal blockage requiring emergency surgery."),
    SafetyEntry(name: "Cherries",         danger: "Pits, stems, and leaves contain cyanide. The flesh is non-toxic but the pits are dangerous."),
    SafetyEntry(name: "Peaches & Plums",  danger: "Pits contain cyanide and are a choking and intestinal blockage hazard."),
]
