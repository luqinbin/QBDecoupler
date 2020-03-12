//
//  QBDecoupler.m
//  
//
//  Created by 覃斌 卢    on 2019/9/24.
//  Copyright © 2019 覃斌 卢   . All rights reserved.
//

#import "QBDecoupler.h"
#import <objc/message.h>
#import <objc/runtime.h>

#define QBLog(msg) NSLog(@"[QBDecoupler] %@", (msg))
#define QBDecouplerInstance [QBDecoupler sharedInstance]

NSExceptionName QBDecouplerExceptionName = @"QBDecouplerExceptionName";

NSString * const kQBDecouplerExceptionCode = @"QBDecouplerExceptionCode";
NSString * const kQBDecouplerExceptionServiceProtocolStr = @"kQBDecouplerExceptionServiceProtocolStr";
NSString * const kQBDecouplerExceptionModuleClassStr = @"kQBDecouplerExceptionModuleClassStr";
NSString * const kQBDecouplerExceptionAPIStr = @"kQBDecouplerExceptionAPIStr";
NSString * const kQBDecouplerExceptionAPIArguments = @"kQBDecouplerExceptionAPIArguments";

@implementation NSException (QBDecoupler)

- (QBDecouplerExceptionCode)qb_exceptionCode {
    return [self.userInfo[kQBDecouplerExceptionCode] integerValue];
}
@end

@interface NSObject (QBDecoupler)

- (void)qb_doesNotRecognizeSelector:(SEL)aSelector;

@end

@interface QBDecoupler ()

@property (nonatomic, copy) QBDecouplerExceptionHandler _Nullable exceptionHandler;

// <moduleName, moduleClass>
@property (nonatomic, strong) NSMutableDictionary<NSString *, Class> *moduleDict;
@property (nonatomic, strong) NSMutableDictionary *moduleInvokeDict;

+ (instancetype _Nonnull )sharedInstance;

@end

@implementation QBDecoupler

+ (instancetype _Nonnull )sharedInstance
{
    static QBDecoupler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
        instance.moduleDict = [NSMutableDictionary dictionary];
        instance.moduleInvokeDict = [NSMutableDictionary dictionary];
    });
    return instance;
}

+ (void)setExceptionHandler:(QBDecouplerExceptionHandler _Nullable )handler {
    QBDecouplerInstance.exceptionHandler = handler;
}

+ (QBDecouplerExceptionHandler _Nullable )getExceptionHandler {
    return QBDecouplerInstance.exceptionHandler;
}

+ (void)registerService:(Protocol*_Nonnull)serviceProtocol
             withModule:(Class<QBDecouplerModuleProtocol> _Nonnull)moduleClass {
    [QBDecouplerInstance registerService:serviceProtocol withModule:moduleClass];
}

- (void)registerService:(Protocol*_Nonnull)serviceProtocol
             withModule:(Class<QBDecouplerModuleProtocol> _Nonnull)moduleClass {
    
    NSString *protocolStr = NSStringFromProtocol(serviceProtocol);
    NSString *moduleStr = NSStringFromClass(moduleClass);
    Class class = moduleClass;
    NSString *exReason = nil;
    if (protocolStr.length == 0) {
        exReason =  QBStr(@"invalid protocol for module %@", moduleStr);
    } else if (moduleStr.length == 0) {
        exReason =  QBStr(@"invalid module for protocol %@", protocolStr);
    } else if (![class conformsToProtocol:serviceProtocol]) {
        exReason =  QBStr(@"Module %@ should confirm to protocol %@", moduleStr, protocolStr);
    } else {
        [QBDecoupler hackUnrecognizedSelecotorExceptionForModule:moduleClass];
        [QBDecouplerInstance.moduleDict setObject:moduleClass forKey:protocolStr];
    }
    if (exReason.length > 0)  {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        [userInfo setValue:@(QBExceptionFailedToRegisterModule) forKey:kQBDecouplerExceptionCode];
        [userInfo setValue:protocolStr forKey:kQBDecouplerExceptionServiceProtocolStr];
        NSException *exception = [[NSException alloc] initWithName:QBDecouplerExceptionName
                                                            reason:exReason
                                                          userInfo:userInfo];
        QBDecouplerExceptionHandler handler = [QBDecoupler getExceptionHandler];
        if (handler) {
            handler(exception);
        }
        QBLog(exReason);
    }
}

