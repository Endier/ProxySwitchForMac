import Foundation

let url = URL(fileURLWithPath: "/usr/sbin/networksetup")

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
        data = try pipe.fileHandleForReading.readToEnd();
    } catch {
        print("Read File failed!")
    }
    
    if let output = String(data: data!, encoding: .utf8) {
        // 输出的结果是每行都是一个网络服务的名字，所以通过分割字符串来获取所有的网络服务
        // 另外第一行会插入一个说明：带*的服务名处于停用状态，不太清楚这个说明是否每次都会出现，这里先把第一行删除
        serviceNames = output.split(separator: "\n").map { String($0) }
        serviceNames.remove(at: 0)
    }
        
    return serviceNames
}

/// 将所有网络服务名输入，逐个获取每个开关的状态，如果有一个关了就返回false，全开才返回true
public func getProxyStatus(serviceNames: [String]) -> Bool {
    
    let arguments = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
    
    var result = true
    
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
                data = try pipe.fileHandleForReading.readToEnd();
            } catch {
                print("Read File failed!")
            }
            // 将数据序列化为uft8编码的String
            // 可选绑定，可以处理可能为空的值
            if let value = String(data: data!, encoding: .utf8) {
                if value.contains("No") {
                    result = false
                }
            } else {
                print("Output is nil")
            }
        }
    }
    
    return result
}

/// 开关代理不需要很精细，全关或全开即可
public func setProxyEnable(serviceNames: [String], bool: Bool) -> Bool {
    // 在子线程中执行命令
    // 分别是http代理、https代理、SOCKS代理
    let arguments = ["-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate"]
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
    
    print("执行成功")
    return true
}
