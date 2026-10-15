# Next Train

Caltrain, BART and Muni for iPod touch 4. Bundled Caltrain timetable, live times from 511 and BART, a trip planner you can type a sentence into, a vector map of the Bay with the Caltrain, BART and Muni Metro lines, and a Laya verdict on whether to run for it.

## Layout

- `tools/compact_gtfs.py` turns the public Caltrain GTFS feed into `res/caltrain.json`. Rerun it when the timetable changes.
- `tools/bay_polygons.py` stitches OpenStreetMap coastline ways (Overpass, `natural=coastline`) into closed water polygons for `res/bay.json`. Map data © OpenStreetMap contributors, ODbL.
- `tools/compact_shapes.py` pulls the Caltrain track and one shape per BART color into `res/track.json` and `res/bart_map.json`; `tools/compact_muni_metro.py` builds `res/muni_metro.json` (J K L M N T stops and shapes) from the SFMTA GTFS via 511.
- `src/CTMap` draws all of that in one view that re-renders sharp at the end of each pinch (1x to 3x); tapping a station pushes its board. Three styles: Standard (the old tile palette), Satellite (`res/sat-*.jpg`: Caltrain and BART from Sentinel-2 cloudless 2016 by EOX, s2maps.eu, CC BY 4.0, contains modified Copernicus Sentinel data 2016, built by `tools/fetch_s2.py`; Muni from the USGS National Map, public domain, `tools/fetch_imagery.sh`) and Night.
- `res/Settings.bundle` puts the OpenRelay key, 511 token and map style in the Settings app.
- `res/bart.json` is the BART station list, `res/muni_stops.json` the Muni stop names from 511.
- `src/CTData` is the timetable engine, `CTLive` the 511 client, `CTAgencies` the BART and Muni clients, `CTAI` the OpenRelay and Laya calls.
- Real-time needs a free token from 511.org; 60 requests per hour. BART needs nothing.

A fan project, not affiliated with Caltrain, BART, SFMTA or MTC. The agency marks identify the services.

## Building

Targets iOS 4.3 on armv7 from a modern Mac with only the Command Line Tools installed. No Xcode.

1. Get the iPhoneOS 4.3 SDK from [EachAndOther/Legacy-iOS-SDKs](https://github.com/EachAndOther/Legacy-iOS-SDKs) into `~/ios4sdk/iPhoneOS4.3.sdk`.
2. The modern linker refuses the old dylibs, so convert them to text stubs once: run `tapi stubify` from the Command Line Tools over the SDK's frameworks and retarget the `-darwin` platform strings to `-ios`.
3. `./build.sh` compiles with `clang -target armv7-apple-ios4.3 -fobjc-runtime=ios-4.3 -fno-objc-arc -marm`, pseudo-signs with `ldid -S`, and zips an IPA into `build/`. ARM mode matters: modern ld drops the Thumb bit on Objective-C method pointers for this target and the app crashes at launch without it.
4. Install on a jailbroken device with AppSync: `ideviceinstaller install build/<App>.ipa`.

Everything is hand-written Foundation and UIKit from 2011. The JSON parser is in `src/ORJSON.m` because iOS 4 has no NSJSONSerialization.

## License

MIT for the code. Third-party marks and data belong to their owners.
