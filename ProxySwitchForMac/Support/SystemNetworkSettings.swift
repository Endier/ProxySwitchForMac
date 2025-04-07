import CFNetwork
import Foundation
import UserNotifications
import KeyboardShortcuts

let url = URL(fileURLWithPath: "/usr/sbin/networksetup")

@Observable
class SystemProxyStatus {
    var _totleEnable: Bool
    
    var totelEnable: Bool {
        get {
            return _totleEnable
        }

        set {
            let serviceNames = ["Wi-Fi", "Ethernet"]
            defaultToggleEnable(serviceNames: serviceNames, bool: newValue)
            _totleEnable = newValue

            // 发送通知
            sentNotifications(isOn: newValue)
        }
    }
    
    init() {
        let networkServices = getSystemNetworkServiceNames()
        var result: ProxySetting?
        var result1: ProxySetting?
        var result2: ProxySetting?
        var result3: ProxySetting?
        var result4: ProxySetting?
        var result5: ProxySetting?

        if networkServices.contains("Wi-Fi") {
            result = getProxySetting(argument: "-getwebproxy", serviceName: "Wi-Fi")
            result1 = getProxySetting(argument: "-getsecurewebproxy", serviceName: "Wi-Fi")
            result2 = getProxySetting(argument: "-getsocksfirewallproxy", serviceName: "Wi-Fi")
        }

        if networkServices.contains("Ethernet") {
            result3 = getProxySetting(argument: "-getwebproxy", serviceName: "Ethernet")
            result4 = getProxySetting(argument: "-getsecurewebproxy", serviceName: "Ethernet")
            result5 = getProxySetting(argument: "-getsocksfirewallproxy", serviceName: "Ethernet")
        }

        if result?.Enable == "No" && result1?.Enable == "No" && result2?.Enable == "No" && result3?.Enable == "No" && result4?.Enable == "No" && result5?.Enable == "No" {
            self._totleEnable = false
        } else {
            self._totleEnable = true
        }
        
        KeyboardShortcuts.onKeyDown(for: .proxySwitch) { [self] in
            totelEnable.toggle()
        }
    }
}

// 命名并设置默认快捷键
extension KeyboardShortcuts.Name {
    static let proxySwitch = Self("proxySwitch", default: .init(.j, modifiers: .command))
}

class ProxySetting {
    public var Enable: String
    public var Server: String
    public var Port: String

    init(Enable: String, Server: String, Port: String) {
        self.Enable = Enable
        self.Server = Server
        self.Port = Port
    }
}

func getSystemNetworkServiceNames() -> [String] {
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

func getProxySetting(argument: String, serviceName: String) -> ProxySetting? {
    // 先创建子线程
    let checkProcess = Process()
    checkProcess.executableURL = url
    checkProcess.arguments = [argument, serviceName]

    // Pipe就是类似于channel的东西，用于在不同的进程间传递数据
    // 这里获取开关状态的命令是在子进程执行的，需要把结果传回主进程
    let pipe = Pipe()
    checkProcess.standardOutput = pipe
    guard let _ = try? checkProcess.run() else {
        fatalError()
    }

    checkProcess.waitUntilExit()

    guard let data = try? pipe.fileHandleForReading.readToEnd() else {
        fatalError("Get system status failed!")
    }

    guard let status = String(data: data, encoding: .utf8) else {
        fatalError()
    }

    let errorMessage = "** Error: Unable to find item in network database."

    if status != errorMessage {
        let hashmap = stringToHashMap(string: status)
        let enabled = hashmap["Enabled"] ?? ""
        let server = hashmap["Server"] ?? ""
        let port = hashmap["Port"] ?? ""
        let proxySetting = ProxySetting(
            Enable: enabled,
            Server: server,
            Port: port
        )

        return proxySetting
    }

    return nil
}

func getProxySettings(serviceNames: [String]) -> [ProxySetting] {
    var proxySettingList: [ProxySetting] = []

    let arguments = [
        "-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy",
    ]

    for argument in arguments {
        for serviceName in serviceNames {
            let proxySetting = getProxySetting(argument: argument, serviceName: serviceName)
            if proxySetting != nil {
                proxySettingList.append(proxySetting!)
            }
        }
    }

    return proxySettingList
}

/// 将所有网络服务名输入，逐个获取每个开关的状态，如果有一个关了就返回false，全开才返回true
func isSwitchOn(proxySettingList: [ProxySetting]) -> Bool {
    var num = 0
    for proxySetting in proxySettingList {
        if proxySetting.Enable == "Yes" {
            num += 1
        }
    }
    if num == 0 {
        return false
    } else {
        return true
    }
 }

func toggleEnable(argument: String, serviceName: String, enable: String) {
    let process = Process()
    process.executableURL = url
    process.arguments = [argument, serviceName, enable]
    guard let _ = try? process.run() else {
        fatalError()
    }
}

/// 开关代理不需要很精细，全关或全开即可
public func defaultToggleEnable(serviceNames: [String], bool: Bool) {
    // 在子线程中执行命令
    // 分别是http代理、https代理、SOCKS代理
    let arguments = [
        "-setwebproxystate", "-setsecurewebproxystate",
        "-setsocksfirewallproxystate",
    ]
    // 最后的变量，填写网络络服务的名称，如 "Wi-Fi" 或 "Ethernet"

    let onOrOff: String = bool ? "on" : "off"

    for serviceName in serviceNames {
        for argument in arguments {
            toggleEnable(argument: argument, serviceName: serviceName, enable: onOrOff)
        }
    }
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
