import Foundation
import IOKit.hid

/// Reads the feature report regularly: HID input notifications do not guarantee
/// a fresh angle for every step of lid movement. Hardware I/O stays off the UI thread.
final class LidSensor {
    var onAngle: ((Double?) -> Void)?
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    private let readerQueue = DispatchQueue(label: "local.openbendy.sensor", qos: .userInteractive)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var polling: DispatchSourceTimer?
    private var lastAngle: Double?
    private var published = false
    init() { readerQueue.setSpecific(key: queueKey, value: true) }
    func start() {
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05AC, kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8A]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard let context, result == kIOReturnSuccess else { return }
            let sensor = Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue()
            sensor.readerQueue.async { [weak sensor] in
                guard let sensor else { return }
                if IOHIDDeviceOpen(device, 0) == kIOReturnSuccess {
                    if let old = sensor.device { IOHIDDeviceClose(old, 0) }
                    sensor.device = device; sensor.read()
                }
            }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let sensor = Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue()
            sensor.readerQueue.async { [weak sensor] in
                guard let sensor, sensor.device == device else { return }
                IOHIDDeviceClose(device, 0); sensor.device = nil; sensor.publish(nil)
            }
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, _ in
            guard let context, result == kIOReturnSuccess else { return }
            let sensor = Unmanaged<LidSensor>.fromOpaque(context).takeUnretainedValue()
            sensor.readerQueue.async { [weak sensor] in sensor?.read() }
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        if result != kIOReturnSuccess { onAngle?(nil) }
        let timer = DispatchSource.makeTimerSource(queue: readerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.read() }
        polling = timer
        timer.resume()
    }
    private func read() {
        guard let device else { publish(nil); return }
        var report = [UInt8](repeating: 0, count: 8)
        var count = report.count
        let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &count)
        guard status == kIOReturnSuccess, count >= 3 else { publish(nil); return }
        let degrees = Double(UInt16(report[1]) | UInt16(report[2]) << 8)
        publish((0...180).contains(degrees) ? degrees : nil)
    }
    private func publish(_ angle: Double?) {
        guard !published || angle != lastAngle else { return }
        published = true; lastAngle = angle
        DispatchQueue.main.async { [weak self] in self?.onAngle?(angle) }
    }
    func stop() {
        polling?.cancel(); polling = nil
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let close = {
            if let device = self.device { IOHIDDeviceClose(device, 0) }
            self.device = nil
        }
        if DispatchQueue.getSpecific(key: queueKey) == true { close() }
        else { readerQueue.sync(execute: close) }
        IOHIDManagerClose(manager, 0)
    }
    deinit { stop() }
}
