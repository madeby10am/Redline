import Foundation
import IOKit

// MARK: - CPU

final class CPUReader {
    private var previous: [UInt32] = []

    /// Fraction of CPU time spent busy since the last call (0...1).
    func usage() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let current = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { previous = current }
        guard previous.count == current.count else { return 0 }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(cpuCount) {
            for state in 0..<states {
                let i = core * states + state
                let delta = UInt64(current[i] &- previous[i])
                total += delta
                if state != Int(CPU_STATE_IDLE) { busy += delta }
            }
        }
        return total == 0 ? 0 : Double(busy) / Double(total)
    }
}

// MARK: - Memory

enum MemoryReader {
    static let total = Double(ProcessInfo.processInfo.physicalMemory)

    /// Bytes in use, counted the way Activity Monitor's "Memory Used" does
    /// (app memory + wired + compressed).
    static func used() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let appPages = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let pages = appPages + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return pages * Double(vm_kernel_page_size)
    }
}

// MARK: - SMC (fans)

/// Mirrors the kernel's SMCParamStruct (80 bytes).
private struct SMCParam {
    struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }

    var key: UInt32 = 0
    var version = Version()
    var pLimit = PLimit()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

struct Fan: Identifiable {
    let id: Int
    let rpm: Double
    let maxRPM: Double
}

final class SMC {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit { IOServiceClose(connection) }

    func fans() -> [Fan] {
        let count = Int(read("FNum") ?? 0)
        return (0..<count).compactMap { i in
            guard let rpm = read("F\(i)Ac") else { return nil }
            return Fan(id: i, rpm: max(rpm, 0), maxRPM: read("F\(i)Mx") ?? 0)
        }
    }

    func read(_ key: String) -> Double? {
        var input = SMCParam()
        input.key = Self.fourCC(key)
        input.data8 = 9 // get key info
        guard let info = call(&input) else { return nil }

        input.keyInfo = info.keyInfo
        input.data8 = 5 // read key
        guard let output = call(&input) else { return nil }

        let size = Int(info.keyInfo.dataSize)
        let b = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        switch Self.string(info.keyInfo.dataType) {
        case "flt " where size == 4:
            return Double(b.withUnsafeBytes { Float(bitPattern: $0.loadUnaligned(as: UInt32.self).littleEndian) })
        case "fpe2" where size == 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "ui8 " where size == 1:
            return Double(b[0])
        case "ui16" where size == 2:
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        default:
            return nil
        }
    }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var output = SMCParam()
        var outputSize = MemoryLayout<SMCParam>.stride
        let result = IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<SMCParam>.stride, &output, &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(_ code: UInt32) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .ascii) ?? ""
    }
}

// MARK: - Temperature (Apple Silicon HID sensors)

final class ThermalReader {
    private let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
    private let temperatureEvent: Int64 = 15
    private var temperatureField: Int32 { Int32(temperatureEvent << 16) }

    init() {
        let match = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = IOHIDEventSystemClientSetMatching(client, match)
    }

    /// Every sensor the system exposes, by name, in °C.
    func allSensors() -> [String: Double] {
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] else { return [:] }
        var readings: [String: Double] = [:]
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as String?,
                  let event = IOHIDServiceClientCopyEvent(service, temperatureEvent, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, temperatureField)
            if value > 0 && value < 150 { readings[name] = value }
        }
        return readings
    }

    /// Hottest CPU die sensor, which is what you'd feel on the chassis.
    func cpuTemperature() -> Double? {
        let sensors = allSensors()
        let die = sensors.filter { $0.key.contains("tdie") }.map(\.value)
        return die.max() ?? sensors.values.max()
    }
}
