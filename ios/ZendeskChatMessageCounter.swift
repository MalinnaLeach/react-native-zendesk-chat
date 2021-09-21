import ChatProvidersSDK
import ChatSDK
import MessagingSDK
import CommonUISDK
import React

public extension Notification.Name {
    static let zendeskChatUpdate = Notification.Name("ZendeskChatUpdate")
}

@objc(ZendeskChatMessageCounter)
final class ZendeskChatMessageCounter: RCTEventEmitter, NotificationCenterObserver {
    public override static func requiresMainQueueSetup() -> Bool {
        return false
    }
    
    internal enum EventEmitterSuported: String, CaseIterable, CustomStringConvertible {
        case UnreadMessageCountChange
        
        var description: String {
            return rawValue
        }
    }
    
    public override func supportedEvents() -> [String]! {
        return EventEmitterSuported.allCases.map({ $0.description })
    }
    
    // MARK: Observations
    /// Collection of token objects to group NotificationCentre related observations
    var notificationTokens: [NotificationToken] = []
    
    /// Collection of `ObservationToken` objects to group Chat related observations
    private var observations: ObserveBehaviours?
    
    // MARK: Chat
    private var chat: Chat
    private var isChatting: Bool? {
        guard connectionStatus == .connected else {
            return nil
        }
        return chatState?.isChatting == true
    }
    
    private var chatState: ChatState? {
        chat.chatProvider.chatState
    }
    
    private var connectionStatus: ConnectionStatus {
        chat.connectionProvider.status
    }
    
    // MARK: Unread messages
    private var lastSeenMessage: ChatLog?
    private var unreadMessages: [ChatLog]? {
        if lastSeenMessage == nil {
            updateLastSeenMessage()
        }
        
        guard
            let chatState = chatState,
            let lastSeenMessage = lastSeenMessage else {
            return nil
        }
        return chatState.logs
            .filter { $0.participant == .agent }
            .filter { $0.createdTimestamp > lastSeenMessage.createdTimestamp }
    }
    
    private var numberOfUnreadMessages = 0 {
        didSet {
            sendEvent(withName: EventEmitterSuported.UnreadMessageCountChange.description,
                          body: ["count": numberOfUnreadMessages])
        }
    }
    
    init(chat: Chat) {
        self.chat = chat
        super.init()
    }
    
    override init() {
        guard let chat = Chat.instance else {
            fatalError("Chat instance is nil.")
        }
        self.chat = chat
        super.init()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.connectToChat()
        }
    }
    
    deinit {
        debugPrint(#function, #file)
    }
    
    // MARK: Connection life-cycle.
    @objc(connectToChat)
    func connectToChat() {
        updateChatReference()
        connect()
        startObservingChat()
        startMessageCounterIfNeeded()
    }
    
    @objc
    public func getNumberOfUnreadMessages(_ callback: RCTResponseSenderBlock) {
        callback([numberOfUnreadMessages])
    }
    
    // MARK: Message counter
    func startMessageCounterIfNeeded() {
        updateLastSeenMessage()
        updateUnreadMessageCount()
    }
    
    func updateLastSeenMessage() {
        if let lastLogId = UserDefaults.standard.value(forKey: "ZendeskLastLogId") as? String {
            lastSeenMessage = chatState?.logs.filter({ $0.id == lastLogId }).first
        } else {
            lastSeenMessage = chatState?.logs.last
        }
    }
    
    func stopMessageCounter() {
        stopObservingChat()
        resetUnreadMessageCount()
        disconnect()
    }
}

// MARK: - Private methods
private extension ZendeskChatMessageCounter {
    func updateChatReference() {
        guard let chat = Chat.instance else { return }
        self.chat = chat
    }
    
    func updateUnreadMessageCount() {
        numberOfUnreadMessages = unreadMessages?.count ?? 0
    }
    
    func resetUnreadMessageCount() {
        numberOfUnreadMessages = 0
    }
    
    func connect() {
        guard connectionStatus != .connected else { return }
        chat.connectionProvider.connect()
    }
    
    func disconnect() {
        chat.connectionProvider.disconnect()
        unobserveNotifications()
    }
    
    // To stop observing we have to call unobserve on each observer
    func stopObservingChat() {
        observations?.unobserve()
        observations = nil
        notificationTokens.removeAll()
    }
    
    func observeConnectionStatus() -> ObserveBehaviour {
        return chat.connectionProvider.observeConnectionStatus { (status) in
            debugPrint("connection status: \(status)")
        }.asBehaviour()
    }
    
    @discardableResult
    private func observeChatState() -> ObserveBehaviour {
        return chat.chatProvider.observeChatState { [weak self] (state) in
            guard let self = self else { return }
            guard self.connectionStatus == .connected else { return }
            
            self.updateUnreadMessageCount()
        }.asBehaviour()
    }
    
    // MARK: Observations
    /// We observe the connection and once it successfully connects we can start observing the state of the chat.
    func startObservingChat() {
        observations = ObserveBehaviours(
            observeConnectionStatus(),
            observeChatState()
        )
        
        observeNotification(withName: Chat.NotificationChatEnded) { [weak self] _ in
            self?.stopMessageCounter()
        }
        
        observeNotification(withName: Chat.NotificationMessageReceived) { [weak self] _ in
            self?.updateUnreadMessageCount()
        }
        
        observeNotification(withName: .zendeskChatUpdate) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.stopMessageCounter()
                self?.connectToChat()
            }
        }
        
        observeApplicationEvents()
    }
    
    func observeApplicationEvents() {
        observeNotification(withName: UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            self?.disconnect()
        }
        
        observeNotification(withName: UIApplication.willEnterForegroundNotification) { [weak self] _ in
            self?.connect()
        }
    }
}
