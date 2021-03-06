//
//  RMTileCache.m
//
// Copyright (c) 2008-2009, Route-Me Contributors
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import <sys/utsname.h>

#import "RMTileCache.h"
#import "RMMemoryCache.h"
#import "RMDatabaseCache.h"
#import "RMFileCache.h"

#import "RMConfiguration.h"
#import "RMTileSource.h"

#import "RMTileCacheDownloadOperation.h"

@interface RMTileCache (Configuration)

- (id <RMTileCache>)memoryCacheWithConfig:(NSDictionary *)cfg;
- (id <RMTileCache>)databaseCacheWithConfig:(NSDictionary *)cfg;
- (id <RMTileCache>)fileCacheWithConfig:(NSDictionary *)cfg;

@end

@implementation RMTileCache
{
    NSMutableArray *_tileCaches;

    // The memory cache, if we have one
    // This one has its own variable because we want to propagate cache hits down in
    // the cache hierarchy up to the memory cache
    RMMemoryCache *_memoryCache;
    NSTimeInterval _expiryPeriod;

    dispatch_queue_t _tileCacheQueue;
    
    id <RMTileSource>_activeTileSource;
    NSOperationQueue *_backgroundFetchQueue;
}

@synthesize backgroundCacheDelegate=_backgroundCacheDelegate;

- (id)initWithExpiryPeriod:(NSTimeInterval)period
{
    if (!(self = [super init]))
        return nil;

    _tileCaches = [NSMutableArray new];
    _tileCacheQueue = dispatch_queue_create("routeme.tileCacheQueue", DISPATCH_QUEUE_CONCURRENT);

    _memoryCache = nil;
    _expiryPeriod = period;
    
    _backgroundCacheDelegate = nil;
    _activeTileSource = nil;
    _backgroundFetchQueue = nil;

    id cacheCfg = [[RMConfiguration configuration] cacheConfiguration];
    if (!cacheCfg)
        cacheCfg = [NSArray arrayWithObjects:
                    [NSDictionary dictionaryWithObject: @"memory-cache" forKey: @"type"],
                    //[NSDictionary dictionaryWithObject: @"db-cache"     forKey: @"type"],
                    [NSDictionary dictionaryWithObject:@"file-cache"    forKey:@"type"],
                    nil];

    for (id cfg in cacheCfg)
    {
        id <RMTileCache> newCache = nil;

        @try {

            NSString *type = [cfg valueForKey:@"type"];

            if ([@"memory-cache" isEqualToString:type])
            {
                _memoryCache = [self memoryCacheWithConfig:cfg];
                continue;
            }

            //if ([@"db-cache" isEqualToString:type])
            //    newCache = [self databaseCacheWithConfig:cfg];
            
            if ([@"file-cache" isEqualToString:type])
                newCache = [self fileCacheWithConfig:cfg];

            if (newCache)
                [_tileCaches addObject:newCache];
            else
                RMLog(@"failed to create cache of type %@", type);

        }
        @catch (NSException * e) {
            RMLog(@"*** configuration error: %@", [e reason]);
        }
    }

    return self;
}

- (id)init
{
    if (!(self = [self initWithExpiryPeriod:0]))
        return nil;

    return self;
}

- (void)dealloc
{
    if (self.isBackgroundCaching)
        [self cancelBackgroundCache];
    
    dispatch_barrier_sync(_tileCacheQueue, ^{
         _memoryCache = nil;
         _tileCaches = nil;
    });
}

- (void)addCache:(id <RMTileCache>)cache
{
    dispatch_barrier_async(_tileCacheQueue, ^{
      [self->_tileCaches addObject:cache];
    });
}

- (void)insertCache:(id <RMTileCache>)cache atIndex:(NSUInteger)index
{
    dispatch_barrier_async(_tileCacheQueue, ^{
      if (index >= [self->_tileCaches count])
        [self->_tileCaches addObject:cache];
        else
          [self->_tileCaches insertObject:cache atIndex:index];
    });
}

