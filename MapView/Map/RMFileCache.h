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

@property (weak, nonatomic) RMTileCache *tileCache;
@property (nonatomic, assign) NSUInteger capacity;
@property (nonatomic, assign) NSTimeInterval expiryPeriod;

+ (id)cacheWithCacheDir:(NSString *)cacheDir;
- (id)initWithCacheDir:(NSString *)cacheDir;

@end
