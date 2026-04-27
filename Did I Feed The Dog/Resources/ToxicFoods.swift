import Foundation

enum DangerLevel {
    case emergency
    case warning

    var emoji: String {
        switch self {
        case .emergency: return "🚨"
        case .warning:   return "⚠️"
        }
    }

    var label: String {
        switch self {
        case .emergency: return "Emergency"
        case .warning:   return "Warning"
        }
    }
}

struct SafetyEntry: Identifiable {
    let id = UUID()
    let name: String
    let danger: String
    let level: DangerLevel
}

let toxicFoods: [SafetyEntry] = [
    // EMERGENCY — immediately life-threatening, even in small amounts
    SafetyEntry(name: "Xylitol",              danger: "Artificial sweetener in gum, candy, and some peanut butters. Causes rapid, severe insulin release and liver failure. Even a small amount can be fatal.", level: .emergency),
    SafetyEntry(name: "Grapes & Raisins",     danger: "Cause sudden, acute kidney failure. Even a few grapes can be fatal — no safe dose is known. Symptoms appear within 24 hours.", level: .emergency),
    SafetyEntry(name: "Hops",                 danger: "Used in home brewing. Causes a life-threatening, uncontrolled spike in body temperature (malignant hyperthermia). Can be fatal within hours.", level: .emergency),
    SafetyEntry(name: "Tobacco & Nicotine",   danger: "Cigarettes, e-cigarette refills, and nicotine patches. Even a small cigarette butt can be fatal to a small dog. Causes rapid heart rate, seizures, and cardiac arrest.", level: .emergency),
    SafetyEntry(name: "Wild Mushrooms",       danger: "Some backyard varieties (e.g. Amanita) are acutely lethal and cause liver failure. When in doubt, treat any mushroom as an emergency.", level: .emergency),
    SafetyEntry(name: "Moldy Foods",          danger: "Mold produces tremorgenic mycotoxins that cause severe, uncontrollable muscle tremors and seizures. Even a small moldy piece of food is dangerous.", level: .emergency),
    SafetyEntry(name: "Chocolate",            danger: "Contains theobromine, which dogs can't metabolize. Dark chocolate and baking chocolate are most dangerous. Can cause seizures and cardiac failure.", level: .emergency),
    SafetyEntry(name: "Macadamia Nuts",       danger: "Cause rapid-onset weakness, tremors, vomiting, and hyperthermia within 12 hours. The exact toxin is unknown. Even small amounts cause severe symptoms.", level: .emergency),
    SafetyEntry(name: "Black Walnuts",        danger: "Contain juglone and can harbor mold that produces tremorgenic mycotoxins. Causes seizures, tremors, and neurological damage.", level: .emergency),
    SafetyEntry(name: "Rhubarb & Star Fruit", danger: "Contain calcium oxalate crystals that cause sudden kidney failure. Can also cause drooling, tremors, and difficulty swallowing.", level: .emergency),

    // WARNING — dangerous, especially with repeated exposure or larger amounts
    SafetyEntry(name: "Onions & Garlic",      danger: "All forms (raw, cooked, powdered) damage red blood cells, causing hemolytic anemia. Cumulative exposure is dangerous — repeated small amounts add up.", level: .warning),
    SafetyEntry(name: "Chives & Leeks",       danger: "Members of the Allium family like onions and garlic. Cause the same red blood cell damage leading to anemia. Often overlooked.", level: .warning),
    SafetyEntry(name: "Alcohol",              danger: "Even small amounts cause vomiting, disorientation, dangerous drops in blood sugar, and can be fatal. Never give intentionally.", level: .warning),
    SafetyEntry(name: "Caffeine",             danger: "Coffee, tea, energy drinks, and some medications. Causes rapid heart rate, high blood pressure, tremors, and seizures. Dose-dependent.", level: .warning),
    SafetyEntry(name: "Avocado",              danger: "Persin in the flesh, pit, and skin causes vomiting and diarrhea. The large pit is also a choking and intestinal blockage hazard.", level: .warning),
    SafetyEntry(name: "Raw Yeast Dough",      danger: "Expands in the warm stomach and produces alcohol as it ferments. Causes painful bloat and alcohol poisoning simultaneously.", level: .warning),
    SafetyEntry(name: "Cooked Bones",         danger: "Splinter into sharp shards that can puncture the mouth, throat, or digestive tract. Raw bones are generally safer.", level: .warning),
    SafetyEntry(name: "Nutmeg",               danger: "Contains myristicin, causing disorientation, high heart rate, and seizures. Large amounts are needed for toxicity, but better avoided.", level: .warning),
    SafetyEntry(name: "Salt",                 danger: "Large quantities cause sodium ion poisoning — excessive thirst, vomiting, diarrhea, tremors, and seizures.", level: .warning),
    SafetyEntry(name: "Corn on the Cob",      danger: "The cob cannot be digested and causes intestinal blockage requiring emergency surgery. The corn kernels themselves are fine.", level: .warning),
    SafetyEntry(name: "Cherries",             danger: "Pits, stems, and leaves contain cyanide. The flesh is non-toxic but the pits are a serious hazard and choking risk.", level: .warning),
    SafetyEntry(name: "Peaches & Plums",      danger: "Pits contain cyanide and are both a poisoning and intestinal blockage hazard. Peeled, pitted fruit is generally safe.", level: .warning),
    SafetyEntry(name: "Green Tomatoes & Raw Potatoes", danger: "Contain solanine, a glycoalkaloid toxic to the digestive and nervous systems. Ripe red tomatoes and cooked potatoes are generally safe.", level: .warning),
]
