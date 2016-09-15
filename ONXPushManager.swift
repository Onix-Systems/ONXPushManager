//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

class PushInfo : NSObject {
    let userInfo : [AnyHashable: Any]
    let receivedAtState : UIApplicationState
    
    init (userInfo: [AnyHashable: Any], applicationState: UIApplicationState) {
        self.userInfo = userInfo
        self.receivedAtState = applicationState
    }
    
    var customObject : AnyObject?
}

@objc protocol ONXPushManagerDelegate : NSObjectProtocol {
    func savedPushTokenForPushManager(_ manager: ONXPushManager) -> String?
    func pushTokenShouldBeSentToBackend(_ token: String, manager: ONXPushManager)
    func pushToken(_ token: String, shouldBeUpdatedOnBackendWith newToken: String, manager: ONXPushManager)
    func pushTokenForStoringNotFoundInManager(_ manager: ONXPushManager)
    func pushDelegateShouldActOnPush(_ pushInfo: PushInfo, manager: ONXPushManager)
    
    @objc optional
    func pushManagerDidHandleApplicationActivation(_ manager: ONXPushManager)
}

enum ONXPushNotificationsRegistrationStatus {
    case notDetermined
    case registered
    case denied
}

class ONXPushManager: NSObject {
    weak var delegate: ONXPushManagerDelegate?
    internal var latestToken: String?
    fileprivate var pendingPush : PushInfo?
    
    //MARK: Public API
    func start(_ app: UIApplication, launchOptions: [AnyHashable: Any]?, registerNow: Bool) {
        if (registerNow) {
            self.registerPushes(app)
        }
        
        if let remoteOptions = launchOptions?[UIApplicationLaunchOptionsKey.remoteNotification] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: app, handler: nil)
        }
    }
    
    func registerPushes(_ app: UIApplication) {
        let types: UIUserNotificationType = [.badge, .sound, .alert]
        let mySettings = UIUserNotificationSettings(types: types, categories: nil)
        
        app.registerUserNotificationSettings(mySettings)
        self.pushesPrompted = true
    }
    
    func registered() -> Bool {
        return pushNotificationsRegistrationStatus() == .registered
    }
    
    func pushNotificationsRegistrationStatus() -> ONXPushNotificationsRegistrationStatus {
        if UIApplication.shared.isRegisteredForRemoteNotifications {
            return .registered
        } else if pushesPrompted {
            return .denied
        } else {
            return .notDetermined
        }
    }
    
    fileprivate let ONXPushNotificationsPromptedKey = "ONXPushNotificationsPromptedKey"
    fileprivate var pushesPrompted : Bool {
        get {
            return UserDefaults.standard.object(forKey: ONXPushNotificationsPromptedKey) != nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ONXPushNotificationsPromptedKey)
        }
    }
    
    //MARK: Handling AppDelegate actions
    func handleApplicationDidBecomeActive(_ app: UIApplication) {
        if let push = self.pendingPush { //Means that push has been received before the app became active, and once it's active we need to do some action
            self.actFromPush(push)
        }
        
        self.pendingPush = nil
    }
    
    func handleDidFailToRegisterWithError(_ error: Error) {
        print("ERROR \(error)")
    }
    
    func handleDidRecieveNotification(_ userInfo: [AnyHashable: Any], app: UIApplication, handler: ((UIBackgroundFetchResult) -> Void)?) {
        print("PUSH \(userInfo)")
        
        switch app.applicationState {
        case .active:
            print("state - active")
            self.pendingPush = nil
            
            let pushInfo = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
            self.actFromPush(pushInfo)
        case .inactive:
            print("state - inactive")
            self.pendingPush = PushInfo(userInfo: userInfo, applicationState: app.applicationState)
        case .background:
            print("state - background")
        }
        
        handler?(UIBackgroundFetchResult.noData)
    }
    
    func handleDidRegisterWithTokenData(_ data: Data) {
        print("DidRegisterWithTokenData bytes \((data as NSData).bytes)")
        let trimmedString = data.description.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        self.latestToken = trimmedString.replacingOccurrences(of: " ", with: "", options: [], range: nil)
        
        //DO NOT DELETE, useful for release debug
//        if let token = self.latestToken {
//            let pasteboard = UIPasteboard.generalPasteboard()
//            pasteboard.string = token
//        }
        
        print(" handleDidRegisterWithTokenDataself.latestToken \(self.latestToken)")
        
        self.updatePushesWithLatestToken()
    }
    
    fileprivate func actFromPush(_ pushInfo: PushInfo) {
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
    
    fileprivate func savedPushToken() -> String? {
        return self.delegate?.savedPushTokenForPushManager(self)
    }
    
    @available(iOS 8.0, *)
    func handleDidRegisterUserNotificationSettings(_ settings: UIUserNotificationSettings, application: UIApplication) {
        application.registerForRemoteNotifications()
    }
}
