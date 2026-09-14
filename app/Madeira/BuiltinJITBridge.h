#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MadeiraBuiltinJITCompletion)(BOOL success, NSString *message);

@interface MadeiraBuiltinJITBridge : NSObject

+ (void)enableJITForPID:(int32_t)pid
             pairingData:(NSData *)pairingData
              scriptData:(NSData *)scriptData
                 started:(MadeiraBuiltinJITCompletion)started
                finished:(MadeiraBuiltinJITCompletion)finished
    NS_SWIFT_NAME(enableJIT(pid:pairingData:scriptData:started:finished:));

@end

NS_ASSUME_NONNULL_END
