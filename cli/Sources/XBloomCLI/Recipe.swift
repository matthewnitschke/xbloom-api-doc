import Foundation

struct Recipe: Decodable {
    let dose: Int
    let grind: GrindConfig?
    let pours: [Pour]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dose = try container.decodeIfPresent(Int.self, forKey: .dose) ?? 15
        grind = try container.decodeIfPresent(GrindConfig.self, forKey: .grind)
        pours = try container.decode([Pour].self, forKey: .pours)
    }

    private enum CodingKeys: String, CodingKey {
        case dose, grind, pours
    }

    struct GrindConfig: Decodable {
        let size: Int
        let rpm: Int
    }

    struct Pour: Decodable {
        let ml: Int
        let temp: Int
        let pattern: Pattern
        let agitation: Bool
        let pause: Int
        let flow: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ml = try container.decode(Int.self, forKey: .ml)
            temp = try container.decodeIfPresent(Int.self, forKey: .temp) ?? 93
            pattern = try container.decodeIfPresent(Pattern.self, forKey: .pattern) ?? .spiral
            agitation = try container.decodeIfPresent(Bool.self, forKey: .agitation) ?? false
            pause = try container.decodeIfPresent(Int.self, forKey: .pause) ?? 0
            flow = try container.decodeIfPresent(Double.self, forKey: .flow) ?? 3.0
        }

        private enum CodingKeys: String, CodingKey {
            case ml, temp, pattern, agitation, pause, flow
        }
    }

    enum Pattern: String, Decodable {
        case spiral
        case ring
        case center
    }

    func validate() throws {
        guard (1...25).contains(dose) else {
            throw RecipeError.invalidDose(dose)
        }
        if let grind = grind {
            guard (1...80).contains(grind.size) else {
                throw RecipeError.invalidGrindSize(grind.size)
            }
            guard grind.rpm == 0 || (60...120).contains(grind.rpm), grind.rpm % 10 == 0 else {
                throw RecipeError.invalidRPM(grind.rpm)
            }
        }
        guard !pours.isEmpty else {
            throw RecipeError.noPours
        }
        for (i, pour) in pours.enumerated() {
            guard (1...4000).contains(pour.ml) else {
                throw RecipeError.invalidPourVolume(i, pour.ml)
            }
            guard (40...95).contains(pour.temp) else {
                throw RecipeError.invalidPourTemp(i, pour.temp)
            }
            guard pour.pattern != .center || !pour.agitation else {
                throw RecipeError.agitationWithCenter(i)
            }
            guard (0...255).contains(pour.pause) else {
                throw RecipeError.invalidPause(i, pour.pause)
            }
            guard (3.0...3.5).contains(pour.flow) else {
                throw RecipeError.invalidFlow(i, pour.flow)
            }
        }
    }
}

enum RecipeError: LocalizedError {
    case invalidDose(Int)
    case invalidGrindSize(Int)
    case invalidRPM(Int)
    case noPours
    case invalidPourVolume(Int, Int)
    case invalidPourTemp(Int, Int)
    case agitationWithCenter(Int)
    case invalidPause(Int, Int)
    case invalidFlow(Int, Double)

    var errorDescription: String? {
        switch self {
        case .invalidDose(let v): return "Invalid dose: \(v)g (must be 1-25)"
        case .invalidGrindSize(let v): return "Invalid grind size: \(v) (must be 1-80)"
        case .invalidRPM(let v): return "Invalid RPM: \(v) (must be 0, or 60-120 in steps of 10)"
        case .noPours: return "Recipe must have at least one pour"
        case .invalidPourVolume(let i, let v): return "Pour \(i): invalid volume \(v)mL (must be 1-4000)"
        case .invalidPourTemp(let i, let v): return "Pour \(i): invalid temp \(v)°C (must be 40-95)"
        case .agitationWithCenter(let i): return "Pour \(i): agitation not valid with center pattern"
        case .invalidPause(let i, let v): return "Pour \(i): invalid pause \(v)s (must be 0-255)"
        case .invalidFlow(let i, let v): return "Pour \(i): invalid flow \(v) (must be 3.0-3.5)"
        }
    }
}
