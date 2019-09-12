//
//  OpenCycleMapSource.m
//
// Copyright (c) 2008-2013, Route-Me Contributors
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

#import "RMUSGSTopoSource.h"

@implementation RMUSGSTopoSource

- (id)init
{
	if (!(self = [super init]))
        return nil;

    self.minZoom = 1;
    self.maxZoom = 15;
    self.LNMapSource = kMapSourceUSGSTopo;

	return self;
} 

- (NSURL *)URLForTile:(RMTile)tile
{
	NSAssert4(((tile.zoom >= self.minZoom) && (tile.zoom <= self.maxZoom)),
			  @"%@ tried to retrieve tile with zoomLevel %d, outside source's defined range %f to %f", 
			  self, tile.zoom, self.minZoom, self.maxZoom);
 
 NSLog(@"Zoom for tile: %d", tile.zoom);

	return [NSURL URLWithString:[NSString stringWithFormat:@"https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/%d/%d/%d", tile.zoom, tile.y, tile.x]];
}

- (NSString *)uniqueTilecacheKey
{
	return @"USGSTopo";
}

- (NSString *)shortName
{
	return @"USGS Topo";
}

- (NSString *)longDescription
{
	return @"Map services and data available from U.S. Geological Survey, National Geospatial Program.";
}

- (NSString *)shortAttribution
{
	return @"U.S. Geological Survey, National Geospatial Program";
}

- (NSString *)longAttribution
{
	return @"Map services and data available from U.S. Geological Survey, National Geospatial Program.";
}

@end
