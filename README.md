This repository currently contains just one function, rivmatch(). It was designed using ChatGPT 4o mini.

**rivmatch()**

**Description:**

**rivmatch()** is a function for cleaning messy river and stream data. Point data is often collected to represent sampling sites (fish surveys, water quality collection, etc), but often the GPS locations do not align with digitized stream layers from NHD or similar line-type GIS files. This function uses the sf (simple features) package for spatial data.
This function looks for matches (case insensitive) between stream name columns in sf objects of point data and corresponding stream layers (such as NHD) and identifies TRUE matches (nearest stream layer corresponds to the point layer name; >90% match), MAYBE matches (nearest stream layer and point layer names are partial matches; 70-90% match), and FALSE matches (point and stream layer names do not match). Points whose nearest stream does not have the same name (FALSE match) then search within the searchdist (set by the user) for a TRUE match. All TRUE matches are then snapped to the stream layer. The output is a new sf object with a column describing the match (TRUE, MAYBE, or FALSE), updated geometries (location data) for TRUE matches, and the distance to the nearest stream (nearest match for TRUE matches).

**Arguments**

sf1, sf2, column_name, searchdist
sf1          simple features object for point data
sf2          simple features object for stream lines, needs same projection (EPSG) as sf1
column_name  column in both sf1 and sf2 corresponding to stream name (must have same name)
searchdist   distance (in units of sf object projection) that non-matches search for a TRUE match. 

**Example**

Example in which fish collection data represented by a sf points object called 'fish_points' needs to be snapped to the corresponding national hydrography dataset stream line represented by a sf line object called 'nhd_lines'. Both sf objects share the column name "GNIS_NAME" containing the stream's name. The search distance ('searchdist') is 200 meters if the nearest stream line to the fish point does not match (assuming the spatial projection uses meters).

snapped_points -> rivmatch(fish_points, nhd_lines, column_name="GNIS_NAME", searchdist=200) 
print(snapped_points)





**est.month.mean()**
**Description:**

**est.month.mean()** is a function for taking an sf points object of instantaneous stream temperature readings and estimating the mean August temperature at those locations. It searches for USGS NWIS locations within a set 'searchdist' of each instantaneous reading and, if found, creates a mean August temperature estimate based on the relationship between the instantaneous and continuous locations' data. See https://github.com/niallgclancy/StreamTempConversion for proof-of-concept analysis.

**Arguments**

instantaneous_sf, searchdist
instantaneous_sf          simple features object for point data with the following column names (req'd): Month (integer), Day (integer), Year (integer), Time (military format), inst.temp (degrees celsius).
searchdist   distance (in units of sf object projection) to search for a USGS NWIS continuous stream temperature logger. 




**Note**

If you are not familiar with the simple feature (sf) package, it is very easy to use. Shapefiles for both points and lines can easily be loaded into R as sf objects.
