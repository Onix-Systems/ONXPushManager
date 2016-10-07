//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

import UserNotifications

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
    func pushManager(manager: ONXPushManager, didGetNotificationsRegisterError error: Error)
    
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
            if #available(iOS 10.0, *) {
                self.registerPushes(app, completion: nil)
            } else {
                self.registerPushes(app)
            }
        }
        
        if let remoteOptions = launchOptions?[UIApplicationLaunchOptionsKey.remoteNotification] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: app, handler: nil)
        }
    }
    
    @available(iOS, obsoleted: 10.0)
    func registerPushes(_ app: UIApplication) {
        let types: UIUserNotificationType = [.badge, .sound, .alert]
        let mySettings = UIUserNotificationSettings(types: types, categories: nil)
        app.registerUserNotificationSettings(mySettings)
        self.pushesPrompted = true
    }
    
    @available(iOS 10.0, *)
    func registerPushes(_ app: UIApplication, completion: ((_ granted: Bool) -> ())?) {
        let types: UIUserNotificationType = [.badge, .sound, .alert]
        let mySettings = UIUserNotificationSettings(types: types, categories: nil)
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.badge, .sound, .alert], completionHandler: { (granted, error) in
            self.denied = !granted
            
            if let uError = error {
                self.delegate?.pushManager(manager: self, didGetNotificationsRegisterError: uError)
            } else {
                app.registerUserNotificationSettings(mySettings)
            }
            
            if let c = completion {
                c(granted)
            }
        })
        
        self.pushesPrompted = true
    }
    
    func registered() -> Bool {
        return pushNotificationsRegistrationStatus() == .registered
    }
    
    func pushNotificationsRegistrationStatus() -> ONXPushNotificationsRegistrationStatus {
        if UIApplication.shared.isRegisteredForRemoteNotifications {
            return .registered
        } else {
            if #available(iOS 10.0, *) {
                if denied {
                    return .denied
                }
            } else if pushesPrompted {
                return .denied
            }
        }
        
        return .notDetermined
    }
    
    fileprivate let ONXPushNotificationsDeniedKey = "ONXPushNotificationsDeniedKey"
    @available(iOS 10.0, *)
    fileprivate var denied : Bool {
        get {
            return UserDefaults.standard.object(forKey: ONXPushNotificationsDeniedKey) != nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ONXPushNotificationsDeniedKey)
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
        
        var token: String = ""
        for i in 0..<data.count {
            token += String(format: "%02.2hhx", data[i] as CVarArg)
        }
        
        self.latestToken = token
        
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

@available(iOS 10.0, *)
extension ONXPushManager : UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("userNotificationCenter willPresent \(notification)")
        completionHandler(.alert)
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        self.handleDidRecieveNotification(response.notification.request.content.userInfo, app: UIApplication.shared, handler: nil)
    }
}