+ (NSArray<Class<QBDecouplerModuleProtocol>>*_Nonnull)allRegisteredModules {
    NSArray *modules = QBDecouplerInstance.moduleDict.allValues;
    NSArray *sortedModules = [modules sortedArrayUsingComparator:^NSComparisonResult(Class class1, Class class2) {
        NSUInteger priority1 = QBDecouplerModuleDefaultPriority;
        NSUInteger priority2 = QBDecouplerModuleDefaultPriority;
        if ([class1 respondsToSelector:@selector(priority)]) {
            priority1 = [class1 priority];
        }
        if ([class2 respondsToSelector:@selector(priority)]) {
            priority2 = [class2 priority];
        }
        if(priority1 == priority2) {
            return NSOrderedSame;
        } else if(priority1 < priority2) {
            return NSOrderedDescending;
        } else {
            return NSOrderedAscending;
        }
    }];
    return sortedModules;
}

+ (void)setupAllModules {
    NSArray *modules = [self allRegisteredModules];
    for (Class<QBDecouplerModuleProtocol> moduleClass in modules) {
        @try {
            BOOL setupSync = NO;
            if ([moduleClass respondsToSelector:@selector(setupModuleSynchronously)]) {
                setupSync = [moduleClass setupModuleSynchronously];
            }
            if (setupSync) {
                [[moduleClass sharedInstance] setup];
            } else {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [[moduleClass sharedInstance] setup];
                });
            }
        } @catch (NSException *exception) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:exception.userInfo];
            [userInfo setValue:@(QBExceptionFailedToSetupModule) forKey:kQBDecouplerExceptionCode];
            [userInfo setValue:NSStringFromClass(moduleClass) forKey:kQBDecouplerExceptionModuleClassStr];
            NSException *ex = [[NSException alloc] initWithName:exception.name
                                                         reason:exception.reason
                                                       userInfo:userInfo];
            QBDecouplerExceptionHandler handler = [self getExceptionHandler];
            if (handler) {
                handler(ex);
            }
            QBLog(exception.reason);
        }
    }
}

+ (id<QBDecouplerModuleProtocol> _Nullable)moduleByService:(Protocol*_Nonnull)serviceProtocol {
    NSString *protocolStr = NSStringFromProtocol(serviceProtocol);
    NSString *exReason = nil;
    NSException *exception = nil;
    if (protocolStr.length == 0) {
        exReason = QBStr(@"Invalid service protocol");
    } else {
        Class class = QBDecouplerInstance.moduleDict[protocolStr];
        NSString *classStr = NSStringFromClass(class);
        if (!class) {
            exReason = QBStr(@"Failed to find module by protocol %@", protocolStr);
        } else if (![class conformsToProtocol:@protocol(QBDecouplerModuleProtocol)]) {
            exReason = QBStr(@"Found %@ by protocol %@, but the module doesn't confirm to protocol QBDecouplerModuleProtocol",
                             classStr, protocolStr);
        } else {
            @try {
                id instance = [class sharedInstance];
                return instance;
            } @catch (NSException *ex) {
                exception = ex;
            }
        }
    }
    if (exReason.length > 0) {
        NSExceptionName name = QBDecouplerExceptionName;
        NSMutableDictionary *userInfo = nil;
        if (exception != nil) {
            userInfo = [NSMutableDictionary dictionaryWithDictionary:exception.userInfo];
            name = exception.name;
        } else {
            userInfo = [NSMutableDictionary dictionary];
        }
        [userInfo setValue:@(QBExceptionFailedToFindModuleByService) forKey:kQBDecouplerExceptionCode];
        [userInfo setValue:NSStringFromProtocol(serviceProtocol) forKey:kQBDecouplerExceptionServiceProtocolStr];
        NSException *ex = [[NSException alloc] initWithName:name
                                                     reason:exReason
                                                   userInfo:userInfo];
        QBDecouplerExceptionHandler handler = [self getExceptionHandler];
        if (handler) {
            handler(ex);
        }
        QBLog(exReason);
        return nil;
    }
}

+ (BOOL)checkAllModulesWithSelector:(SEL)selector arguments:(NSArray*)arguments {
    BOOL result = NO;
    NSArray *modules = [self allRegisteredModules];
    for (Class<QBDecouplerModuleProtocol> class in modules) {
        id<QBDecouplerModuleProtocol> moduleItem = [class sharedInstance];
        if ([moduleItem respondsToSelector:selector]) {
            
            __block BOOL shouldInvoke = YES;
            if (![QBDecouplerInstance.moduleInvokeDict objectForKey:NSStringFromClass([moduleItem class])]) {
                // 如果 modules 里面有 moduleItem 的子类，不 invoke target
                [modules enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    if ([NSStringFromClass([obj superclass]) isEqualToString:NSStringFromClass([moduleItem class])]) {
                        shouldInvoke = NO;
                        *stop = YES;
                    }
                }];
            }
            
            if (shouldInvoke) {
                if (![QBDecouplerInstance.moduleInvokeDict objectForKey:NSStringFromClass([moduleItem class])]) { //cache it
                    [QBDecouplerInstance.moduleInvokeDict setObject:moduleItem forKey:NSStringFromClass([moduleItem class])];
                }
                
                BOOL ret = NO;
                [self invokeTarget:moduleItem action:selector arguments:arguments returnValue:&ret];
                if (!result) {
                    result = ret;
                }
            }
        }
    }
    return result;
}

