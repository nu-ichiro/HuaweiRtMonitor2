//
//  SettingsView.swift
//  HuaweiRtMonitor2
//
//  Created by 中橋 一朗 on 2022/12/27.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("huaweiRtHost") private var huaweiRtHost = "192.168.1.1"
    @AppStorage("huaweiRtUserID") private var huaweiRtUserID = "admin"
    @AppStorage("huaweiRtPassword") private var huaweiRtPassword = "xxxxx"

    var body: some View {
        Form {
            TextField("Host", text: $huaweiRtHost)
            TextField("User ID", text: $huaweiRtUserID)
            SecureField("Password", text: $huaweiRtPassword)
        }
        .padding(16.0)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
