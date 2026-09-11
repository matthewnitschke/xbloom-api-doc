import Foundation

func crc16Kermit(_ data: [UInt8]) -> UInt16 {
    var crc: UInt16 = 0
    for byte in data {
        crc ^= UInt16(byte)
        for _ in 0..<8 {
            if crc & 0x0001 != 0 {
                crc = (crc >> 1) ^ 0x8408
            } else {
                crc >>= 1
            }
        }
    }
    return crc
}

func buildFrame(cmd: UInt8, seq: UInt8, payload: [UInt8], typeCode: UInt8 = 0x01) -> Data {
    var body = [UInt8]([0x58, 0x01, typeCode, cmd, seq])
    let len = UInt32(11 + payload.count)
    body.append(UInt8(truncatingIfNeeded: len & 0xFF))
    body.append(UInt8(truncatingIfNeeded: (len >> 8) & 0xFF))
    body.append(0x00)
    body.append(0x00)
    body.append(contentsOf: payload)
    let crc = crc16Kermit(body)
    body.append(UInt8(truncatingIfNeeded: crc & 0xFF))
    body.append(UInt8(truncatingIfNeeded: (crc >> 8) & 0xFF))
    return Data(body)
}

func float32Bits(_ value: Float) -> [UInt8] {
    var val = value
    return withUnsafeBytes(of: &val) { Array($0) }
}

func u32LE(_ value: UInt32) -> [UInt8] {
    [
        UInt8(truncatingIfNeeded: value & 0xFF),
        UInt8(truncatingIfNeeded: (value >> 8) & 0xFF),
        UInt8(truncatingIfNeeded: (value >> 16) & 0xFF),
        UInt8(truncatingIfNeeded: (value >> 24) & 0xFF)
    ]
}
