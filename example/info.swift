import AppKit
import CoreBluetooth

let serviceUUID = CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212")
let commandUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
let statusUUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")

let infoCode: UInt16 = 40521  // 0x9E49 RD_MachineInfo

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

struct MachineInfo {
    let serial: String
    let model: String
    let version: String
    let waterOK: Bool
    let volume: Int?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var centralManager: CBCentralManager!
    var connectedPeripheral: CBPeripheral?
    var commandCharacteristic: CBCharacteristic?
    var receivedInfo = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func requestInfo() {
        guard let characteristic = commandCharacteristic else { print("Not connected yet"); return }
        // 0xA4 session start + 0x56 status handshake — the machine replies with info
        connectedPeripheral?.writeValue(frame(cmd: 0xA4, seq: 0x1F, payload: [0x01, 0xB9, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]),
                                        for: characteristic, type: .withoutResponse)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connectedPeripheral?.writeValue(frame(cmd: 0x56, seq: 0x1F, payload: [0x01]),
                                                 for: characteristic, type: .withoutResponse)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            if !self.receivedInfo {
                print("No machine info received")
                NSApplication.shared.terminate(nil)
            }
        }
    }

    func parseInfo(_ data: Data) -> MachineInfo? {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return nil }
        var payload: [UInt8]
        if bytes[1] == 0x01 && bytes[2] == 0x01 {  // classic response frame
            let cmd = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
            guard cmd == infoCode else { return nil }
            payload = Array(bytes[10...].dropLast(2))
        } else if bytes[1] == 0x02 && bytes[2] == 0x07,  // notify frame
                  bytes[3] == 0x49,
                  let marker = bytes.firstIndex(of: 0xC1) {
            payload = Array(bytes[(marker + 1)...].dropLast(2))
        } else {
            return nil
        }
        guard payload.count >= 34 else { return nil }
        let ascii = { (r: Range<Int>) -> String in
            String(decoding: payload[r], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
        return MachineInfo(serial: ascii(0..<13),
                           model: ascii(13..<19),
                           version: ascii(19..<29),
                           waterOK: payload[33] == 1,
                           volume: payload.count > 36 ? Int(payload[36]) : nil)
    }

    func handleInfo(_ info: MachineInfo) {
        receivedInfo = true
        print("Serial:  \(info.serial)")
        print("Model:   \(info.model)")
        print("Version: \(info.version)")
        print("Water:   \(info.waterOK ? "OK" : "LOW")")
        if let volume = info.volume {
            print("Volume:  \(volume)")
        }
        NSApplication.shared.terminate(nil)
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
                requestInfo()
            }
            if characteristic.uuid == statusUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let info = parseInfo(data) else { return }
        handleInfo(info)
    }
}

app.run()