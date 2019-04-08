//
//  PushManager.swift
//  Swayy
//
//  Created by Oleksii Nezhyborets on 1/12/15.
//  Copyright (c) 2015 Onix. All rights reserved.
//

import UserNotifications
import UIKit

class PushInfo : NSObject {
    let userInfo : [AnyHashable: Any]
    let receivedAtState : UIApplication.State
    
    init (userInfo: [AnyHashable: Any], applicationState: UIApplication.State) {
        self.userInfo = userInfo
        self.receivedAtState = applicationState
    }
    
    var customObject : AnyObject?
}

@objc protocol ONXPushManagerDelegate : NSObjectProtocol {
    func savedPushTokenForPushManager(_ manager: ONXPushManager) -> String?
    func pushTokenShouldBeSentToBackend(_ token: String, manager: ONXPushManager)
    func pushToken(savedToken token: String, shouldBeUpdatedOnBackendWith newToken: String, manager: ONXPushManager)
    func updateRequested(withSameToken token: String, in manager: ONXPushManager)
    func pushTokenForStoringNotFoundInManager(_ manager: ONXPushManager)
    func pushDelegateShouldActOnPush(_ pushInfo: PushInfo, manager: ONXPushManager)
    func pushManager(manager: ONXPushManager, didGetNotificationsRegisterError error: Error)
    func didSetNewLatest(token: String, in manager: ONXPushManager)
    func pushManagerDidHandleApplicationActivation(_ manager: ONXPushManager)
    
    @available(iOS 10.0, *)
    func willPresent(pushNotification: PushInfo, in manager: ONXPushManager)
}

enum ONXPushNotificationsRegistrationStatus : String {
    case notDetermined
    case registered
    case denied

    @available(iOS 10.0, *)
    static func fromAuthorizationStatus(_ authorizationStatus: UNAuthorizationStatus) -> ONXPushNotificationsRegistrationStatus {
        switch authorizationStatus {
        case .authorized:
            return .registered
        case .denied, .provisional:
            return .denied
        case .notDetermined:
            return .notDetermined
        }
    }
}

@objc class ONXPushManager: NSObject {
    private typealias Class = ONXPushManager
    weak var delegate: ONXPushManagerDelegate?
    var shouldShowSystemInAppAlert : Bool = true
    private var latestToken: String?
    fileprivate var pendingPush : PushInfo?
    
    fileprivate let ONXPushNotificationsDeniedKey = "ONXPushNotificationsDeniedKey"
    fileprivate let ONXPushNotificationsPromptedKey = "ONXPushNotificationsPromptedKey"
    
    fileprivate var pushesPrompted : Bool {
        get {
            return UserDefaults.standard.object(forKey: ONXPushNotificationsPromptedKey) != nil
        }
        set {
            UserDefaults.standard.set(newValue, forKey: ONXPushNotificationsPromptedKey)
        }
    }
    
    //MARK: Public API
    /**
     This method should be called from applicationDidFinishLaunching because of Apple Doc Note:
     "You must assign your delegate object to the UNUserNotificationCenter object no later before your app finishes launching. For example, in an iOS app, you must assign it in the application(_:willFinishLaunchingWithOptions:) or application(_:didFinishLaunchingWithOptions:) method."
     
     @param registerNow If true - will call application.registerUserNotificationSettings(settings:) on iOS <= 9 or userNotificationCenter.requestAuthorization(options:completionHandler:) on iOS >= 10
     
     */
    func start(_ app: UIApplication, launchOptions: [AnyHashable: Any]?, registerNow: Bool) {
        if #available(iOS 10.0, *) {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
        } else {
            // Fallback on earlier versions
        }
        
        if (registerNow) {
            self.registerPushes(app, completion: nil)
        }
        