+ (BOOL)invokeTarget:(id)target
              action:(_Nonnull SEL)selector
           arguments:(NSArray* _Nullable )arguments
         returnValue:(void* _Nullable)result; {
    if (target && [target respondsToSelector:selector]) {
        NSMethodSignature *sig = [target methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
        [invocation setTarget:target];
        [invocation setSelector:selector];
        for (NSUInteger i = 0; i<[arguments count]; i++) {
            NSUInteger argIndex = i+2;
            id argument = arguments[i];
            if ([argument isKindOfClass:NSNumber.class]) {
                BOOL shouldContinue = NO;
                NSNumber *num = (NSNumber*)argument;
                const char *type = [sig getArgumentTypeAtIndex:argIndex];
                if (strcmp(type, @encode(BOOL)) == 0) {
                    BOOL rawNum = [num boolValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if (strcmp(type, @encode(int)) == 0
                           || strcmp(type, @encode(short)) == 0
                           || strcmp(type, @encode(long)) == 0) {
                    NSInteger rawNum = [num integerValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if(strcmp(type, @encode(long long)) == 0) {
                    long long rawNum = [num longLongValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if (strcmp(type, @encode(unsigned int)) == 0
                           || strcmp(type, @encode(unsigned short)) == 0
                           || strcmp(type, @encode(unsigned long)) == 0) {
                    NSUInteger rawNum = [num unsignedIntegerValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if(strcmp(type, @encode(unsigned long long)) == 0) {
                    unsigned long long rawNum = [num unsignedLongLongValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if (strcmp(type, @encode(float)) == 0) {
                    float rawNum = [num floatValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                } else if (strcmp(type, @encode(double)) == 0) {
                    double rawNum = [num doubleValue];
                    [invocation setArgument:&rawNum atIndex:argIndex];
                    shouldContinue = YES;
                }
                if (shouldContinue) {
                    continue;
                }
            }
            if ([argument isKindOfClass:[NSNull class]]) {
                argument = nil;
            }
            [invocation setArgument:&argument atIndex:argIndex];
        }
        [invocation invoke];
        NSString *methodReturnType = [NSString stringWithUTF8String:sig.methodReturnType];
        if (result && ![methodReturnType isEqualToString:@"v"]) { // return type 不为空
            if([methodReturnType isEqualToString:@"@"]) { // return type： NSObject
                CFTypeRef cfResult = nil;
                [invocation getReturnValue:&cfResult];
                if (cfResult) {
                    CFRetain(cfResult);
                    *(void**)result = (__bridge_retained void *)((__bridge_transfer id)cfResult);
                }
            } else {
                [invocation getReturnValue:result];
            }
        }
        return YES;
    }
    return NO;
}

+ (void)hackUnrecognizedSelecotorExceptionForModule:(Class)class {
    SEL originSEL = @selector(doesNotRecognizeSelector:);
    SEL newSEL = @selector(qb_doesNotRecognizeSelector:);
    [self swizzleOrginSEL:originSEL withNewSEL:newSEL inClass:class];
}

+ (void)swizzleOrginSEL:(SEL)originSEL withNewSEL:(SEL)newSEL inClass:(Class)class {
    Method origMethod = class_getInstanceMethod(class, originSEL);
    Method overrideMethod = class_getInstanceMethod(class, newSEL);
    if (class_addMethod(class, originSEL, method_getImplementation(overrideMethod),
                        method_getTypeEncoding(overrideMethod))) {
        class_replaceMethod(class, newSEL, method_getImplementation(origMethod),
                            method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, overrideMethod);
    }
}

@end

@implementation NSObject (QBDecoupler)

- (void)qb_doesNotRecognizeSelector:(SEL)aSelector {
    @try {
        [self qb_doesNotRecognizeSelector:aSelector];
    } @catch (NSException *ex) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        [userInfo setValue:@(QBExceptionAPINotFoundException) forKey:kQBDecouplerExceptionCode];
        NSException *exception = [[NSException alloc] initWithName:ex.name
                                                            reason:ex.reason
                                                          userInfo:userInfo];
        if (QBDecouplerInstance.exceptionHandler) {
            QBDecouplerInstance.exceptionHandler(exception);
        } else {
#ifdef DEBUG
            @throw exception;
#endif
        }
    } @finally {
    }
}

@end
