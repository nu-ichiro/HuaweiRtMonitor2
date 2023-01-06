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
    var rssi: Int
    
    init(timestamp: Date, down: Double, up: Double, sinr: Int, rssi: Int) {
        self.timestamp = timestamp
        self.down = down
        self.up = up
        self.sinr = sinr
        self.rssi = rssi
    }
}

let RtStatusRetentionPeriod = 300.0 // sec
let RtStatusInterval = 5.0 //sec

@MainActor
class HuaweiRtStatus : ObservableObject {
    @Published var downMbps: String = "-1"
    @Published var upMbps: String = "-1"
    @Published var rssi: String = "-dB"
    @Published var sinr: String = "-dB"
    @Published var series: [RtStatusSeries] = []
    @Published var errorMessage = ""
    
    func append(series s: RtStatusSeries?) {
        if let s {
            downMbps = String(format:"%0.1f", s.down)
            upMbps = String(format:"%0.1f", s.up)
            rssi = String(format:"%ddBm", s.rssi)
            sinr = String(format:"%ddB", s.sinr)
                        
            series.append(s)
        }

        let currentTimeStamp = Date()
        while series[0].timestamp.distance(to: currentTimeStamp) > RtStatusRetentionPeriod {
            series.remove(at:0)
        }
        
    }
    
    func setErrorMessage(_ msg: String) {
        errorMessage = msg
    }
    
    func statusString() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = .right
        paraStyle.lineHeightMultiple = 0.7
        
        text.append(NSAttributedString(
            string: "↓\(downMbps)M\n",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 10),
                .baselineOffset: -6,
                .paragraphStyle: paraStyle
            ]
        ))
        text.append(NSAttributedString(
            string: "↑\(upMbps)M",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 10),
                .baselineOffset: -6,
                .paragraphStyle: paraStyle
            ]
        ))
        return text;
    }

}


var RtStatus: HuaweiRtStatus!
let MonitorCtl = RtMonitorController()

@main
struct HuaweiRtMonitor2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        RtStatus = HuaweiRtStatus()
    }
    
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


class RtMonitorController {
    @AppStorage("huaweiRtHost") private var huaweiRtHost = "192.168.1.1"
    @AppStorage("huaweiRtUserID") private var huaweiRtUserID = "admin"
    @AppStorage("huaweiRtPassword") private var huaweiRtPassword = "xxxxx"
    
    var statusUpdateTimer: Timer?
    let rts = HuaweiRtSession()
    //var msg = RtStatusMsg()
    var updateSuccess: Bool = false
    
    var timerCancellable: AnyCancellable?
    var connectionTask: Any?
    
    var success = false

    @MainActor
    func start() {
        let statusBarButton = StatusItem!.button!
        statusBarButton.attributedTitle = RtStatus.statusString()
        
        timerCancellable = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.updateStatus()
            }
        
        // first update
        updateStatus()
    }


    func updateStatus() {

        if connectionTask != nil {
            print("Another connection is active. Aborted.")
            
            // Remove expired data and update the view
            Task { await RtStatus.append(series: nil) }
            return
        }
        connectionTask = Task {
            defer {
                self.connectionTask = nil
            }
            
            do {
                try await self.rts.connect(host:huaweiRtHost, userID:huaweiRtUserID, password:huaweiRtPassword)
                
                let (band, rsrq, rsrp, rssi, sinr) = await self.rts.signalStatus()
                print("Signal: band=\(band) rsrq=\(rsrq) rsrp=\(rsrp) rssi=\(rssi) sinr=\(sinr)")
                                
                let (down, up) = await self.rts.trafficStatus()
                print("Traffic: down=\(down) up=\(up)")
                
                try await self.rts.close()
                
                let currentTimeStamp = Date()
                let item = RtStatusSeries(
                    timestamp: currentTimeStamp,
                    down: Double(down) * 8.0 / 1000000,
                    up: Double(up) * 8.0 / 1000000,
                    sinr: Int(sinr.replacingOccurrences(of: "dB", with: "")) ?? 0,
                    rssi: Int(rssi.replacingOccurrences(of: "dBm", with: "")) ?? 0
                )
                await RtStatus.append(series: item)
                self.success = true

            } catch {
                print("Failed to obtain router status!")
            }
            
            if (self.success) {
                await RtStatus.setErrorMessage("")
            } else {
                await RtStatus.setErrorMessage("Connection failed")
            }

            await updateStatusMenuButton()
        }
        
    }

    @MainActor
    func updateStatusMenuButton() {
        StatusItem!.button!.attributedTitle = RtStatus.statusString()
    }
    
    
    func reboot() {

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
            while connectionTask != nil {
                print("Another connection is active. Waiting.")
                sleep(1)
            }
            connectionTask = "reboot"
            defer { connectionTask = nil }
            
            do {
                try! await self.rts.connect(host:huaweiRtHost, userID:huaweiRtUserID, password:huaweiRtPassword)
                try! await self.rts.reboot()
            }
        }
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
