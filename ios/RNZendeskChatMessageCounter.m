#import <React/RCTBridgeModule.h>
#import "React/RCTEventEmitter.h"

@interface RCT_EXTERN_MODULE(ZendeskChatMessageCounter, RCTEventEmitter)

RCT_EXTERN_METHOD(connectToChat);
RCT_EXTERN_METHOD(getNumberOfUnreadMessages);

@end
