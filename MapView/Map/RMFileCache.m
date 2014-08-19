//
//  RMFileCache.m
//  MapView
//
//  Created by Nathan Giordano on 8/18/14.
//
//

#import "RMFileCache.h"

@interface RMFileCache ()

@property (strong, nonatomic) NSTimer *cachePurgeTimer;
@property (strong, nonatomic) NSString *cacheDir;
@property (nonatomic, assign) BOOL isUpdatingAreaData;
@property (nonatomic, assign) BOOL isPurgingCache;

@end

@implementation RMFileCache

#pragma mark - Initialization

- (id)init
{
    self = [super init];
    
    if (self) {
        NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        
        self.cacheDir = [NSString pathWithComponents:@[ documentsDirectory, @"Cache" ]];
        
        [self initialize];
    }
    
    return self;
}

- (id)initWithCacheDir:(NSString *)cacheDir
{
    self = [super init];
    
    if (self) {
        self.cacheDir = cacheDir;
        
        [self initialize];
    }
    
    return self;
}

- (void)initialize
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    
    if (![fileManager fileExistsAtPath:self.cacheDir]) {
        RMLog(@"Creating cache directory %@", self.cacheDir);
        
        if (![fileManager createDirectoryAtPath:self.cacheDir withIntermediateDirectories:YES attributes:nil error:&error]) {
            RMLog(@"Error creating cache directory %@: %@", self.cacheDir, error.localizedDescription);
        }
    }
    
    // Exclude the cache directory from backup
    if ([fileManager fileExistsAtPath:self.cacheDir]) {
        NSURL *cacheURL = [NSURL fileURLWithPath:self.cacheDir];
        
        if (![cacheURL setResourceValue:[NSNumber numberWithBool:YES] forKey:NSURLIsExcludedFromBackupKey error:&error]) {
            RMLog(@"Error excluding %@ from backup: %@", self.cacheDir, error.localizedDescription);
        }
    }
    
    self.expiryPeriod = 3600; // Default to one hour
    self.cachePurgeTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self selector:@selector(purgeCache) userInfo:nil repeats:YES];
    self.isUpdatingAreaData = NO;
    self.isPurgingCache = NO;
}

- (void)dealloc
{
    if (self.cachePurgeTimer) {
        [self.cachePurgeTimer invalidate];
        self.cachePurgeTimer = nil;
    }
}

#pragma mark - RM tile cache protocol (required)

- (UIImage *)cachedImage:(RMTile)tile withCacheKey:(NSString *)cacheKey
{
    UIImage *cachedImage = nil;
    NSString *zoom = @(tile.zoom).stringValue;
    NSString *x = @(tile.x).stringValue;
    NSString *y = @(tile.y).stringValue;
    NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, zoom, x, y ]];
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingUncached error:&error];
    
    if (data) {
        cachedImage = [UIImage imageWithData:data];
    }
    
    //if (error) {
    //    RMLog(@"Error reading cached image for tile %d %d %d: %@", tile.zoom, tile.x, tile.y, error.localizedDescription);
    //}
    
    return cachedImage;
}

- (void)didReceiveMemoryWarning
{
    // Nothing to do here
}

#pragma mark - RM tile cache protocol (optional)

- (void)addImage:(UIImage *)image forTile:(RMTile)tile withCacheKey:(NSString *)cacheKey
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSString *zoom = @(tile.zoom).stringValue;
    NSString *x = @(tile.x).stringValue;
    NSString *y = @(tile.y).stringValue;
    NSString *dir = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, zoom, x ]];
    NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, zoom, x, y ]];
    
    // If the image exists in the cache, update the modification date
    if ([fileManager fileExistsAtPath:path]) {
        NSMutableDictionary *attributes = [[fileManager attributesOfItemAtPath:path error:nil] mutableCopy];
        
        if (attributes) {
            [attributes setObject:[NSDate date] forKey:NSFileModificationDate];
            
            [fileManager setAttributes:attributes ofItemAtPath:path error:nil];
        }
        
        return;
    }
    
    // If the image directory doesn't exist, create the path
    if (![fileManager fileExistsAtPath:dir]) {
        if (![fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error]) {
            if (error.code != NSFileWriteFileExistsError) {
                RMLog(@"Error creating cache directory %@: %@", dir, error.localizedDescription);
                
                return;
            }
        }
    }
    
    // Write the image data to the cache
    NSData *data = UIImagePNGRepresentation(image);
    
    if (data) {
        [data writeToFile:path options:NSDataWritingAtomic error:&error];
        
        if (error) {
            RMLog(@"Error writing image for tile %d %d %d: %@", tile.zoom, tile.x, tile.y, error.localizedDescription);
        }
    }
}

