import Foundation
import Testing

@testable import DeskMuxDiagnostics

@Test func parsesProfilerDataWithoutSerialsOrAddresses() throws {
  let json = #"""
    {
      "SPHardwareDataType": [{
        "machine_name": "MacBook Air",
        "machine_model": "MacBookAir10,1",
        "chip_type": "Apple M1",
        "physical_memory": "16 GB",
        "platform_UUID": "must-not-escape"
      }],
      "SPDisplaysDataType": [{
        "spdisplays_ndrvs": [{
          "_name": "U27B3CF",
          "_spdisplays_resolution": "3840 x 2160 @ 60.00Hz",
          "spdisplays_main": "spdisplays_yes",
          "spdisplays_online": "spdisplays_yes",
          "spdisplays_serial_number": "must-not-escape"
        }]
      }],
      "SPUSBHostDataType": [{
        "_items": [{
          "_name": "USB Receiver",
          "USBDeviceKeyVendorName": "Logitech",
          "USBDeviceKeyVendorID": "0x046d",
          "USBDeviceKeyProductID": "0xc548",
          "USBDeviceKeySerialNumber": "must-not-escape"
        }]
      }],
      "SPBluetoothDataType": [{
        "device_connected": [{
          "Keyboard": {"device_address": "must-not-escape"}
        }],
        "device_not_connected": [{
          "Mouse": {"device_address": "must-not-escape"}
        }]
      }]
    }
    """#

  let diagnostics = try DiagnosticsParser.parse(
    profilerData: Data(json.utf8),
    macOSVersion: "26.5.2",
    architecture: "arm64"
  )

  #expect(diagnostics.machine.identifier == "MacBookAir10,1")
  #expect(
    diagnostics.displays == [
      Display(name: "U27B3CF", resolution: "3840 x 2160 @ 60.00Hz", isMain: true, isOnline: true)
    ])
  #expect(
    diagnostics.usbDevices == [
      USBDevice(
        name: "USB Receiver", manufacturer: "Logitech", vendorID: "0x046d", productID: "0xc548")
    ])
  #expect(
    diagnostics.bluetoothDevices == [
      BluetoothDevice(name: "Keyboard", connected: true),
      BluetoothDevice(name: "Mouse", connected: false),
    ])

  let encoded = try JSONEncoder().encode(diagnostics)
  #expect(!String(decoding: encoded, as: UTF8.self).contains("must-not-escape"))
}
