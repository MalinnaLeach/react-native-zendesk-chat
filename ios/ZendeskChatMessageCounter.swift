import ChatProvidersSDK
import ChatSDK
import MessagingSDK
import CommonUISDK
import React

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
    
    open override func supportedEvents() -> [String]! {
      return EventEmitterSuported.allCases.map({ $0.description })
    }
    
    /// Called every time the unread message count has changed
    var onUnreadMessageCountChange: ((Int) -> Void)?
    
    var isActive = false {
        didSet {
            if isActive == false {
                stopMessageCounter()
            }
        }
    }
    
    // MARK: Observations
    /// Collection of token objects to group NotificationCentre related observations
    var notificationTokens: [NotificationToken] = []
    
    /// Collection of `ObservationToken` objects to group Chat related observations
    private var observations: ObserveBehaviours?
    
    // MARK: Chat
    private let chat: Chat
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
        guard
            isActive && isChatting == true,
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
            if oldValue != numberOfUnreadMessages && isActive {
                onUnreadMessageCountChange?(numberOfUnreadMessages)
                sendEvent(withName: EventEmitterSuported.UnreadMessageCountChange.description,
                          body: ["count": numberOfUnreadMessages])
                
            }
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
    }
    
    // MARK: Connection life-cycle
    @objc(connectToChat)
    func connectToChat() {
        guard isActive else { return }
        connect()
        startObservingChat()
    }
    
    @objc(getNumberOfUnreadMessages)
    public func getNumberOfUnreadMessages() -> Int {
        return numberOfUnreadMessages
    }
    
    // MARK: Message counter
    func startMessageCounterIfNeeded() {
        guard isChatting == true && !isActive else { return }
        
        lastSeenMessage = chatState?.logs.last
        updateUnreadMessageCount()
    }
    
    func stopMessageCounter() {
        stopObservingChat()
        resetUnreadMessageCount()
        disconnect()
    }
}

// MARK: - Private methods
private extension ZendeskChatMessageCounter {
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
    }
    
    // To stop observing we have to call unobserve on each observer
    func stopObservingChat() {
        observations?.unobserve()
        observations = nil
        notificationTokens.removeAll()
    }
    
    func observeConnectionStatus() -> ObserveBehaviour {
        chat.connectionProvider.observeConnectionStatus { [weak self] (status) in
            guard let self = self else { return }
            guard status == .connected else { return }
            _ = self.observeChatState()
        }.asBehaviour()
    }
    
    private func observeChatState() -> ObserveBehaviour {
        chat.chatProvider.observeChatState { [weak self] (state) in
            guard let self = self else { return }
            guard self.connectionStatus == .connected else { return }
            
            if state.isChatting == false {
                self.stopMessageCounter()
            }
            
            if self.isActive {
                self.updateUnreadMessageCount()
            }
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
        observeApplicationEvents()
    }
    
    func observeApplicationEvents() {
        observeNotification(withName: UIApplication.didEnterBackgroundNotification) { [weak self] _ in
            self?.disconnect()
        }
        
        observeNotification(withName: UIApplication.willEnterForegroundNotification) { [weak self] _ in
            if self?.isActive == true {
                self?.connect()
            }
        }
        
        observeNotification(withName: Chat.NotificationChatEnded) { [weak self] _ in
            if self?.isActive == true {
                self?.stopMessageCounter()
            }
        }
    }
}