- (void)removeAllCachedImages
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:self.cacheDir error:&error];
    
    if (error) {
        RMLog(@"Error removing cached images: %@", error.localizedDescription);
        
        return;
    }
    
    for (NSString *cacheKey in contents) {
        NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey ]];
        
        if (![fileManager removeItemAtPath:path error:&error]) {
            RMLog(@"Error removing cached images in %@: %@", cacheKey, error.localizedDescription);
        }
    }
}

- (void)removeAllCachedImagesForCacheKey:(NSString *)cacheKey
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error;
    NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey ]];
    
    if (![fileManager fileExistsAtPath:path]) {
        return;
    }
    
    if (![fileManager removeItemAtPath:path error:&error]) {
        RMLog(@"Error removing cached images for cache key %@: %@", cacheKey, error.localizedDescription);
    }
}

// LeadNav customization to allow user-saved areas to be cached indefinitely
- (void)addArea:(NSDictionary *)area forCacheKey:(NSString *)cacheKey
{
    self.isUpdatingAreaData = YES;
    
    NSMutableDictionary *areaData = [[self loadAreaDataForCacheKey:cacheKey] mutableCopy];
    NSArray *tiles = [self tilesForArea:area];
    
    for (NSValue *tileObject in tiles) {
        RMTile tile;
        
        [tileObject getValue:&tile];
        
        NSString *zoom = @(tile.zoom).stringValue;
        NSString *x = @(tile.x).stringValue;
        NSString *y = @(tile.y).stringValue;
        NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, zoom, x, y ]];
        NSNumber *areaCount = [areaData objectForKey:path];
        int _areaCount = (areaCount == nil) ? 0 : areaCount.intValue;
        
        _areaCount++;
        
        areaCount = [NSNumber numberWithInt:_areaCount];
        
        [areaData setObject:areaCount forKey:path];
    }
    
    [self saveAreaData:areaData forCacheKey:cacheKey];
    
    self.isUpdatingAreaData = NO;
}

// LeadNav customization to allow user-saved areas to be cached indefinitely
- (void)removeArea:(NSDictionary *)area forCacheKey:(NSString *)cacheKey
{
    self.isUpdatingAreaData = YES;
    
    NSMutableDictionary *areaData = [[self loadAreaDataForCacheKey:cacheKey] mutableCopy];
    NSArray *tiles = [self tilesForArea:area];
    
    for (NSValue *tileObject in tiles) {
        RMTile tile;
        
        [tileObject getValue:&tile];
        
        NSString *zoom = @(tile.zoom).stringValue;
        NSString *x = @(tile.x).stringValue;
        NSString *y = @(tile.y).stringValue;
        NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, zoom, x, y ]];
        NSNumber *areaCount = [areaData objectForKey:path];
        
        if (areaCount == nil) {
            continue;
        }
        
        int _areaCount = areaCount.intValue;
        
        _areaCount--;
        
        if (_areaCount < 1) {
            [areaData removeObjectForKey:path];
        } else {
            areaCount = [NSNumber numberWithInt:_areaCount];
            
            [areaData setObject:areaCount forKey:path];
        }
    }
    
    [self saveAreaData:areaData forCacheKey:cacheKey];
    
    self.isUpdatingAreaData = NO;
}

// LeadNav customization to get all the tiles for an area
- (NSArray *)tilesForArea:(NSDictionary *)area
{
    NSMutableArray *tiles = [NSMutableArray new];
    int minCacheZoom = [[area objectForKey:@"minZoom"] intValue];
    int maxCacheZoom = [[area objectForKey:@"maxZoom"] intValue];
    float minCacheLat = [[area objectForKey:@"southWestLat"] floatValue];
    float maxCacheLat = [[area objectForKey:@"northEastLat"] floatValue];
    float minCacheLon = [[area objectForKey:@"southWestLong"] floatValue];
    float maxCacheLon = [[area objectForKey:@"northEastLong"] floatValue];
    
    if (minCacheLat > maxCacheLat || minCacheLon > maxCacheLon || minCacheZoom > maxCacheZoom) {
        return [tiles copy];
    }
    
    int n, xMin, yMax, xMax, yMin;
    
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
                RMTile tile = RMTileMake(x, y, zoom);
                
                [tiles addObject:[NSValue valueWithBytes:&tile objCType:@encode(RMTile)]];
            }
        }
    };
    
    return [tiles copy];
}