- (NSArray *)tileCaches
{
    return [NSArray arrayWithArray:_tileCaches];
}

+ (NSNumber *)tileHash:(RMTile)tile
{
	return [NSNumber numberWithUnsignedLongLong:RMTileKey(tile)];
}

// Returns the cached image if it exists. nil otherwise.
- (UIImage *)cachedImage:(RMTile)tile withCacheKey:(NSString *)aCacheKey
{
    __block UIImage *image = [_memoryCache cachedImage:tile withCacheKey:aCacheKey];

    if (image)
        return image;

    dispatch_sync(_tileCacheQueue, ^{

        for (id <RMTileCache> cache in _tileCaches)
        {
            image = [cache cachedImage:tile withCacheKey:aCacheKey];

            if (image != nil)
            {
                [_memoryCache addImage:image forTile:tile withCacheKey:aCacheKey];
                break;
            }
        }

    });

	return image;
}

- (void)addImage:(UIImage *)image forTile:(RMTile)tile withCacheKey:(NSString *)aCacheKey
{
    if (!image || !aCacheKey)
        return;

    [_memoryCache addImage:image forTile:tile withCacheKey:aCacheKey];

    dispatch_sync(_tileCacheQueue, ^{

        for (id <RMTileCache> cache in _tileCaches)
        {	
            if ([cache respondsToSelector:@selector(addImage:forTile:withCacheKey:)])
                [cache addImage:image forTile:tile withCacheKey:aCacheKey];
        }

    });
}

- (void)didReceiveMemoryWarning
{
	LogMethod();

    [_memoryCache didReceiveMemoryWarning];

    dispatch_sync(_tileCacheQueue, ^{

        for (id<RMTileCache> cache in _tileCaches)
        {
            [cache didReceiveMemoryWarning];
        }

    });
    
    // LeadNav customization to throttle memory usage when a memory warning is received during background caching
    if (_backgroundFetchQueue && _backgroundFetchQueue.operationCount > 6) {
        RMLog(@"Suspending background caching for 10 sec.");
        
        _backgroundFetchQueue.suspended = YES;
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
          self->_backgroundFetchQueue.suspended = NO;
        });
    }
}

- (void)removeAllCachedImages
{
    [_memoryCache removeAllCachedImages];

    dispatch_sync(_tileCacheQueue, ^{

        for (id<RMTileCache> cache in _tileCaches)
        {
            [cache removeAllCachedImages];
        }

    });
}

- (void)removeAllCachedImagesForCacheKey:(NSString *)cacheKey
{
    [_memoryCache removeAllCachedImagesForCacheKey:cacheKey];

    dispatch_sync(_tileCacheQueue, ^{

        for (id<RMTileCache> cache in _tileCaches)
        {
            [cache removeAllCachedImagesForCacheKey:cacheKey];
        }
    });
}

// LeadNav customization to allow user-saved areas to be cached indefinitely
- (void)addArea:(NSDictionary *)area forCacheKey:(NSString *)cacheKey
{
    dispatch_sync(_tileCacheQueue, ^{
        
        for (id<RMTileCache> cache in _tileCaches)
        {
            [cache addArea:area forCacheKey:cacheKey];
        }
        
    });
}

// LeadNav customization to allow user-saved areas to be cached indefinitely
- (void)removeArea:(NSDictionary *)area forCacheKey:(NSString *)cacheKey
{
    dispatch_sync(_tileCacheQueue, ^{
        
        for (id<RMTileCache> cache in _tileCaches)
        {
            [cache removeArea:area forCacheKey:cacheKey];
        }
        
    });
}

// LeadNav customization to get all the tiles for an area
- (NSArray *)tilesForArea:(NSDictionary *)area
{
    __block NSArray *tiles = nil;
    
    dispatch_sync(_tileCacheQueue, ^{
        
        for (id<RMTileCache> cache in _tileCaches)
        {
            tiles = [cache tilesForArea:area];
        }
        
    });
    
    return tiles;
}

