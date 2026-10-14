#!/bin/sh
# Satellite backgrounds for the three map boxes from the USGS National Map (public domain).
# Sizes match the app's equirectangular boxes (height = lat span / lon span * width * 1.262).
B="https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/export"
get() { curl -s -o "res/sat-$1.jpg" "$B?bbox=$2&bboxSR=4326&imageSR=4326&size=$3&format=jpg&f=image"; }
get caltrain -122.56,36.97,-121.52,37.84 1400,1478
get bart     -122.56,37.44,-121.66,38.06 1400,1217
get muni     -122.525,37.70,-122.365,37.815 1000,907
# Offshore no-data comes back white; fill it with sea color (see the seafill step in the session notes) before shipping.
