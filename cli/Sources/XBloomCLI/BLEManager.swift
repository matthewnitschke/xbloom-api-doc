import Foundation
import CoreBluetooth

let serviceUUID = CBUUID(string: "0000e0ff-3c17-d293-8e48-14fe2e4da212")
let commandUUID = CBUUID(string: "0000ffe1-0000-1000-8000-00805f9b34fb")
let statusUUID = CBUUID(string: "0000ffe2-0000-1000-8000-00805f9b34fb")

final class BLEManager: NSObject {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?

    var onReady: (() -> Void)?
    var onNotification: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }

    func startScanning() {
        guard central.state == .poweredOn else {
            return
        }
        if central.isScanning { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func writeFrame(_ frame: Data) {
        guard let peripheral = peripheral, let characteristic = commandCharacteristic else {
            onError?("Not connected")
            return
        }
        peripheral.writeValue(frame, for: characteristic, type: .withoutResponse)
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .unauthorized, .unsupported, .poweredOff:
            let reason: String
            switch central.state {
            case .poweredOff:
                reason = "Bluetooth is powered off — turn it on in System Settings"
            case .unauthorized:
                reason = "Bluetooth access denied — grant the terminal Bluetooth permission"
            case .unsupported:
                reason = "Bluetooth not supported on this Mac"
            default:
                reason = "Bluetooth unavailable (state \(central.state.rawValue))"
            }
            onError?(reason)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onError?("Disconnected from peripheral")
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            onError?("Service discovery failed: \(error!.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics([commandUUID, statusUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            onError?("Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case commandUUID:
                commandCharacteristic = characteristic
            case statusUUID:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        if commandCharacteristic != nil {
            onReady?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        onNotification?(data)
    }
}