//
//  AHService.swift
//  Pods
//
//  Created by Andy Tong on 7/18/17.
//
//

import Foundation

public typealias AHServiceCompletion = (_ finished: Bool,_ userInfo: [String: Any]?) -> Void
public typealias AHServiceWorker = (_ userInfo: [String: Any], _ completion: AHServiceCompletion?) -> [String: Any]?
public typealias AHServiceVCWorker = (_ userInfo: [String: Any]) -> UIViewController?


public enum AHServiceNavigationType{
    /// Present a server side provided VC
    case present(currentVC: UIViewController)
    /// Present a server side provided VC with a navVC embedded
    case presentWithNavVC(currentVC: UIViewController)
    /// Push a server side provided VC by the closest navVC to the rootVC
    case push(navVC: UINavigationController)
}





private struct AHServer: CustomStringConvertible, Equatable {
    var service: String
    private var tasks = [String : AHTask]()
    
    init(service: String) {
        self.service = service
    }
    
    mutating func add(task: AHTask) {
        tasks[task.taskName] = task
    }
    func getTask(taskName: String) -> AHTask? {
        if let task = tasks[taskName] {
            return task
        }
        return nil
    }
    func taskExists(taskName: String) -> Bool {
        if let _ = tasks[taskName] {
            return true
        }
        return false
    }
    mutating func remove(taskName: String) {
        tasks.removeValue(forKey: taskName)
    }
    
    var description: String {
        let tasksString = tasks.flatMap({$0.key}).joined(separator: ",")
        return "service:\(service) tasks:{\(tasksString)}"
    }
    
    public static func ==(lhs: AHServer, rhs: AHServer) -> Bool {
        return lhs.service == rhs.service && lhs.tasks == rhs.tasks
    }
}

private enum AHServiceWorkerType {
    /// For non VC related, data processing
    case service(AHServiceWorker)
    
    /// For navigating VCs
    case navigateVC(AHServiceVCWorker)
}

private struct AHTask: CustomStringConvertible, Equatable {
    var taskName: String
    var workerType: AHServiceWorkerType
    var description: String {
        return "\(taskName)"
    }
    
    public static func ==(lhs: AHTask, rhs: AHTask) -> Bool {
        return lhs.taskName == rhs.taskName
    }
}

public final class AHServiceRouter {
    // ['serviceName': AHServer]
    fileprivate static var services = [String : AHServer]()
    
    /// Use this method to provide services/tasks, it does NOT help you navigate VCs.
    /// AHServiceRouter does not keep the provided object or does any modification.
    /// - Parameters:
    ///   - service: The service name. This should be unique globally.
    ///   - taskName: The name of the task. This should be unique under the service.
    ///   - worker: A closure callback that provides more info for the provider to process later when the service is being used.
    public static func registerTask(_ service: String, taskName: String, worker: @escaping AHServiceWorker) {
        
        let task = AHTask(taskName: taskName, workerType: AHServiceWorkerType.service(worker))
        register(service: service, task: task)
    }
    

    /// Use this method to provide services/tasks for navigating VCs.
    /// - Parameters:
    ///   - service: The service name. This should be unique globally.
    ///   - taskName: The name of the task. This should be unique under the service.
    ///   - worker: A closure callback that notify the provider later to give a VC to present or push.
    public static func registerVC(_ service: String, taskName: String, worker: @escaping AHServiceVCWorker) {
        
        let task = AHTask(taskName: taskName, workerType: AHServiceWorkerType.navigateVC(worker))
        register(service: service, task: task)
        
        
    }
    
    private static func register(service: String, task: AHTask) {
        if var server = services[service]{
            // check duplicate
            if server.taskExists(taskName: task.taskName) {
                assert(false,"\(service).\(task.taskName) is already register.")
                return
            }
            server.add(task: task)
            services[service] = server
        }else{
            var server = AHServer(service: service)
            server.add(task: task)
            services[service] = server
        }
    }
    
    @discardableResult
    public static func doTask(_ service: String, taskName: String, userInfo: [String: Any], completion: AHServiceCompletion?) -> [String: Any]? {

        guard let server = services[service] else {
            assert(false,"AHService: service:\(service) not registered")
            return nil
        }
        
        guard let task = server.getTask(taskName: taskName) else {
            assert(false,"AHService: \(service).\(taskName) not found")
            return nil
        }
        
        guard case let AHServiceWorkerType.service(worker) = task.workerType else {
            assert(false,"worker type doesn't matched!!")
            return nil
        }
        
        return worker(userInfo, completion)
        
    }
    
    public static func navigateVC(_ service: String, taskName: String, userInfo: [String: Any], type: AHServiceNavigationType, completion: AHServiceCompletion?) {
        
        guard let server = services[service] else {
            assert(false, "AHService: service:\(service) not registered")
            return
        }
        
        guard let task = server.getTask(taskName: taskName) else {
            assert(false,"AHService: \(service).\(taskName) not found")
            return
        }
        
        guard case let AHServiceWorkerType.navigateVC(worker) = task.workerType else {
            assert(false, "worker type doesn't matched!!")
            return
        }
        
        
        if let vc = worker(userInfo) {
            switch type {
                case let .present(currentVC):
                    currentVC.present(vc, animated: true, completion: nil)
                case let .presentWithNavVC(currentVC):
                    let navVC = UINavigationController(rootViewController: vc)
                    currentVC.present(navVC, animated: true, completion: nil)
                case let .push(navVC):
                    navVC.pushViewController(vc, animated: true)
            }
            completion?(true, nil)
        }else{
            completion?(false, nil)
        }
        
        
    }
    
    public static func allServices() -> [String] {
        let servers = services.values
        return servers.flatMap({$0.description})
        
    }
    
    public static func remove(service: String) {
        services.removeValue(forKey: service)
    }
}
