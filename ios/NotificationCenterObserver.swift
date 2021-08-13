/*
 *  NotificationCenterObserver.swift
 *  Common
 *
 *  Created by Zendesk on 26/03/2019.
 *
 *  Copyright © 2019 Zendesk. All rights reserved.
 *
 *  By downloading or using the Zendesk Mobile SDK, You agree to the Zendesk Master
 *  Subscription Agreement https://www.zendesk.com/company/customers-partners/#master-subscription-agreement and Application Developer and API License
 *  Agreement https://www.zendesk.com/company/customers-partners/#application-developer-api-license-agreement and
 *  acknowledge that such terms govern Your use of and access to the Mobile SDK.
 */

import Foundation

final class NotificationToken {
    private let token: NSObjectProtocol
    private let notificationCenter: NotificationCenter
    let name: Notification.Name

    deinit {
        cancel()
    }

    init(token: NSObjectProtocol, notificationCenter: NotificationCenter, name: Notification.Name) {
        self.token = token
        self.notificationCenter = notificationCenter
        self.name = name
    }

    func cancel() {
        notificationCenter.removeObserver(token)
    }
}

extension NotificationCenter {

    func addObserver(forName name: Notification.Name, closure: @escaping (Notification) -> Void) -> NotificationToken {
        let token = addObserver(forName: name, object: nil, queue: nil, using: closure)
        return NotificationToken(token: token, notificationCenter: self, name: name)
    }

}

protocol NotificationCenterObserver: class {

    var notificationTokens: [NotificationToken] { get set }

    /// Unobserve NotificationCenter notifications.
    func unobserveNotifications()
    func unobserveNotification(withName name: NSNotification.Name)

    func observeNotification(withName name: NSNotification.Name, closure: @escaping (Notification) -> Void)
}

extension NotificationCenterObserver {

    func unobserveNotifications() {
        notificationTokens.forEach { $0.cancel() }
        notificationTokens.removeAll()
    }

    func unobserveNotification(withName name: NSNotification.Name) {
        for notification in notificationTokens where notification.name == name {
            notification.cancel()
        }
        notificationTokens.removeAll { $0.name == name }
    }

    func observeNotification(withName name: NSNotification.Name, closure: @escaping (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, closure: closure)
        notificationTokens.append(token)
    }
}
