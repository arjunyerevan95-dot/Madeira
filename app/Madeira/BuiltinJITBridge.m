#import "BuiltinJITBridge.h"

// NSExtension's host-side launcher is Foundation SPI. Madeira is a sideloaded
// JIT application already outside App Store constraints; declaring the small
// surface here keeps the private API isolated from the rest of the app.
@interface NSExtension : NSObject
+ (instancetype)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *requestIdentifier))completion;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *uuid, NSError *error))callback;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *uuid, NSArray *extensionItems))callback;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *uuid))callback;
@end

@implementation MadeiraBuiltinJITBridge

static NSExtension *activeExtension;
static MadeiraBuiltinJITCompletion activeStarted;
static MadeiraBuiltinJITCompletion activeFinished;

+ (void)finish:(BOOL)success message:(NSString *)message {
    MadeiraBuiltinJITCompletion started = activeStarted;
    MadeiraBuiltinJITCompletion finished = activeFinished;
    activeStarted = nil;
    activeFinished = nil;
    activeExtension = nil;
    if (started) {
        dispatch_async(dispatch_get_main_queue(), ^{
            started(NO, message ?: @"Built-in JIT helper failed to start.");
        });
    }
    if (finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            finished(success, message ?: @"");
        });
    }
}

+ (void)enableJITForPID:(int32_t)pid
             pairingData:(NSData *)pairingData
              scriptData:(NSData *)scriptData
                 started:(MadeiraBuiltinJITCompletion)started
                finished:(MadeiraBuiltinJITCompletion)finished {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (activeExtension != nil) {
            started(NO, @"A built-in JIT request is already running.");
            return;
        }

        NSString *hostID = NSBundle.mainBundle.bundleIdentifier;
        if (hostID.length == 0) {
            started(NO, @"Could not determine Madeira's bundle identifier.");
            return;
        }

        NSString *helperID = [hostID stringByAppendingString:@".StikJITHelper"];
        NSError *error = nil;
        NSExtension *extension = [NSExtension extensionWithIdentifier:helperID error:&error];
        if (extension == nil) {
            started(NO, error.localizedDescription ?: @"Could not start the built-in JIT helper.");
            return;
        }

        activeExtension = extension;
        activeStarted = [started copy];
        activeFinished = [finished copy];

        [extension setRequestCancellationBlock:^(NSUUID *uuid, NSError *error) {
            [self finish:NO message:error.localizedDescription ?: @"Built-in JIT request was cancelled."];
        }];
        [extension setRequestInterruptionBlock:^(NSUUID *uuid) {
            [self finish:NO message:@"Built-in JIT helper was interrupted."];
        }];
        [extension setRequestCompletionBlock:^(NSUUID *uuid, NSArray *items) {
            NSExtensionItem *result = items.firstObject;
            NSDictionary *info = result.userInfo;
            BOOL success = [info[@"success"] boolValue];
            NSString *message = info[@"message"];
            [self finish:success message:message ?: (success ? @"Built-in JIT enabled." : @"Built-in JIT failed.")];
        }];

        NSExtensionItem *item = [NSExtensionItem new];
        item.userInfo = @{
            @"pid": @(pid),
            @"pairingData": pairingData,
            @"scriptData": scriptData,
        };
        [extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *requestIdentifier) {
            if (requestIdentifier == nil) {
                [self finish:NO message:@"Built-in JIT helper did not accept the request."];
                return;
            }
            MadeiraBuiltinJITCompletion callback = activeStarted;
            activeStarted = nil;
            if (callback) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    callback(YES, @"Built-in JIT helper started.");
                });
            }
        }];
    });
}

@end
