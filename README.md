# ONXPushManager

This is a simple class written in Swift to help you manage push notifications in a simple way.
This class will help you:
* delete/update a proper device/token on a server (server should be applicable to the way it's done in this class)
* replace all your Remote Notifications code with just few lines of forwarding
* handle the remote notification properly depending on the state it was received
* handle the situation when Remote Notification is received before views are loaded

Just subclass the ONXPushManager and override following methods with your code:
* func actFromPush(pushInfo: PushInfo)
Put your custom actions here depending on PushInfo.

* func updatePushesWithLatestToken()
Update/Add token backend requests go here

* func deleteTokenFromBackend()
Delete request goes here

* func handleApplicationDidBecomeActive(app: UIApplication)
This one is optional, you can, for example, clear badge here.

Please see https://gist.github.com/nezhyborets/427a3e8eb403cea42b61 for example of sublcassing
