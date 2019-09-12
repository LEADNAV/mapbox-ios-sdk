//
//  RMURLMapSource.m
//  MapView
//
//  Created by Nathan Giordano on 7/11/14.
//
//

#import "RMURLMapSource.h"

@implementation RMURLMapSource
{
    NSString *_URLTemplate;
    NSString *_uniqueTilecacheKey;
}

- (id)initWithURLTemplate:(NSString *)URLTemplate tileCacheKey:(NSString *)tileCacheKey minZoom:(float)minZoom maxZoom:(float)maxZoom
{
    self = [super init];
    
    if (!self)
        return nil;
    
    NSAssert(URLTemplate != nil, @"Empty URLTemplate parameter not allowed");
    NSAssert(tileCacheKey != nil, @"Empty tileCacheKey parameter not allowed");
    
    _URLTemplate = URLTemplate;
    _uniqueTilecacheKey = tileCacheKey;
    
    self.minZoom = minZoom;
    self.maxZoom = maxZoom;
    self.LNMapSource = kMapSourceURL;
    
    return self;
}

- (NSURL *)URLForTile:(RMTile)tile
{
    NSAssert4(((tile.zoom >= self.minZoom) && (tile.zoom <= self.maxZoom)),
              @"%@ tried to retrieve tile with zoomLevel %d, outside source's defined range %f to %f",
              self, tile.zoom, self.minZoom, self.maxZoom);
    
    NSString *URLString = [_URLTemplate stringByReplacingOccurrencesOfString:@"@x" withString:[NSString stringWithFormat:@"%d", tile.x]];
    URLString = [URLString stringByReplacingOccurrencesOfString:@"@y" withString:[NSString stringWithFormat:@"%d", tile.y]];
    URLString = [URLString stringByReplacingOccurrencesOfString:@"@z" withString:[NSString stringWithFormat:@"%d", tile.zoom]];
    
    return [NSURL URLWithString:URLString];
}

- (NSString *)uniqueTilecacheKey
{
    return _uniqueTilecacheKey;
}

- (NSString *)shortName
{
	return @"URL Map Source";
}

- (NSString *)longDescription
{
	return @"URL Map Source";
}

- (NSString *)shortAttribution
{
	return @"n/a";
}

- (NSString *)longAttribution
{
	return @"n/a";
}

@end
