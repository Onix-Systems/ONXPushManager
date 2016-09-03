//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

class PushInfo : NSObject {
    let userInfo : [NSObject : AnyObject]
    let receivedAtState : UIApplicationState
    
    init (userInfo: [NSObject : AnyObject], applicationState: UIApplicationState) {
        self.userInfo = userInfo
        self.receivedAtState = applicationState
    }
    
    var customObject : AnyObject?
}

@objc protocol ONXPushManagerDelegate : NSObjectProtocol {
    func savedPushTokenForPushManager(manager: ONXPushManager) -> String?
    func pushTokenShouldBeSentToBackend(token: String, manager: ONXPushManager)
    func pushToken(token: String, shouldBeUpdatedOnBackendWith newToken: String, manager: ONXPushManager)
    func pushTokenForStoringNotFoundInManager(manager: ONXPushManager)
    func pushDelegateShouldActOnPush(pushInfo: PushInfo, manager: ONXPushManager)
    
    optional
    func pushManagerDidHandleApplicationActivation(manager: ONXPushManager)
}

enum ONXPushNotificationsRegistrationStatus {
    case NotDetermined
    case Registered
    case Denied
}

class ONXPushManager: NSObject {
    weak var delegate: ONXPushManagerDelegate?
    internal var latestToken: String?
    private var pendingPush : PushInfo?
    
    //MARK: Public API
    func start(app: UIApplication, launchOptions: [NSObject : AnyObject]?, registerNow: Bool) {
        if (registerNow) {
            self.registerPushes(app)
        }
        
        if let remoteOptions = launchOptions?[UIApplicationLaunchOptionsRemoteNotificationKey] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: app, handler: nil)
        }
    }
    
    func registerPushes(app: UIApplication) {
        let types: UIUserNotificationType = [.Badge, .Sound, .Alert]
        let mySettings = UIUserNotificationSettings(forTypes: types, categories: nil)
        
        app.registerUserNotificationSettings(mySettings)
        self.pushesPrompted = true
    }
    
    func registered() -> Bool {
        return pushNotificationsRegistrationStatus() == .Registered
    }
    
    func pushNotificationsRegistrationStatus() -> ONXPushNotificationsRegistrationStatus {
        if UIApplication.sharedApplication().isRegisteredForRemoteNotifications() {
            return .Registered
        } else if pushesPrompted {
            return .Denied
        } else {
            return .NotDetermined
        }
    }
    
    private let ONXPushNotificationsPromptedKey = "ONXPushNotificationsPromptedKey"
    private var pushesPrompted : Bool {
        get {
            return NSUserDefaults.standardUserDefaults().objectForKey(ONXPushNotificationsPromptedKey) != nil
        }
        set {
            NSUserDefaults.standardUserDefaults().setBool(newValue, forKey: ONXPushNotificationsPromptedKey)
        }
    }
    
    //MARK: Handling AppDelegate actions
    func handleApplicationDidBecomeActive(app: UIApplication) {
        if let push = self.pendingPush { //Means that push has been received before the app became active, and once it's active we need to do some action
            self.actFromPush(push)
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
        
        //DO NOT DELETE, useful for release debug
//        if let token = self.latestToken {
//            let pasteboard = UIPasteboard.generalPasteboard()
//            pasteboard.string = token
//        }
        
        print(" handleDidRegisterWithTokenDataself.latestToken \(self.latestToken)")
        
        self.updatePushesWithLatestToken()
    }
    
    private func actFromPush(pushInfo: PushInfo) {
        self.delegate?.pushDelegateShouldActOnPush(pushInfo, manager: self)
        
        //Your actions upon push here, below is example
    }
    
    func updatePushesWithLatestToken() {
        //Method for updating your server with latest token saved.
        //You should probably call it on token retrieve and upon login, but don't forget to check authToken and pushToken as shown in example (Should call savePushToken at some point.)
        if let deviceToken = self.latestToken {
            if let savedToken = self.savedPushToken() {
                if savedToken != deviceToken {
                    //UPDATE REQUEST
                    self.delegate?.pushToken(savedToken, shouldBeUpdatedOnBackendWith: deviceToken, manager: self)
                } else {
                    print("updatePushesWithLatestToken - not updating - same token")
                }
            } else {
                //POST REQUEST
                self.delegate?.pushTokenShouldBeSentToBackend(deviceToken, manager: self)
            }
        }
        else {
            self.delegate?.pushTokenForStoringNotFoundInManager(self)
        }
    }
    
    private func savedPushToken() -> String? {
        return self.delegate?.savedPushTokenForPushManager(self)
    }
    
    @available(iOS 8.0, *)
    func handleDidRegisterUserNotificationSettings(settings: UIUserNotificationSettings, application: UIApplication) {
        application.registerForRemoteNotifications()
    }
}
