import ChatProvidersSDK
import ChatSDK
import MessagingSDK

@objc(ZendeskChatMessageCounter)
final class ZendeskChatMessageCounter: NotificationCenterObserver {
    init() {
        Messaging.instance.delegate = self
        guard let chat = Chat.instance else { return }
        messageCounter = ZendeskChatMessageCounter(chat: chat)
        messageCounter?.onUnreadMessageCountChange = { [weak self] numberOfUnreadMessages in
            guard let self = self else { return }
            // Notify delegate
            self.delegate?.unreadMessageCountChanged(numberOfUnreadMessages: numberOfUnreadMessages,
            in: self)
        }
    }

    // Called every time the unread message count has changed
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

    var unreadMessages: [ChatLog]? {
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

    private(set) var numberOfUnreadMessages = 0 {
        didSet {
            if oldValue != numberOfUnreadMessages && isActive {
                onUnreadMessageCountChange?(numberOfUnreadMessages)
            }
        }
    }

    init(chat: Chat) {
        self.chat = chat
    }

    // To stop observing we have to call unobserve on each observer
    private func stopObservingChat() {
        observations?.unobserve()
        observations = nil
        notificationTokens.removeAll()
    }

    private func observeConnectionStatus() -> ObserveBehaviour {
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

    // MARK: Connection life-cycle

    private func connect() {
        guard connectionStatus != .connected else { return }
        chat.connectionProvider.connect()
    }

    private func disconnect() {
        chat.connectionProvider.disconnect()
    }

    func connectToChat() {
        guard isActive else { return }
        connect()
        startObservingChat()
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

    private func updateUnreadMessageCount() {
        numberOfUnreadMessages = unreadMessages?.count ?? 0
    }

    private func resetUnreadMessageCount() {
        numberOfUnreadMessages = 0
    }

    // MARK: unread message counter
    private var messageCounter: ZendeskChatMessageCounter?

    var isUnreadMessageCounterActive = false {
        didSet {
            messageCounter?.isActive = isUnreadMessageCounterActive
        }
}

var numberOfUnreadMessages: Int {
    messageCounter?.numberOfUnreadMessages ?? 0
}
}

extension ZendeskChatMessageCounter {
    // MARK: Observations
    //We observe the connection and once it successfully connects we can start observing the state of the chat.
    private func startObservingChat() {
        observations = ObserveBehaviours(
            observeConnectionStatus(),
            observeChatState()
        )

        observeNotification(withName: Chat.NotificationChatEnded) { [weak self] _ in
            self?.stopMessageCounter()
        }
        observeApplicationEvents()
    }

    private func observeApplicationEvents() {
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

