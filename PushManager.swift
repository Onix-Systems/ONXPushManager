//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

import UIKit

class PushInfo {
    let userInfo : [NSObject : AnyObject]
    let receivedAtState : UIApplicationState
    
    init (userInfo: [NSObject : AnyObject], applicationState: UIApplicationState) {
        self.userInfo = userInfo
        self.receivedAtState = applicationState
    }
    
    var customObject : AnyObject?
}

class PushManager: NSObject {
    var latestToken: String?
    var pendingPush : PushInfo?
    
    class var manager : PushManager {
        struct Static {
            static let instance : PushManager = PushManager()
        }
        
        return Static.instance
    }
    
    override init() {
        super.init()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "onApplicationDidFinishLaunching:", name:
            UIApplicationDidFinishLaunchingNotification, object: nil)
    }
    
    func iOS8() -> Bool {
        switch UIDevice.currentDevice().systemVersion.compare("8.0.0", options: NSStringCompareOptions.NumericSearch) {
        case .OrderedSame, .OrderedDescending:
            return true
        case .OrderedAscending:
            return false
        }
    }
    
    //MARK: Public API
    func registerDevice() {
        if iOS8() {
            let types: UIUserNotificationType = .Badge | .Sound | .Alert;
            
            let mySettings = UIUserNotificationSettings(forTypes: types, categories: nil)
            
            UIApplication.sharedApplication().registerUserNotificationSettings(mySettings)
        } else {
            let myTypes: UIRemoteNotificationType = .Badge | .Alert | .Sound
            UIApplication.sharedApplication().registerForRemoteNotificationTypes(myTypes)
        }
    }
    
    //MARK: Handling AppDelegate actions
    func handleApplicationDidBecomeActive(app: UIApplication) {
        if let push = self.pendingPush { //Means that poll_id has been received before the app became active, and once it's active we need to do some action
            let delayTime = dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(0.5 * Double(NSEC_PER_SEC))
            )
            
            dispatch_after(delayTime, dispatch_get_main_queue(), { () -> Void in //Small quick hack, probably need replacement
                self.actFromPush(push)
            })
        }
        
        self.pendingPush = nil
    }
    
    func handleDidFailToRegisterWithError(error: NSError) {
        println("ERROR \(error)")
    }
    
    func handleDidRecieveNotification(userInfo: [NSObject : AnyObject], app: UIApplication, handler: ((UIBackgroundFetchResult) -> Void)?) {
        println("PUSH \(userInfo)")
                
        switch app.applicationState {
        case .Active:
            println("state - active")
            self.pendingPush = nil
            
            let pushInfo = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
            self.actFromPush(pushInfo)
        case .Inactive:
            println("state - inactive")
            self.pendingPush = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
        case .Background:
            println("state - background")
        default:
            println("state - default")
        }
        
        handler?(UIBackgroundFetchResult.NoData)
    }
    
    func handleDidRegisterUserNotificationSettings(settings: UIUserNotificationSettings, application: UIApplication) {
        application.registerForRemoteNotifications()
    }
    
    func handleDidRegisterWithTokenData(data: NSData) {
        let bytes = data.bytes
        println("DidRegisterWithTokenData bytes \(data.bytes)")
        let trimmedString = data.description.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "<>"))
        self.latestToken = trimmedString.stringByReplacingOccurrencesOfString(" ", withString: "", options: .allZeros, range: nil)
        println("self.latestToken \(self.latestToken)")
        
        self.updatePushesWithLatestToken()
    }
    
    func actFromPush(var pushInfo: PushInfo) {
        //Your actions upon push here, below is example
        
//        let userInfo = pushInfo.userInfo
//        if let inboxBadgeNumber = userInfo["inbox_badge"] as? Int {
//            NSNotificationCenter.defaultCenter().postNotificationName(kInboxBadgeValuePushRecievedNotification, object: nil, userInfo: [kNotificationDataKey : inboxBadgeNumber])
//        }
//        
//        if let recentActivityBadgeNumber = userInfo["activity_badge"] as? Int {
//            NSNotificationCenter.defaultCenter().postNotificationName(kRecentBadgeValuePushRecievedNotification, object: nil, userInfo: [kNotificationDataKey : recentActivityBadgeNumber])
//        }
//        
//        if let pollId = userInfo["poll_id"] as? Int {
//            let poll = Poll(id: pollId)
//            pushInfo.customObject = poll
//                        self.sendPushReceivedNotification(pushInfo, key: kViewPollActionRequestedNotification)
//        }
    }
    
    func updatePushesWithLatestToken() {
        //Method for updating your server with latest token saved. You should probably call it on token retrieve and upon login, but don't forget to check authToken and pushToken as shown in example:
        
//        if let sessionToken = ServerManager.authToken {
//            if let deviceToken = self.latestToken {
//                let request = UpdateDeviceRequest(token: deviceToken)
//                request.completionBlock  = { (responseJson, error) -> () in
//                    println("updatePushesWithLatestToken error \(error)")
//                    println("updatePushesWithLatestToken json \(responseJson)")
//                    
//                    if let uError = error {
//                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                            errorAlert(uError.localizedDescription)
//                        })
//                    }
//                }
//                
//                ServerManager.manager.runRequest(request)
//            } else {
//                dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                                    errorAlert("No token found for Push Notification registration. You won't recieve push notifications for this device. Please try to relogin.")
//                })
//            }
//        } else {
//            println("updatePushesWithLatestToken - no authToken");
//        }
    }
    
    //MARK: Notifications
    func onApplicationDidFinishLaunching(notification: NSNotification) {
        if let remoteOptions = notification.userInfo?[UIApplicationLaunchOptionsRemoteNotificationKey] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: notification.object as UIApplication, handler: nil)
        }
    }
    
    //MARK: Private API
    private func sendPushReceivedNotification(pushInfo: PushInfo, key: String) {
        let kNotificationDataKey = "ANYKEY" //Use the key you need here
        
        let pushInfo = [kNotificationDataKey : pushInfo]
        
        NSNotificationCenter.defaultCenter().postNotificationName(key, object: self, userInfo: pushInfo)
    }
}