        if let remoteOptions = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [String : AnyObject] {
            self.handleDidRecieveNotification(remoteOptions, app: app, handler: nil)
        }
    }
    
    func startAndRegisterIfAlreadyRegistered(_ app: UIApplication, launchOptions: [AnyHashable: Any]?) {
        getPushNotificationsRegistrationStatus { [weak self] (status) in
            print("push registration status \(status)")
            let registered = status == .registered
            self?.start(app, launchOptions: launchOptions, registerNow: registered)
        }
    }
    
    @available(iOS 10.0, *)
    func registerPushes(_ app: UIApplication, completion: ((_ status: Bool) -> Void)?) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: Class.unAuthorizationOptions, completionHandler: { (granted, error) in
            DispatchQueue.main.async {
                if let uError = error {
                    self.delegate?.pushManager(manager: self, didGetNotificationsRegisterError: uError)
                } else if granted {
                    app.registerForRemoteNotifications()
                }

                if let c = completion {
                    c(granted)
                }
            }
        })

        // If you do not request and receive authorization for your app's interactions, the system delivers all remote notifications to your app silently.
        // Currently we do it only if authorization granted and it's not customizable
        // app.registerForRemoteNotifications()
        
        self.pushesPrompted = true
    }

    @available(iOS 10.0, *)
    private static let unAuthorizationOptions: UNAuthorizationOptions = [.badge, .sound, .alert]
    
    func getIsRegistered(completion: @escaping (Bool) -> Void) {
        getPushNotificationsRegistrationStatus { (status) in
            completion(status == .registered)
        }
    }
    
    func getPushNotificationsRegistrationStatus(completion: @escaping (ONXPushNotificationsRegistrationStatus) -> Void) {
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) in
                completion(.fromAuthorizationStatus(settings.authorizationStatus))
            }
        } else {
            // iOS 9
            if UIApplication.shared.isRegisteredForRemoteNotifications {
                completion(.registered)
            } else if pushesPrompted {
                completion(.denied)
            } else {
                completion(.notDetermined)
            }
        }
    }
    
    //MARK: Handling AppDelegate actions
    func handleApplicationDidBecomeActive(_ app: UIApplication) {
        if let push = self.pendingPush { //Means that push has been received before the app became active, and once it's active we need to do some action
            self.actFromPush(push)
        }
        
        self.pendingPush = nil
        self.delegate?.pushManagerDidHandleApplicationActivation(self)
    }
    
    func handleDidFailToRegisterWithError(_ error: Error) {
        print("ERROR \(error)")
    }
    
    func handleDidRecieveNotification(_ userInfo: [AnyHashable: Any], app: UIApplication, handler: ((UIBackgroundFetchResult) -> Void)?) {
        #if DEBUG
        print("PUSH \(userInfo)")
        #endif
        
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
    
    func handleDidRegisterWithTokenData(_ data: Data) -> String {
        #if DEBUG
        print("DidRegisterWithTokenData bytes \((data as NSData).bytes)")
        #endif
        
        var token: String = ""
        for i in 0..<data.count {
            token += String(format: "%02.2hhx", data[i] as CVarArg)
        }
        
        self.latestToken = token
        delegate?.didSetNewLatest(token: token, in: self)
        
        // You can copy this to AppDelegate for production debugging
//        if let token = self.latestToken {
//            let pasteboard = UIPasteboard.generalPasteboard()
//            pasteboard.string = token
//        }

        #if DEBUG
        print("handleDidRegisterWithTokenDataself.latestToken \(String(describing: self.latestToken))")
        #endif
        
        self.updatePushesWithLatestToken()
        return token
    }
    
    fileprivate func actFromPush(_ pushInfo: PushInfo) {
        self.delegate?.pushDelegateShouldActOnPush(pushInfo, manager: self)
    }
    
    func updatePushesWithLatestToken() {
        //Method for updating your server with latest token saved.
        //You should probably call it on token retrieve and upon login, but don't forget to check authToken and pushToken as shown in example (Should call savePushToken at some point.)
        if let deviceToken = self.latestToken {
            if let savedToken = self.savedPushToken() {
                if savedToken != deviceToken {
                    //Update request should be sent from delegate
                    self.delegate?.pushToken(savedToken: savedToken, shouldBeUpdatedOnBackendWith: deviceToken, manager: self)
                } else {
                    //Depends on backend probably, but in our application it's Post request, because our backend checks if there is already this token in database.
                    self.delegate?.updateRequested(withSameToken: deviceToken, in: self)
                }
            } else {
                //Post request should be sent from delegate
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
        let pushInfo = PushInfo(userInfo: notification.request.content.userInfo, applicationState: UIApplication.shared.applicationState)
        delegate?.willPresent(pushNotification: pushInfo, in: self)
        completionHandler(shouldShowSystemInAppAlert ? [.alert, .sound] : [])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        self.handleDidRecieveNotification(response.notification.request.content.userInfo, app: UIApplication.shared, handler: nil)
    }
}
