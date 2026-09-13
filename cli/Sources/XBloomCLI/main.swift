import Foundation

if CommandLine.arguments.count >= 2, CommandLine.arguments[1].hasPrefix("-") {
    print("Usage: xbloom-cli [recipe.json]  (or pipe JSON via stdin)")
    exit(1)
}

let recipe: Recipe
do {
    let data: Data
    if CommandLine.arguments.count >= 2 {
        data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    } else {
        data = FileHandle.standardInput.readDataToEndOfFile()
    }
    recipe = try JSONDecoder().decode(Recipe.self, from: data)
    try recipe.validate()
} catch {
    print("Failed to load recipe: \(error.localizedDescription)")
    exit(1)
}

let totalMl = recipe.pours.reduce(0) { $0 + $1.ml }
let ratio = Double(totalMl) / Double(recipe.dose)
if let grind = recipe.grind {
    print("Recipe: \(recipe.dose)g dose, grind size \(grind.size) @ \(grind.rpm)rpm")
} else {
    print("Recipe: \(recipe.dose)g dose, pre-ground (no grind)")
}
print("Pours: \(recipe.pours.count) (\(totalMl)mL total, \(String(format: "%.1f", ratio)):1 ratio)")

let manager = BLEManager()
var state: UInt8 = 0x01
var recipeSent = false
var finished = false
var recipeFramesSent = false

let stateNames: [UInt8: String] = [
    0x01: "idle", 0x0C: "no_water", 0x0F: "no_beans", 0x10: "brewing",
    0x1D: "loading", 0x1F: "armed", 0x1E: "awaiting_confirm",
    0x22: "starting", 0x23: "brewing", 0x24: "ready",
    0x3B: "brewing", 0x41: "complete", 0x43: "saving", 0x25: "saved"
]

func sendRecipeFrames() {
    guard !recipeFramesSent else { return }
    recipeFramesSent = true

    var dosePayload = [UInt8](repeating: 0x00, count: 13)
    dosePayload[0] = 0x01
    dosePayload[9] = UInt8(recipe.dose)
    manager.writeFrame(buildFrame(cmd: 0xA6, seq: 0x1F, payload: dosePayload))

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        var stagePayload: [UInt8] = [0x01]
        stagePayload.append(contentsOf: float32Bits(110.0))
        stagePayload.append(contentsOf: float32Bits(90.0))
        manager.writeFrame(buildFrame(cmd: 0xA8, seq: 0x1F, payload: stagePayload))
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        let (opcode, payload) = encodePayload(recipe: recipe)
        manager.writeFrame(buildFrame(cmd: opcode, seq: 0x1F, payload: payload))
        recipeSent = true
        print("Brew profile sent")
    }
}

func reportState(_ newState: UInt8) {
    guard newState != state else { return }
    state = newState
    let name = stateNames[newState] ?? String(format: "0x%02X", newState)
    print("State: \(name)")
}

manager.onError = { message in
    print("Error: \(message)")
    exit(1)
}

manager.onReady = {
    print("Connected, starting session...")
    manager.writeFrame(buildFrame(cmd: 0xA4, seq: 0x1F,
                                  payload: [0x01, 0xB9, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        manager.writeFrame(buildFrame(cmd: 0x56, seq: 0x1F, payload: [0x01]))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        sendRecipeFrames()
    }
}

manager.onNotification = { data in
    let bytes = [UInt8](data)
    guard bytes.count >= 10, bytes[0] == 0x58 else { return }
    guard bytes[1] == 0x02, bytes[2] == 0x07, bytes[3] == 0x57,
          let marker = bytes.firstIndex(of: 0xC1), marker + 1 < bytes.count else { return }
    let newState = bytes[marker + 1]
    reportState(newState)
    if newState == 0x1F, recipeSent, !finished {
        finished = true
        print("Recipe loaded — machine armed (state 0x1F)")
        print("Approve on the device to start brewing")
        exit(0)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) {
    if !finished {
        let name = stateNames[state] ?? String(format: "0x%02X", state)
        print("Timed out waiting for machine to arm (last state: \(name))")
        exit(1)
    }
}

manager.startScanning()
RunLoop.main.run()