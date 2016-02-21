//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

import KeychainAccess

class PushInfo : NSObject {
    let userInfo : [NSObject : AnyObject]
    let receivedAtState : UIApplicationState
    
    init (userInfo: [NSObject : AnyObject], applicationState: UIApplicationState) {
        self.userInfo = userInfo
        self.receivedAtState = applicationState
    }
    
    var customObject : AnyObject?
}

class ONXPushManager: NSObject {
    internal let keychain = Keychain(service: NSBundle.mainBundle().bundleIdentifier!)
    internal let kKeychainPushToken = "kKeychainPushToken"
    internal var latestToken: String?
    private var pendingPush : PushInfo?
    var delay = 0.5

    //This should be implemented in subclass
//    class var manager : ONXPushManager {
//        struct Static {
//            static let instance : ONXPushManager = ONXPushManager()
//        }
//        
//        return Static.instance
//    }
    
    private func iOS8() -> Bool {
        switch UIDevice.currentDevice().systemVersion.compare("8.0.0", options: NSStringCompareOptions.NumericSearch) {
        case .OrderedSame, .OrderedDescending:
            return true
        case .OrderedAscending:
            return false
        }
    }
    
    //MARK: Public API
    func start(app: UIApplication, launchOptions: [String : AnyObject]?) {
        if #available(iOS 8.0, *) {
            let types: UIUserNotificationType = [.Badge, .Sound, .Alert]
            let mySettings = UIUserNotificationSettings(forTypes: types, categories: nil)
            
            app.registerUserNotificationSettings(mySettings)
        } else {
            let myTypes: UIRemoteNotificationType = [.Badge, .Alert, .Sound]
            app.registerForRemoteNotificationTypes(myTypes)
        }
        
        if let remoteOptions = launchOptions?[UIApplicationLaunchOptionsRemoteNotificationKey] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: app, handler: nil)
        }
    }
    
    //MARK: Handling AppDelegate actions
    func handleApplicationDidBecomeActive(app: UIApplication) {
        if let push = self.pendingPush { //Means that poll_id has been received before the app became active, and once it's active we need to do some action
            let delayTime = dispatch_time(
                DISPATCH_TIME_NOW,
                Int64(self.delay * Double(NSEC_PER_SEC))
            )
            
            dispatch_after(delayTime, dispatch_get_main_queue(), { () -> Void in //Small quick hack, probably need replacement
                self.actFromPush(push)
            })
        }
        
        self.pendingPush = nil
    }
    
    func handleDidFailToRegisterWithError(error: NSError) {
        print("ERROR \(error)")
    }
    
    func handleDidRecieveNotification(userInfo: [NSObject : AnyObject], app: UIApplication, handler: ((UIBackgroundFetchResult) -> Void)?) {
        print("PUSH \(userInfo)")
                
        switch app.applicationState {
        case .Active:
            print("state - active")
            self.pendingPush = nil
            
            let pushInfo = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
            self.actFromPush(pushInfo)
        case .Inactive:
            print("state - inactive")
            self.pendingPush = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
        case .Background:
            print("state - background")
        }
        
        handler?(UIBackgroundFetchResult.NoData)
    }
    
    func handleDidRegisterWithTokenData(data: NSData) {
        print("DidRegisterWithTokenData bytes \(data.bytes)")
        let trimmedString = data.description.stringByTrimmingCharactersInSet(NSCharacterSet(charactersInString: "<>"))
        self.latestToken = trimmedString.stringByReplacingOccurrencesOfString(" ", withString: "", options: [], range: nil)
//        UIAlertView(title: "Token", message: self.latestToken ?: "No token", delegate: nil, cancelButtonTitle: nil).show()
        
        print(" handleDidRegisterWithTokenDataself.latestToken \(self.latestToken)")
        
        self.updatePushesWithLatestToken()
    }
    
    func actFromPush(pushInfo: PushInfo) {
        fatalError("actFromPush should be overridden")
        
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
        fatalError("updatePushesWithLatestToken should be overridden")
        
        //Method for updating your server with latest token saved.
        //You should probably call it on token retrieve and upon login, but don't forget to check authToken and pushToken as shown in example (Should call savePushToken at some point.)
        
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
    
    func savedPushToken() -> String? {
        return self.keychain[kKeychainPushToken]
    }
    
    func savePushToken(token: String?) {
        self.keychain[kKeychainPushToken] = token
    }
    
    func deleteTokenFromBackend() {
        fatalError("delete should be overridden")
    }
        
    @available(iOS 8.0, *)
    func handleDidRegisterUserNotificationSettings(settings: UIUserNotificationSettings, application: UIApplication) {
        application.registerForRemoteNotifications()
    }
}
