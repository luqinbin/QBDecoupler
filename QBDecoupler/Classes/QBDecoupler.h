//
//  QBDecoupler.h
//  WMRouterDemo
//
//  Created by 覃斌 卢    on 2019/9/24.
//  Copyright © 2019 覃斌 卢   . All rights reserved.
//

#import <Foundation/Foundation.h>
#import "QBDecouplerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

#define QBDecouplerRegister(service_protocol) [QBDecoupler registerService:@protocol(service_protocol) withModule:self.class];
#define QBModule(service_protocol) ((id<service_protocol>)[QBDecoupler moduleByService:@protocol(service_protocol)])
#define QBStr(fmt, ...) [NSString stringWithFormat:fmt, ##__VA_ARGS__]

typedef NS_ENUM(NSInteger, QBDecouplerExceptionCode)
{
    QBExceptionDefaultCode = -22000,                                    // 默认错误码
    QBExceptionModuleNotFoundException = -22001,                        // 未知模块
    QBExceptionAPINotFoundException = -22002,                           // 未知协议API
    QBExceptionFailedToRegisterModule = -22003,                         // 注册模块失败
    QBExceptionFailedToSetupModule = -22004,                            // 初始化配置模块识别
    QBExceptionFailedToFindModuleByService = -22005,                    // 未找到协议映射的模块
};

extern NSExceptionName _Nonnull QBDecouplerExceptionName;

extern NSString *const _Nonnull kQBDecouplerExceptionCode;
extern NSString *const _Nonnull kQBDecouplerExceptionServiceProtocolStr;
extern NSString *const _Nonnull kQBDecouplerExceptionModuleClassStr;
extern NSString *const _Nonnull kQBDecouplerExceptionAPIStr;
extern NSString *const _Nonnull kQBDecouplerExceptionAPIArguments;

@interface NSException (QBDecoupler)

- (QBDecouplerExceptionCode)qb_exceptionCode;

@end

/**
 异常回调，比如未知协议API
 
 @param exception 执行module api时抛出的异常
 @return object
 */
typedef _Nullable id (^QBDecouplerExceptionHandler)(NSException * _Nonnull exception);

@interface QBDecoupler : NSObject

+ (void)setExceptionHandler:(QBDecouplerExceptionHandler _Nullable )handler;

+ (QBDecouplerExceptionHandler _Nullable )getExceptionHandler;

/**
 注册模块service协议和模块class的映射
 
 @param serviceProtocol moduleService协议
 @param moduleClass The class of the module
 */
+ (void)registerService:(Protocol*_Nonnull)serviceProtocol
             withModule:(Class<QBDecouplerModuleProtocol> _Nonnull)moduleClass;

/**
 setup 所有注册模块
 */
+ (void)setupAllModules;

/**
 获取module对象
 
 @param serviceProtocol 模块服务接口协议
 @return module instance
 */
+ (id<QBDecouplerModuleProtocol> _Nullable)moduleByService:(Protocol*_Nonnull)serviceProtocol;

/**
 获取所有的注册模块，根据优先级降序排序
 
 @return module
 */
+ (NSArray<Class<QBDecouplerModuleProtocol>>*_Nonnull)allRegisteredModules;

/**
 各模块执行UIApplicationDelegate方法
 
 @param selector appdelegate 声明周期方法
 @param arguments argument array
 @return the return 各模块的执行结果
 */
+ (BOOL)checkAllModulesWithSelector:(nonnull SEL)selector
                          arguments:(nullable NSArray*)arguments;

@end

NS_ASSUME_NONNULL_END
