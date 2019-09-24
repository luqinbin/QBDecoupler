#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "QBDecoupler.h"
#import "QBDecouplerHeader.h"
#import "QBDecouplerProtocol.h"

FOUNDATION_EXPORT double QBDecouplerVersionNumber;
FOUNDATION_EXPORT const unsigned char QBDecouplerVersionString[];

