import Foundation
import SwiftData

let url = URL(fileURLWithPath: "/usr/sbin/networksetup")

public class ProxySetting {
    public var Enabled: Bool
    public var Server: String
    public var Port: String

    init() {
        self.Enabled = false
        self.Server = "No information"
        self.Port = "No information"
    }

    init(Enable: Bool, Server: String, Port: String) {
        self.Enabled = Enable
        self.Server = Server
        self.Port = Port
    }
}

public func getSystemNetworkServiceNames() -> [String] {
    var serviceNames: [String] = []
    // 先创建子线程
    let checkProcess = Process()
    let pipe = Pipe()
    // 在子线程中执行命令
    checkProcess.executableURL = url
    checkProcess.arguments = ["-listallnetworkservices"]
    checkProcess.standardOutput = pipe

    do {
        try checkProcess.run()
    } catch {
        print("Process run error!")
    }

    checkProcess.waitUntilExit()
    var data: Data?

    do {
        data = try pipe.fileHandleForReading.readToEnd()
    } catch {
        print("Read File failed!")
    }

    if let output = String(data: data!, encoding: .utf8) {
        // 输出的结果是每行都是一个网络服务的名字，所以通过分割字符串来获取所有的网络服务
        // 另外每次执行命令，第一行会固定插入一个说明：带*的服务名处于停用状态，要先把第一行删除
        serviceNames = output.components(separatedBy: .newlines).map {
            String($0)
        }
        serviceNames.remove(at: 0)
        // 排除掉以*开头的字符串
        serviceNames.removeAll(where: {
            $0.hasPrefix("*") || $0.trimmingCharacters(in: .whitespaces).isEmpty
        })
        // 另一种写法
        //        serviceNames = serviceNames.filter { !$0.hasPrefix("*") || $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    #if DEBUG
        print(serviceNames)
    #endif

    return serviceNames
}

public func getProxySettings(serviceNames: [String]) -> [ProxySetting] {
    var proxySettingList: [ProxySetting] = []

    let arguments = [
        "-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy",
    ]

    for argument in arguments {
        for serviceName in serviceNames {
            // 先创建子线程
            let checkProcess = Process()
            // 在子线程中执行命令
            checkProcess.executableURL = url
            // 命令有两个参数
            // 第一个参数有三种，分别对应的是获取http代理、https代理、SOCKS代理的状态
            // 第二个参数是网络服务的名称,如 "Wi-Fi" 或 "Ethernet"
            checkProcess.arguments = [argument, serviceName]
            // Pipe就是类似于channel的东西，用于在不同的进程间传递数据
            // 这里获取开关状态的命令是在子进程执行的，需要把结果传回主进程
            let pipe = Pipe()
            checkProcess.standardOutput = pipe

            do {
                try checkProcess.run()
            } catch {
                print("Process run error!")
            }

            checkProcess.waitUntilExit()

            var data: Data?

            do {
                data = try pipe.fileHandleForReading.readToEnd()
                let jsonString = String(data: data!, encoding: .utf8)
                if jsonString
                    != "** Error: Unable to find item in network database."
                {
                    let hashmap = stringToHashMap(string: jsonString!)
                    let enabled = hashmap["Enabled"] == "Yes" ? true : false
                    let server = hashmap["Server"] ?? ""
                    let port = hashmap["Port"] ?? ""
                    let proxySetting = ProxySetting(
                        Enable: enabled,
                        Server: server,
                        Port: port
                    )

                    proxySettingList.append(proxySetting)
                }
            } catch {
                print(error)
                print("Read file failed or Decode data filed!")
            }
            
            
        }
    }

    return proxySettingList
}

/// 将所有网络服务名输入，逐个获取每个开关的状态，如果有一个关了就返回false，全开才返回true
func isProxyOn(proxySettingList: [ProxySetting]) -> Bool {
    var isProxyOn = false
    for proxySetting in proxySettingList {
        isProxyOn = proxySetting.Enabled
    }
    return isProxyOn
}

/// 开关代理不需要很精细，全关或全开即可
public func setProxyEnable(serviceNames: [String], bool: Bool) -> Bool {
    // 在子线程中执行命令
    // 分别是http代理、https代理、SOCKS代理
    let arguments = [
        "-setwebproxystate", "-setsecurewebproxystate",
        "-setsocksfirewallproxystate",
    ]
    //最后的变量，填写网络络服务的名称，如 "Wi-Fi" 或 "Ethernet"
    // TODO 网络服务的名字会变化的，需要使用方法获取

    let onOrOff: String = bool ? "on" : "off"

    for serviceName in serviceNames {
        for argument in arguments {
            // 先创建子线程
            let process = Process()
            process.executableURL = url
            process.arguments = [argument, serviceName, onOrOff]
            do {
                try process.run()
            } catch {
                print("Process run error!")
                return false
            }
        }
    }

    return true
}

func stringToHashMap(string: String) -> [String: String] {
    var hashMap: [String: String] = [:]

    // Swift 这个字符串分割挺好用的
    let lines = string.components(separatedBy: .newlines)

    for line in lines {
        let KV = line.components(separatedBy: ": ")
        if KV.count == 2 {
            hashMap[KV[0]] = KV[1]
        }
    }

    return hashMap
}
