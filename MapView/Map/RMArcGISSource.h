//
//#import "RMAbstractWebMapSource.h"
//
//#define kMapboxDefaultTileSize 256
//#define kMapboxDefaultMinTileZoom 0
//#define kMapboxDefaultMaxTileZoom 18
//#define kMapboxDefaultLatLonBoundingBox ((RMSphericalTrapezium){ .northEast = { .latitude =  90, .longitude =  180 }, \
//                                                                 .southWest = { .latitude = -90, .longitude = -180 } })
//
//#define kMapboxPlaceholderMapID @"examples.map-z2effxa8"
//
////// constants for the image quality API (see http://mapbox.com/developers/api/#image_quality)
////typedef enum : NSUInteger {
////    RMMapboxSourceQualityFull   = 0, // default
////    RMMapboxSourceQualityPNG32  = 1, // 32 color indexed PNG
////    RMMapboxSourceQualityPNG64  = 2, // 64 color indexed PNG
////    RMMapboxSourceQualityPNG128 = 3, // 128 color indexed PNG
////    RMMapboxSourceQualityPNG256 = 4, // 256 color indexed PNG
////    RMMapboxSourceQualityJPEG70 = 5, // 70% quality JPEG
////    RMMapboxSourceQualityJPEG80 = 6, // 80% quality JPEG
////    RMMapboxSourceQualityJPEG90 = 7  // 90% quality JPEG
////} RMMapboxSourceQuality;
//
//@class RMMapView;
//
///** An RMMapboxSource is used to display map tiles from a network-based map hosted on [Mapbox](http://mapbox.com/plans) or the open source [TileStream](https://github.com/mapbox/tilestream) software. Maps are referenced by their Mapbox map ID or by a file or URL containing [TileJSON](http://mapbox.com/developers/tilejson/). */
////@interface RMArcGISSource : RMAbstractWebMapSource
//
///** @name Creating Tile Sources */
//
///** Initialize a tile source using the Mapbox map ID.
//*
//*   This method requires a network connection in order to download the TileJSON used to define the tile source. 
//*
//*   @param mapID The Mapbox map ID string, typically in the format `<username>.map-<random characters>`.
//*   @return An initialized Mapbox tile source. */
//- (id)initWithMapID:(NSString *)mapID;
//
///** Initialize a tile source using the Mapbox map ID, optionally enabling SSL.
//*
//*   This method requires a network connection in order to download the TileJSON used to define the tile source.
//*
//*   @param mapID The Mapbox map ID string, typically in the format `<username>.map-<random characters>`.
//*   @param enableSSL Whether to use SSL-enabled HTTPS connections for map tiles and other related data. Defaults to `NO`. At some point in the future, this will default to `YES`. 
//*   @return An initialized Mapbox tile source. */
//- (id)initWithMapID:(NSString *)mapID enablingSSL:(BOOL)enableSSL;
//
///** Initialize a tile source with either a remote or local TileJSON structure.
//*
//*   Passing a remote URL requires a network connection. If offline functionality is desired, you should cache the TileJSON locally at a prior date, then pass a file path URL to this method.
//*
//*   @see tileJSON
//*
//*   @param referenceURL A remote or file path URL pointing to a TileJSON structure.
//*   @return An initialized Mapbox tile source. */
//- (id)initWithReferenceURL:(NSURL *)referenceURL;
//
///** Initialize a tile source with TileJSON.
//*   @param tileJSON A string containing TileJSON. 
//*   @return An initialized Mapbox tile source. */
//- (id)initWithTileJSON:(NSString *)tileJSON;
//
///** For TileJSON 2.1.0+ layers, initialize a tile source and automatically find and add annotations from [simplestyle](http://mapbox.com/developers/simplestyle/) data.
//*
//*   This method requires a network connection in order to download the TileJSON used to define the tile source.
//*
//*   @param mapID The Mapbox map ID string, typically in the format `<username>.map-<random characters>`.
//*   @param mapView A map view on which to display the annotations.
//*   @return An initialized Mapbox tile source. */
//- (id)initWithMapID:(NSString *)mapID enablingDataOnMapView:(RMMapView *)mapView;
//
///** For TileJSON 2.1.0+ layers, initialize a tile source and automatically find and add annotations from [simplestyle](http://mapbox.com/developers/simplestyle/) data, optionally enabling SSL.
//*
//*   This method requires a network connection in order to download the TileJSON used to define the tile source.
//*
//*   @param mapID The Mapbox map ID string, typically in the format `<username>.map-<random characters>`.
//*   @param mapView A map view on which to display the annotations.
//*   @param enableSSL Whether to use SSL-enabled HTTPS connections for map tiles and other related data. Defaults to `NO`. At some point in the future, this will default to `YES`.
//*   @return An initialized Mapbox tile source. */
//- (id)initWithMapID:(NSString *)mapID enablingDataOnMapView:(RMMapView *)mapView enablingSSL:(BOOL)enableSSL;
//
///** For TileJSON 2.1.0+ layers, initialize a tile source and automatically find and add annotations from [simplestyle](http://mapbox.com/developers/simplestyle/) data.
//*   @param tileJSON A string containing TileJSON.
//*   @param mapView A map view on which to display the annotations. 
//*   @return An initialized Mapbox tile source. */
//- (id)initWithTileJSON:(NSString *)tileJSON enablingDataOnMapView:(RMMapView *)mapView;
//
///** For TileJSON 2.1.0+ layers, initialize a tile source and automatically find and add annotations from [simplestyle](http://mapbox.com/developers/simplestyle/) data.
//*
//*   Passing a remote URL requires a network connection. If offline functionality is desired, you should cache the TileJSON locally at a prior date, then pass a file path URL to this method.
//*
//*   @see tileJSON
//*
//*   @param referenceURL A remote or file path URL pointing to a TileJSON structure.
//*   @param mapView A map view on which to display the annotations.
//*   @return An initialized Mapbox tile source. */
//- (id)initWithReferenceURL:(NSURL *)referenceURL enablingDataOnMapView:(RMMapView *)mapView;
//
///** @name Querying Tile Source Information */
//
///** Any available HTML-formatted map legend data for the tile source, suitable for display in a `UIWebView`. */
//- (NSString *)legend;
//
///** A suggested starting center coordinate for the map layer. */
//- (CLLocationCoordinate2D)centerCoordinate;
//
///** A suggested starting center zoom level for the map layer. */
//- (float)centerZoom;
//
///** Returns `YES` if the tile source provides full-world coverage; otherwise, returns `NO`. */
//- (BOOL)coversFullWorld;
//
///** The TileJSON for the map layer. Useful for saving locally to use in instantiating a tile source while offline. */
//@property (nonatomic, readonly, strong) NSString *tileJSON;
//
///** The TileJSON URL for the map layer. Useful for retrieving TileJSON to save locally to use in instantiating a tile source while offline. */
//@property (nonatomic, readonly, strong) NSURL *tileJSONURL;
//
///** The TileJSON data in dictionary format. Useful for retrieving info about the layer without having to parse TileJSON. */
//@property (nonatomic, readonly, strong) NSDictionary *infoDictionary;
//
/////** @name Configuring Map Options */
////
/////** Image quality that is retrieved from the network. Useful for lower-bandwidth environments. The default is to provide full-quality imagery. 
////*
////*   Note that you may want to clear the tile cache after changing this value in order to provide a consistent experience. */
////@property (nonatomic, assign) RMMapboxSourceQuality imageQuality;
//
//#if OS_OBJECT_USE_OBJC
//@property (nonatomic, readonly, strong) dispatch_queue_t dataQueue;
//#else
//@property (nonatomic, readonly, assign) dispatch_queue_t dataQueue;
//#endif
//
//@end
