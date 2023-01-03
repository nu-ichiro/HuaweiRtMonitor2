//
//  HuaweiRtMonitor2App.swift
//  HuaweiRtMonitor2
//
//  Created by 中橋 一朗 on 2022/12/25.
//

import SwiftUI
import Combine

class RtStatusSeries : Identifiable {
    var id = UUID()
    var timestamp: Date
    var down: Double
    var up: Double
    var sinr: Int
    
    init(timestamp: Date, down: Double, up: Double, sinr: Int) {
        self.timestamp = timestamp
        self.down = down
        self.up = up
        self.sinr = sinr
    }
}

let RtStatusRetentionPeriod = 300.0 // sec
let RtStatusInterval = 5.0 //sec

class HuaweiRtStatus : ObservableObject {
    @Published var downMbps: String = "-1"
    @Published var upMbps: String = "-1"
    @Published var rssi: String = "-dB"
    @Published var sinr: String = "-dB"
    @Published var series: [RtStatusSeries] = []
    @Published var errorMessage = ""
}

struct RtStatusMsg {
    var success: Bool = false
    var down: Int = -1
    var up: Int = -1
    var rssi: String = "-dB"
    var sinr: String = "-dB"
}

let RtStatus = HuaweiRtStatus()
let MonitorCtl = RtMonitorController()

@main
struct HuaweiRtMonitor2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            /*
            ContentView()
                .environmentObject(RtStatus)
             */
            SettingsView()
        }.defaultSize(CGSize(width: 200, height: 100))
    }
}

extension Notification.Name {
    static let HuaweiRtStatusUpdated = Notification.Name("HuaweiRtStatusUpdated")
}


class RtMonitorController {
    @AppStorage("huaweiRtHost") private var huaweiRtHost = "192.168.1.1"
    @AppStorage("huaweiRtUserID") private var huaweiRtUserID = "admin"
    @AppStorage("huaweiRtPassword") private var huaweiRtPassword = "xxxxx"
    
    var statusUpdateTimer: Timer?
    let rts = HuaweiRtSession()
    var msg = RtStatusMsg()
    var updateSuccess: Bool = false
    
    var timerCancellable: AnyCancellable?
    var updateInProgress: Bool = false
    
    func start() {
        let statusBarButton = StatusItem!.button!
        statusBarButton.attributedTitle = statusString()
        //statusBarButton.action = #selector(AppDelegate.togglePopover(sender:))
        
        timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.updateStatus()
            }
        
        // first update
        updateStatus()
    }
    
    
    func updateStatus() {
        let semaphore = DispatchSemaphore(value: 0)

        if updateInProgress {
            print("Status update is still in progress.")
            return
        }
        updateInProgress = true
        
        self.msg.success = false
        self.msg.down = 0
        self.msg.up = 0
        self.msg.rssi = "0dB"
        self.msg.sinr = "0dB"
        
        Task {
            do {
                try await self.rts.connect(host:huaweiRtHost, userID:huaweiRtUserID, password:huaweiRtPassword)
                
                let (band, rsrq, rsrp, rssi, sinr) = await self.rts.signalStatus()
                print("Signal: band=\(band) rsrq=\(rsrq) rsrp=\(rsrp) rssi=\(rssi) sinr=\(sinr)")
                
                //let cst = await self.rts.connectionStatus()
                //print("Connection Status: \(cst)")
                
                let (down, up) = await self.rts.trafficStatus()
                print("Traffic: down=\(down) up=\(up)")
                
                try await self.rts.close()
                
                self.msg.down = down
                self.msg.up = up
                self.msg.rssi = rssi
                self.msg.sinr = sinr
                
                self.msg.success = true
            } catch {
                print("Failed to obtain router status!")
            }
            semaphore.signal()
            
        }
        
        semaphore.wait()
        updateInProgress = false
        
        RtStatus.downMbps = String(format:"%0.1f", Double(self.msg.down) * 8.0 / 1000000)
        RtStatus.upMbps = String(format:"%0.1f", Double(self.msg.up) * 8.0 / 1000000)
        RtStatus.rssi = self.msg.rssi
        RtStatus.sinr = self.msg.sinr
        
        let currentTimeStamp = Date()
        let item = RtStatusSeries(
            timestamp: currentTimeStamp,
            down: Double(self.msg.down) * 8.0 / 1000000,
            up: Double(self.msg.up) * 8.0 / 1000000,
            sinr: Int(self.msg.sinr.replacingOccurrences(of: "dB", with: "")) ?? 0
        )
        
        RtStatus.series.append(item)
        while RtStatus.series[0].timestamp.distance(to: currentTimeStamp) > RtStatusRetentionPeriod {
            RtStatus.series.remove(at:0)
        }
        
        StatusItem!.button!.attributedTitle = statusString()
        
        if (self.msg.success) {
            RtStatus.errorMessage = ""
        } else {
            RtStatus.errorMessage = "Connection failed"
        }
    }
    
    func statusString() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .right
        paraStyle.lineHeightMultiple = 0.7
        text.append(NSAttributedString(
            string: "↓\(RtStatus.downMbps)M\n",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 10),
                //.foregroundColor: NSColor.systemGreen,
                .baselineOffset: -6,
                .paragraphStyle: paraStyle
            ]
        ))
        text.append(NSAttributedString(
            string: "↑\(RtStatus.upMbps)M",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 10),
                //.foregroundColor: NSColor.systemBlue,
                .baselineOffset: -6,
                .paragraphStyle: paraStyle
            ]
        ))
        return text;
    }
    
    func reboot() {
        let semaphore = DispatchSemaphore(value: 0)

        let alert = NSAlert()
        alert.alertStyle = NSAlert.Style.warning
        alert.messageText = "Reboot Router"
        alert.informativeText = "Are you sure?"
        
        alert.addButton(withTitle: "Ok")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response != .alertFirstButtonReturn {
            return
        }
 
        Task {
            do {
                try await self.rts.connect(host:huaweiRtHost, userID:huaweiRtUserID, password:huaweiRtPassword)
                try await self.rts.reboot()
            } catch {
                
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
    
}

var SettingsWindow: NSWindow?
var StatusItem: NSStatusItem?

class AppDelegate: NSObject, NSApplicationDelegate {
    var popover = NSPopover.init()
    var settingsWindow: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        // Nasty hack :(
        let isInSwiftUIPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isInSwiftUIPreview {
            return
        }

        NSApp.windows.forEach{ $0.orderOut(self) }
        SettingsWindow = NSApp.windows[0]
        
        let contentView = ContentView()
            .environmentObject(RtStatus)
        popover.contentSize = NSSize(width: 300, height: 190)
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        StatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        StatusItem!.button!.action = #selector(AppDelegate.togglePopover(sender:))

        MonitorCtl.start()
    }
    
    /*
    @objc func showSettingsWindow() {
        settingsWindow.display()
    }
    */
    
    @objc func togglePopover(sender: AnyObject) {
        //debugPrint("Menu Clicked")
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let button = StatusItem!.button!
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.maxY)
        }
    }
}
