//
//  RMURLMapSource.h
//  MapView
//
//  Created by Nathan Giordano on 7/11/14.
//
//

#import "RMAbstractWebMapSource.h"

@interface RMURLMapSource : RMAbstractWebMapSource

- (id)initWithURLTemplate:(NSString *)URLTemplate tileCacheKey:(NSString *)tileCacheKey minZoom:(float)minZoom maxZoom:(float)maxZoom;

@end
