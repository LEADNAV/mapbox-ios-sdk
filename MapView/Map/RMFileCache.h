//
//  RMFileCache.h
//  MapView
//
//  Created by Nathan Giordano on 8/18/14.
//
//

#import <Foundation/Foundation.h>
#import "RMTileCache.h"

@interface RMFileCache : NSObject <RMTileCache>

@property (nonatomic, assign) NSTimeInterval expiryPeriod;

- (id)initWithCacheDir:(NSString *)cacheDir;

@end
