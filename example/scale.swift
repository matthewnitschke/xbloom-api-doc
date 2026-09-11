import AppKit
import CoreBluetooth

let serviceUUID = CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212")
let commandUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
let statusUUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")

let weightCode: UInt16 = 20501  // 0x501D RD_CURRENT_WEIGHT2

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)

// Frame building — 58 01 01 | CMD u16 LE | LEN u32 LE | 01 | payload | CRC16 LE
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

func frame(cmd: UInt8, seq: UInt8, payload: [UInt8]) -> Data {
    var body = [UInt8]([0x58, 0x01, 0x01, cmd, seq])
    let len = UInt32(12 + payload.count)
    body.append(contentsOf: [UInt8(truncatingIfNeeded: len & 0xFF), UInt8(truncatingIfNeeded: (len >> 8) & 0xFF),
                             UInt8(truncatingIfNeeded: (len >> 16) & 0xFF), UInt8(truncatingIfNeeded: (len >> 24) & 0xFF)])
    body.append(0x01)
    body.append(contentsOf: payload)
    let crc = crc16Kermit(body)
    body.append(UInt8(truncatingIfNeeded: crc & 0xFF))
    body.append(UInt8(truncatingIfNeeded: (crc >> 8) & 0xFF))
    return Data(body)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var centralManager: CBCentralManager!
    var connectedPeripheral: CBPeripheral?
    var commandCharacteristic: CBCharacteristic?

    var scaleReading: Double = 0
    var coffeeReading: Double = 0
    var waterReading: Double = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // "Enable scale mode" — opening a session (0xA4) + status handshake (0x56)
    // makes the machine start streaming the scale weights on ffe2.
    func enableScale() {
        guard let characteristic = commandCharacteristic else { print("Not connected yet"); return }
        connectedPeripheral?.writeValue(frame(cmd: 0xA4, seq: 0x1F, payload: [0x01, 0xB9, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]),
                                        for: characteristic, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connectedPeripheral?.writeValue(frame(cmd: 0x56, seq: 0x1F, payload: [0x01]),
                                                 for: characteristic, type: .withoutResponse)
        }
    }

    func updateOutput() {
        let lines = [
            "  * Scale: \(String(format: "%.1f", scaleReading)) g",
            "  * Coffee: \(String(format: "%.1f", coffeeReading)) g",
            "  * Water: \(String(format: "%.1f", waterReading)) g",
        ]
        updateMultilineOutput(lines: lines)
    }

    var isFirstOutput = true
    func updateMultilineOutput(lines: [String]) {
        if (isFirstOutput) {
            isFirstOutput = false;
            for line in lines {
                print(line)
            }
            return
        }
        print("\u{001B}[\(lines.count)A", terminator: "")
        for line in lines {
            print("\u{001B}[K" + line)
        }
        fflush(stdout)
    }

    func handleNotify(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, bytes[0] == 0x58 else { return }

        // Stream frames (58 02 07 | TYPE | SUB | LEN | C1 | f32 LE): 0x4B = water
        // in milligrams, 0x15 = coffee in grams.
        if bytes[1] == 0x02, let marker = bytes.firstIndex(of: 0xC1), marker + 4 < bytes.count {
            let value = bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: marker + 1, as: Float.self) }
            if bytes[3] == 0x4B {
                waterReading = Double(value) / 1000.0
            } else if bytes[3] == 0x15 {
                coffeeReading = Double(value)
            }
            updateOutput()
            return
        }

        // Classic response (58 01 01 | CMD u16 LE | LEN | 01 | f32 LE | CRC):
        // 20501 RD_CURRENT_WEIGHT2 = current scale weight in grams.
        if bytes[1] == 0x01 && bytes[2] == 0x01,
           (UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)) == weightCode,
           bytes.count >= 14 {
            scaleReading = Double(bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 10, as: Float.self) })
            updateOutput()
        }
    }
}

extension AppDelegate: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Searching for \"xbloom\"", terminator: "")
            central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if peripheral.name?.lowercased().starts(with: "xbloom") == true {
            central.stopScan()
            connectedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            print("\rConnected to \"xbloom\" ")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }
}

extension AppDelegate: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([commandUUID, statusUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == commandUUID {
                commandCharacteristic = characteristic
                enableScale()
            }
            if characteristic.uuid == statusUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        handleNotify(data)
    }
}

app.run()