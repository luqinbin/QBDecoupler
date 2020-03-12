//
//  QBDecouplerProtocol.h
//  
//
//  Created by 覃斌 卢    on 2019/9/24.
//  Copyright © 2019 覃斌 卢   . All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define QBDecouplerModuleDefaultPriority 100

@protocol QBDecouplerModuleProtocol <NSObject>

@required

+ (instancetype)sharedInstance;

/**
 模块配置方法，再注册modules时调用
 比如监听NSNotificationCenter
 当setupModuleSynchronously方法return NO， 则在后台线程异步执行
 */
- (void)setup;

@optional

/**
 模块setup的优先级
 
 @return the priority
 */
+ (NSUInteger)priority;


/**
 setup方法默认在后台线程异步执行，默认为NO。
 return Yes，则在主线程同步执行。
 
 @return whether synchronously
 */
+ (BOOL)setupModuleSynchronously;

@end

NS_ASSUME_NONNULL_END
