//
//  HuaweiAPI.swift
//  HuaweiRtMonitor2
//
//  Created by 中橋 一朗 on 2022/12/25.
//

// Based on API information obtained here: https://github.com/Salamek/huawei-lte-api

import Foundation
import CryptoKit
import SWXMLHash

private func hexString(_ iterator: Array<UInt8>.Iterator) -> String {
    return iterator.map { String(format: "%02x", $0) }.joined()
}

enum HuaweiRtSessionError : Error {
    case LoginFailed
}

class HuaweiRtSession {
    var rt_host = ""

    var session: URLSession
    var csrf_token: [String] = []

    init() {
        session = URLSession.shared
    }

    func connect(host: String, userID: String, password: String) async throws {
        var html: String?

        rt_host = "http://\(host)/"
        print("Connect: host=\(host) userID=\(userID)")
        
        let (data, _) =  try await URLSession.shared.data(from: URL(string: rt_host)!)
        html = String(data: data, encoding: .utf8)
        //debugPrint(html)

        csrf_token = []
        let regex = try! NSRegularExpression(pattern: #"name="csrf_token"\s+content="(\S+)""#)
        var diff = 0
        regex.enumerateMatches(in: html!, options: .reportCompletion, range: NSRange(location: 0, length: html!.count), using: { (result, flags, stop) in
            //debugPrint("*"); debugPrint(flags)
            if let result = result {
                if result.numberOfRanges == 2 {
                    //print("location: \(result.range(at: 1).location), length: \(result.range(at: 1).length)")
                    let start = html!.index(html!.startIndex, offsetBy: result.range(at: 1).location + diff)
                    let end = html!.index(start, offsetBy: result.range(at: 1).length)
                    let text = String(html![start..<end])
                    //debugPrint(text)
                    csrf_token.append(text)
                    diff = diff - 1
                }
            }
        })
        if csrf_token.count <= 0 {
            throw HuaweiRtSessionError.LoginFailed
        }
        //debugPrint("CSRF Token:", self.csrf_token)
        
        var concentrated: Data = userID.data(using: .utf8)!
        let pw_hash = hexString(SHA256.hash(data: password.data(using: .ascii)!).makeIterator())
        concentrated.append(pw_hash.data(using: .ascii)!.base64EncodedData())
        concentrated.append(csrf_token[0].data(using: .utf8)!)
        let hashed_pw = hexString(SHA256.hash(data:concentrated).makeIterator()).data(using: .ascii)?.base64EncodedString()
        
        let url = URL(string: "\(rt_host)api/user/login")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(csrf_token[0], forHTTPHeaderField: "__RequestVerificationToken")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        let body_str = """
    <?xml version="1.0" encoding="UTF-8"?>
    <request>
        <Username>\(userID)</Username>
        <Password>\(hashed_pw!)</Password>
        <password_type>4</password_type>
    </request>
    """
        //debugPrint(body_str)
        req.httpBody = body_str.data(using: .utf8)
        let req_ = req
        
        let (_, resp) = try await URLSession.shared.data(for: req_)
        //debugPrint(String(data: d, encoding: .utf8))
        //debugPrint(resp)
        let http_resp = resp as? HTTPURLResponse
        if let token = http_resp!.value(forHTTPHeaderField: "__RequestVerificationTokenone") {
            self.csrf_token[0] = token
            print("Successful Logon - New CSRF Token:", token)
        } else {
            print("Login failed")
            throw HuaweiRtSessionError.LoginFailed
        }
    }

    func close() async throws {
        let requestXML = """
<?xml version="1.0" encoding="utf-8"?>
<request><Logout>1</Logout></request>
"""

        var req = URLRequest(url: URL(string: "\(rt_host)api/user/logout")!)
        req.httpMethod = "POST"
        req.setValue(csrf_token[0], forHTTPHeaderField: "__RequestVerificationToken")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = requestXML.data(using: .utf8)
        
        let (_, _) = try await URLSession.shared.data(for: req)
        //debugPrint(String(data: data, encoding: .utf8))
        
        csrf_token = []
        print("Logoff")
    }

    func signalStatus() async -> (Int, String, String, String, String) {
        var band = -1, rsrq = "", rsrp = "", rssi = "", sinr = ""
        
        let req = URLRequest(url: URL(string: "\(rt_host)api/device/signal")!)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let xml = XMLHash.parse(String(data:data, encoding: .utf8)!)
            band = Int(xml["response"]["band"].element?.text ?? "") ?? -1
            rsrq = xml["response"]["rsrq"].element!.text
            rsrp = xml["response"]["rsrp"].element!.text
            rssi = xml["response"]["rssi"].element!.text
            sinr = xml["response"]["sinr"].element!.text
        } catch {
            // retain default value
        }

        return (band, rsrq, rsrp, rssi, sinr)
    }

    func connectionStatus() async -> Int {
        var connStatus: Int = -1

        let req = URLRequest(url: URL(string: "\(rt_host)api/monitoring/status")!)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let xml = XMLHash.parse(String(data:data, encoding: .utf8)!)
            connStatus = Int(xml["response"]["ConnectionStatus"].element!.text) ?? -1
        } catch {
            // retain default value
        }

        return connStatus
    }

    func trafficStatus() async -> (Int, Int) {
        var downRate = -1
        var upRate = -1
        
        let req = URLRequest(url: URL(string: "\(rt_host)api/monitoring/traffic-statistics")!)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let xml = XMLHash.parse(String(data:data, encoding: .utf8)!)
            downRate = Int(xml["response"]["CurrentDownloadRate"].element!.text) ?? -1
            upRate   = Int(xml["response"]["CurrentUploadRate"].element!.text) ?? -1
        } catch {
            // retain default value
        }

        return (downRate, upRate)
    }
    
/*
 func reboot() {
        
        let headers: HTTPHeaders = [
            "__RequestVerificationToken": csrf_token[0],
            "Content-Type": "application/xml"
        ]
        let requestXML = """
<?xml version="1.0" encoding="utf-8"?>
<request><Control>1</Control></request>
"""
        session.upload(requestXML.data(using: .utf8)!, to: rt_url + "api/device/control", headers: headers).response { response in
            //debugPrint(response)
        }

    }
     */
}