// LeadNav customization to count the number of tiles in an area
- (NSUInteger)countTilesInArea:(NSDictionary *)area
{
    return 0;
}

// LeadNav customization to estimate the cache size for an area
- (unsigned long long)estimateCacheSizeForArea:(NSDictionary *)area
{
    return 0;
}

// LeadNav customization to get the cache size for a cache
- (unsigned long long)cacheSizeForCacheKey:(NSString *)cacheKey
{
    return 0;
}

#pragma mark - Private methods

- (void)purgeCache
{
    if (self.isPurgingCache || self.isUpdatingAreaData) {
        return;
    }
    
    self.isPurgingCache = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RMLog(@"Purging images from the cache.");
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error;
        NSDate *expiryPeriod = [NSDate dateWithTimeIntervalSinceNow:(self.expiryPeriod * -1)];
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:self.cacheDir error:&error];
        
        if (error) {
            RMLog(@"Error purging cache: %@", error.localizedDescription);
            
            self.isPurgingCache = NO;
            
            return;
        }
        
        for (NSString *cacheKey in contents) {
            NSDictionary *areaData = [self loadAreaDataForCacheKey:cacheKey];
            NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey ]];
            NSURL *cacheURL = [[NSURL alloc] initFileURLWithPath:path];
            NSDirectoryEnumerator *cacheDirectoryEnumerator = [fileManager enumeratorAtURL:cacheURL
                                                                includingPropertiesForKeys:@[ NSURLContentModificationDateKey, NSURLIsDirectoryKey ]
                                                                                   options:0
                                                                              errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
            
            for (NSURL *cachedImageURL in cacheDirectoryEnumerator) {
                if (self.isUpdatingAreaData) {
                    RMLog(@"Aborting purge for area data update.");
                    
                    self.isPurgingCache = NO;
                    
                    return;
                }
                
                if ([cachedImageURL.lastPathComponent isEqualToString:@"area-data"]) {
                    continue;
                }
                
                if ([areaData objectForKey:cachedImageURL.path] != nil) {
                    continue;
                }
                
                NSDate *contentModificationDate;
                NSNumber *isDirectory;
                
                [cachedImageURL getResourceValue:&contentModificationDate forKey:NSURLContentModificationDateKey error:NULL];
                [cachedImageURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
                
                if (![isDirectory boolValue] && [contentModificationDate compare:expiryPeriod] == NSOrderedAscending) {
                    [fileManager removeItemAtURL:cachedImageURL error:&error];
                    
                    if (error) {
                        RMLog(@"Error purging image %@ from cache: %@", cachedImageURL.lastPathComponent, error.localizedDescription);
                    }
                }
            }
        }
        
        self.isPurgingCache = NO;
    });
}

- (NSDictionary *)loadAreaDataForCacheKey:(NSString *)cacheKey
{
    NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, @"area-data" ]];
    NSDictionary *areaData = nil;
    
    @try {
        areaData = (NSDictionary *)[NSKeyedUnarchiver unarchiveObjectWithFile:path];
    }
    @catch (NSException *exception) {
        RMLog(@"Area data for cache key %@ is corrupted. Removing the area data file.", cacheKey);
        
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:path error:nil];
    }
    
    if (!areaData) {
        areaData = [NSDictionary new];
    }
    
    return areaData;
}

- (void)saveAreaData:(NSDictionary *)areaData forCacheKey:(NSString *)cacheKey
{
    NSString *path = [NSString pathWithComponents:@[ self.cacheDir, cacheKey, @"area-data" ]];
    
    if (!areaData) {
        areaData = [NSDictionary new];
    }
    
    if (![NSKeyedArchiver archiveRootObject:areaData toFile:path]) {
        RMLog(@"Error writing area data for cache key %@", cacheKey);
    }
}

@end