// LeadNav customization to count the number of tiles in an area
- (NSUInteger)countTilesInArea:(NSDictionary *)area
{
    int minCacheZoom = [[area objectForKey:@"minZoom"] intValue];
    int maxCacheZoom = [[area objectForKey:@"maxZoom"] intValue];
    float minCacheLat = [[area objectForKey:@"southWestLat"] floatValue];
    float maxCacheLat = [[area objectForKey:@"northEastLat"] floatValue];
    float minCacheLon = [[area objectForKey:@"southWestLong"] floatValue];
    float maxCacheLon = [[area objectForKey:@"northEastLong"] floatValue];
    
    if (minCacheLat > maxCacheLat || minCacheLon > maxCacheLon || minCacheZoom > maxCacheZoom) {
        return 0;
    }
    
    int n, xMin, yMax, xMax, yMin;
    
    int totalTiles = 0;
     
    for (int zoom = minCacheZoom; zoom <= maxCacheZoom; zoom++)
    {
        n = pow(2.0, zoom);
        xMin = floor(((minCacheLon + 180.0) / 360.0) * n);
        yMax = floor((1.0 - (logf(tanf(minCacheLat * M_PI / 180.0) + 1.0 / cosf(minCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);
        xMax = floor(((maxCacheLon + 180.0) / 360.0) * n);
        yMin = floor((1.0 - (logf(tanf(maxCacheLat * M_PI / 180.0) + 1.0 / cosf(maxCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);

        totalTiles += (xMax + 1 - xMin) * (yMax + 1 - yMin);
    }
    
    return totalTiles;
}

// LeadNav customization to estimate the cache size for an area
- (unsigned long long)estimateCacheSizeForArea:(NSDictionary *)area
{
    return [self countTilesInArea:area] * 5000; // The average size of a tile is ~5K
}

// LeadNav customization to get the cache size for a cache
- (unsigned long long)cacheSizeForCacheKey:(NSString *)cacheKey
{
    unsigned long long cacheSize = 0;
    
    for (id<RMTileCache> cache in _tileCaches)
    {
        cacheSize += [cache cacheSizeForCacheKey:cacheKey];
    }
    
    return cacheSize;
}

- (BOOL)isBackgroundCaching
{
    return (_activeTileSource || _backgroundFetchQueue);
}

- (void)beginBackgroundCacheForTileSource:(id <RMTileSource>)tileSource southWest:(CLLocationCoordinate2D)southWest northEast:(CLLocationCoordinate2D)northEast minZoom:(float)minZoom maxZoom:(float)maxZoom
{
    if (self.isBackgroundCaching)
        return;

    _activeTileSource = tileSource;
    
    _backgroundFetchQueue = [[NSOperationQueue alloc] init];
    [_backgroundFetchQueue setMaxConcurrentOperationCount:6];
    
    int   minCacheZoom = (int)minZoom;
    int   maxCacheZoom = (int)maxZoom;
    float minCacheLat  = southWest.latitude;
    float maxCacheLat  = northEast.latitude;
    float minCacheLon  = southWest.longitude;
    float maxCacheLon  = northEast.longitude;

    NSAssert(minCacheZoom <= maxCacheZoom, @"Minimum zoom should be less than or equal to maximum zoom");
    NSAssert(maxCacheLat  >  minCacheLat,  @"Northernmost bounds should exceed southernmost bounds");
    NSAssert(maxCacheLon  >  minCacheLon,  @"Easternmost bounds should exceed westernmost bounds");

    int n, xMin, yMax, xMax, yMin;

    int totalTiles = 0;

    for (int zoom = minCacheZoom; zoom <= maxCacheZoom; zoom++)
    {
        n = pow(2.0, zoom);
        xMin = floor(((minCacheLon + 180.0) / 360.0) * n);
        yMax = floor((1.0 - (logf(tanf(minCacheLat * M_PI / 180.0) + 1.0 / cosf(minCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);
        xMax = floor(((maxCacheLon + 180.0) / 360.0) * n);
        yMin = floor((1.0 - (logf(tanf(maxCacheLat * M_PI / 180.0) + 1.0 / cosf(maxCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);

        totalTiles += (xMax + 1 - xMin) * (yMax + 1 - yMin);
    }

    if ([_backgroundCacheDelegate respondsToSelector:@selector(tileCache:didBeginBackgroundCacheWithCount:forTileSource:)])
        [_backgroundCacheDelegate tileCache:self didBeginBackgroundCacheWithCount:totalTiles forTileSource:_activeTileSource];

    __block int progTile = 0;

    for (int zoom = minCacheZoom; zoom <= maxCacheZoom; zoom++)
    {
        n = pow(2.0, zoom);
        xMin = floor(((minCacheLon + 180.0) / 360.0) * n);
        yMax = floor((1.0 - (logf(tanf(minCacheLat * M_PI / 180.0) + 1.0 / cosf(minCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);
        xMax = floor(((maxCacheLon + 180.0) / 360.0) * n);
        yMin = floor((1.0 - (logf(tanf(maxCacheLat * M_PI / 180.0) + 1.0 / cosf(maxCacheLat * M_PI / 180.0)) / M_PI)) / 2.0 * n);

        for (int x = xMin; x <= xMax; x++)
        {
            for (int y = yMin; y <= yMax; y++)
            {
                RMTileCacheDownloadOperation *operation = [[RMTileCacheDownloadOperation alloc] initWithTile:RMTileMake(x, y, zoom)
                                                                                                forTileSource:_activeTileSource
                                                                                                   usingCache:self];

                __block RMTileCacheDownloadOperation *internalOperation = operation;

                [operation setCompletionBlock:^(void)
                {
                    dispatch_sync(dispatch_get_main_queue(), ^(void)
                    {
                        if ( ! [internalOperation isCancelled])
                        {
                            progTile++;

                          if ([self->_backgroundCacheDelegate respondsToSelector:@selector(tileCache:didBackgroundCacheTile:withIndex:ofTotalTileCount:)])
                            [self->_backgroundCacheDelegate tileCache:self didBackgroundCacheTile:RMTileMake(x, y, zoom) withIndex:progTile ofTotalTileCount:totalTiles];

                            if (progTile == totalTiles)
                            {
                              self->_backgroundFetchQueue = nil;

                              self->_activeTileSource = nil;

                              if ([self->_backgroundCacheDelegate respondsToSelector:@selector(tileCacheDidFinishBackgroundCache:)])
                                [self->_backgroundCacheDelegate tileCacheDidFinishBackgroundCache:self];
                            }
                        }

                        internalOperation = nil;
                    });
                }];

                [_backgroundFetchQueue addOperation:operation];
            }
        }
    };
}

- (void)cancelBackgroundCache
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
    {
        @synchronized (self)
        {
            BOOL didCancel = NO;

          if (self->_backgroundFetchQueue)
            {
              [self->_backgroundFetchQueue cancelAllOperations];
              [self->_backgroundFetchQueue waitUntilAllOperationsAreFinished];
              self->_backgroundFetchQueue = nil;

                didCancel = YES;
            }

          if (self->_activeTileSource)
            self->_activeTileSource = nil;

            if (didCancel)
            {
                dispatch_sync(dispatch_get_main_queue(), ^(void)
                {
                  if ([self->_backgroundCacheDelegate respondsToSelector:@selector(tileCacheDidCancelBackgroundCache:)])
                    [self->_backgroundCacheDelegate tileCacheDidCancelBackgroundCache:self];
                });
            }
        }
    });
}

@end

#pragma mark -

@implementation RMTileCache (Configuration)

static NSMutableDictionary *predicateValues = nil;

- (NSDictionary *)predicateValues
{
    static dispatch_once_t predicateValuesOnceToken;

    dispatch_once(&predicateValuesOnceToken, ^{
        struct utsname systemInfo;
        uname(&systemInfo);

        NSString *machine = [NSString stringWithCString:systemInfo.machine encoding:NSASCIIStringEncoding];

        predicateValues = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                           [[UIDevice currentDevice] model], @"model",
                           machine, @"machine",
                           [[UIDevice currentDevice] systemName], @"systemName",
                           [NSNumber numberWithFloat:[[[UIDevice currentDevice] systemVersion] floatValue]], @"systemVersion",
                           [NSNumber numberWithInt:[[UIDevice currentDevice] userInterfaceIdiom]], @"userInterfaceIdiom",
                           nil];

        if ( ! ([machine isEqualToString:@"i386"] || [machine isEqualToString:@"x86_64"]))
        {
            NSNumber *machineNumber = [NSNumber numberWithFloat:[[[machine stringByTrimmingCharactersInSet:[NSCharacterSet letterCharacterSet]] stringByReplacingOccurrencesOfString:@"," withString:@"."] floatValue]];

            if ( ! machineNumber)
                machineNumber = [NSNumber numberWithFloat:0.0];

            [predicateValues setObject:machineNumber forKey:@"machineNumber"];
        }
        else
        {
            [predicateValues setObject:[NSNumber numberWithFloat:0.0] forKey:@"machineNumber"];
        }

        // A predicate might be:
        // (self.model = 'iPad' and self.machineNumber >= 3) or (self.machine = 'x86_64')
        // See NSPredicate

//        NSLog(@"Predicate values:\n%@", [predicateValues description]);
    });

    return predicateValues;
}

- (id <RMTileCache>)memoryCacheWithConfig:(NSDictionary *)cfg
{
    NSUInteger capacity = 32;

	NSNumber *capacityNumber = [cfg objectForKey:@"capacity"];
	if (capacityNumber != nil)
        capacity = [capacityNumber unsignedIntegerValue];

    NSArray *predicates = [cfg objectForKey:@"predicates"];

    if (predicates)
    {
        NSDictionary *predicateValues = [self predicateValues];

        for (NSDictionary *predicateDescription in predicates)
        {
            NSString *predicate = [predicateDescription objectForKey:@"predicate"];
            if ( ! predicate)
                continue;

            if ( ! [[NSPredicate predicateWithFormat:predicate] evaluateWithObject:predicateValues])
                continue;

            capacityNumber = [predicateDescription objectForKey:@"capacity"];
            if (capacityNumber != nil)
                capacity = [capacityNumber unsignedIntegerValue];
        }
    }

    RMLog(@"Memory cache configuration: {capacity : %lu}", (unsigned long)capacity);

	return [[RMMemoryCache alloc] initWithCapacity:capacity];
}

- (id <RMTileCache>)databaseCacheWithConfig:(NSDictionary *)cfg
{
    BOOL useCacheDir = NO;
    RMCachePurgeStrategy strategy = RMCachePurgeStrategyFIFO;

    NSUInteger capacity = 1000;
    NSUInteger minimalPurge = capacity / 10;

    // Defaults

    NSNumber *capacityNumber = [cfg objectForKey:@"capacity"];

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad && [cfg objectForKey:@"capacity-ipad"])
    {
        NSLog(@"***** WARNING: deprecated config option capacity-ipad, use a predicate instead: -[%@ %@] (line %d)", self, NSStringFromSelector(_cmd), __LINE__);
        capacityNumber = [cfg objectForKey:@"capacity-ipad"];
    }

    NSString *strategyStr = [cfg objectForKey:@"strategy"];
    NSNumber *useCacheDirNumber = [cfg objectForKey:@"useCachesDirectory"];
    NSNumber *minimalPurgeNumber = [cfg objectForKey:@"minimalPurge"];
    NSNumber *expiryPeriodNumber = [cfg objectForKey:@"expiryPeriod"];

    NSArray *predicates = [cfg objectForKey:@"predicates"];

    if (predicates)
    {
        NSDictionary *predicateValues = [self predicateValues];

        for (NSDictionary *predicateDescription in predicates)
        {
            NSString *predicate = [predicateDescription objectForKey:@"predicate"];
            if ( ! predicate)
                continue;

            if ( ! [[NSPredicate predicateWithFormat:predicate] evaluateWithObject:predicateValues])
                continue;

            if ([predicateDescription objectForKey:@"capacity"])
                capacityNumber = [predicateDescription objectForKey:@"capacity"];
            if ([predicateDescription objectForKey:@"strategy"])
                strategyStr = [predicateDescription objectForKey:@"strategy"];
            if ([predicateDescription objectForKey:@"useCachesDirectory"])
                useCacheDirNumber = [predicateDescription objectForKey:@"useCachesDirectory"];
            if ([predicateDescription objectForKey:@"minimalPurge"])
                minimalPurgeNumber = [predicateDescription objectForKey:@"minimalPurge"];
            if ([predicateDescription objectForKey:@"expiryPeriod"])
                expiryPeriodNumber = [predicateDescription objectForKey:@"expiryPeriod"];
        }
    }

    // Check the values

    if (capacityNumber != nil)
    {
        NSInteger value = [capacityNumber intValue];

        // 0 is valid: it means no capacity limit
        if (value >= 0)
        {
            capacity =  value;
            minimalPurge = MAX(1,capacity / 10);
        }
        else
        {
            RMLog(@"illegal value for capacity: %ld", (long)value);
        }
    }

    if (strategyStr != nil)
    {
        if ([strategyStr caseInsensitiveCompare:@"FIFO"] == NSOrderedSame) strategy = RMCachePurgeStrategyFIFO;
        if ([strategyStr caseInsensitiveCompare:@"LRU"] == NSOrderedSame) strategy = RMCachePurgeStrategyLRU;
    }
    else
    {
        strategyStr = @"FIFO";
    }

    if (useCacheDirNumber != nil)
        useCacheDir = [useCacheDirNumber boolValue];

    if (minimalPurgeNumber != nil && capacity != 0)
    {
        NSUInteger value = [minimalPurgeNumber unsignedIntValue];

        if (value > 0 && value<=capacity)
            minimalPurge = value;
        else
            RMLog(@"minimalPurge must be at least one and at most the cache capacity");
    }

    if (expiryPeriodNumber != nil)
        _expiryPeriod = [expiryPeriodNumber doubleValue];

    RMLog(@"Database cache configuration: {capacity : %lu, strategy : %@, minimalPurge : %lu, expiryPeriod: %.0f, useCacheDir : %@}", (unsigned long)capacity, strategyStr, (unsigned long)minimalPurge, _expiryPeriod, useCacheDir ? @"YES" : @"NO");

    RMDatabaseCache *dbCache = [[RMDatabaseCache alloc] initUsingCacheDir:useCacheDir];
    [dbCache setCapacity:capacity];
    [dbCache setPurgeStrategy:strategy];
    [dbCache setMinimalPurge:minimalPurge];
    [dbCache setExpiryPeriod:_expiryPeriod];

    return dbCache;
}

- (id <RMTileCache>)fileCacheWithConfig:(NSDictionary *)cfg
{
    NSString *appSupportDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *cacheDir = [NSString pathWithComponents:@[ appSupportDir, @"Cache" ]];
    NSUInteger capacity = 3000; // 1000
    NSTimeInterval expiryPeriod = 0;
    
    NSNumber *capacityNumber = [cfg objectForKey:@"capacity"];
    
    if (capacityNumber) {
        capacity = capacityNumber.unsignedIntegerValue;
    }
    
    NSNumber *expiryPeriodNumber = [cfg objectForKey:@"expiryPeriod"];
    
    if (expiryPeriodNumber) {
        expiryPeriod = expiryPeriodNumber.doubleValue;
    }
    
    RMLog(@"File cache configuration: {cacheDir : %@, capacity : %lu, expiryPeriod : %.0f}", cacheDir, (unsigned long)capacity, expiryPeriod);
    
    RMFileCache *fileCache = [RMFileCache cacheWithCacheDir:cacheDir];
    fileCache.tileCache = self;
    fileCache.capacity = capacity;
    fileCache.expiryPeriod = expiryPeriod;
    
    return fileCache;
}

@end
