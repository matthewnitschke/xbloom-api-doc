import Foundation

func encodePayload(recipe: Recipe) -> (opcode: UInt8, payload: [UInt8]) {
    let usesGrinder = recipe.grind != nil
    let grindWire: UInt8 = usesGrinder ? UInt8(recipe.grind!.size) : 0xFE

    var segments: [UInt8] = []
    for (i, pour) in recipe.pours.enumerated() {
        let pat: UInt8
        let agit: UInt8
        switch pour.pattern {
        case .spiral:
            pat = 0x02
            agit = pour.agitation ? 0x02 : 0x00
        case .ring:
            pat = 0x01
            agit = 0x00
        case .center:
            pat = 0x00
            agit = 0x01
        }

        let rpm = (i == 0) ? (recipe.grind?.rpm ?? 0) : 0
        let negPause = UInt8((256 - pour.pause) & 0xFF)
        let flow10 = UInt8(round(pour.flow * 10))

        if pour.ml > 127 {
            var remaining = pour.ml
            while remaining > 127 {
                segments.append(contentsOf: [127, UInt8(pour.temp), pat, agit])
                remaining -= 127
            }
            segments.append(contentsOf: [
                UInt8(remaining), UInt8(pour.temp), pat, agit,
                negPause, 0x00, UInt8(rpm), flow10
            ])
        } else {
            segments.append(contentsOf: [
                UInt8(pour.ml), UInt8(pour.temp), pat, agit,
                negPause, 0x00, UInt8(rpm), flow10
            ])
        }
    }

    let totalMl = recipe.pours.reduce(0) { $0 + $1.ml }
    let ratioByte = UInt8((UInt32(round(Double(totalMl) / Double(recipe.dose) * 10)) & 0xFF))

    var payload: [UInt8] = [0x01, UInt8(segments.count)]
    payload.append(contentsOf: segments)
    payload.append(grindWire)
    payload.append(ratioByte)

    return (usesGrinder ? 0x41 : 0x44, payload)
}
