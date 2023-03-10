//
//  ContentView.swift
//  HuaweiRtMonitor2
//
//  Created by 中橋 一朗 on 2022/12/25.
//

import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var rtStatus: HuaweiRtStatus
    
    var body: some View {
        VStack(alignment: .leading) {
            Chart(self.rtStatus.series) {
                LineMark(
                    x: .value("Time", $0.timestamp),
                    y: .value("Down MBps", $0.down),
                    series: .value("down", "D")
                )
                .foregroundStyle(Color(red: 0.0, green: 0.5, blue: 0.0))
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Time", $0.timestamp),
                    y: .value("Up MBps", $0.up),
                    series: .value("up", "U")
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
            }
            .chartXScale(domain: Date().addingTimeInterval(-1.0 * RtStatusRetentionPeriod)...Date())
            HStack {
                Text("Down \(self.rtStatus.downMbps) Mbps")
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.0, green: 0.5, blue: 0.0))
                Text("Up \(self.rtStatus.upMbps) Mbps")
                    .fontWeight(.bold)
                    .foregroundColor(Color.blue)
            }
            Chart(self.rtStatus.series) {
                LineMark(
                    x: .value("Time", $0.timestamp),
                    y: .value("SINR", $0.sinr),
                    series: .value("sinr", "s")
                )
                .foregroundStyle(Color("ChartLine"))
                .interpolationMethod(.monotone)
            }
            .frame(height: 25.0)
            .chartXAxis {
                AxisMarks {
                    AxisGridLine()
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-1.0 * RtStatusRetentionPeriod)...Date())
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    HStack(alignment: .bottom) {
                        Text("SINR \(self.rtStatus.sinr)")
                            .fontWeight(.bold)
                        Text("(RSSI \(self.rtStatus.rssi))")
                            .font(.callout)
                    }
                    Text(self.rtStatus.errorMessage)
                        .foregroundColor(Color.red)
                }
                Spacer()
                Menu {
                    Button("Reboot...", action: {
                        MonitorCtl.reboot()
                    } )
                    Button("Settings...", action: {
                        NSApp.activate(ignoringOtherApps: true)
                        SettingsWindow?.makeKeyAndOrderFront(self)
                    } )
                    Button("Quit", action: {NSApplication.shared.terminate(nil)} )
                } label: {
                    Image(systemName: "gearshape")
                }.frame(width:45, alignment: .leading)
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static let rtStatus = HuaweiRtStatus()
    static var previews: some View {
        ContentView()
            .environmentObject(rtStatus)
            .frame(width: 300, height: 180)
    }
}
