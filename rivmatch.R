# Function to compare values in two columns across spatial objects, in particular point data to a nearby stream
# created with the aid of ChatGPT
rivmatch <- function(sf1, sf2, column_name, searchdist) {
  library(sf)         # For handling spatial objects
  library(stringdist) # For calculating string similarity
  library(units)      # For handling distances
  
  # Check if the column exists in both spatial objects
  if (!(column_name %in% colnames(sf1))) {
    stop(paste("Column", column_name, "not found in the first spatial object."))
  }
  if (!(column_name %in% colnames(sf2))) {
    stop(paste("Column", column_name, "not found in the second spatial object."))
  }
  
  # Extract the columns and make them lowercase for case-insensitive comparison
  col1 <- tolower(sf1[[column_name]])
  col2 <- tolower(sf2[[column_name]])
  
  # Find the nearest feature in sf2 for each feature in sf1
  nearest_indices <- st_nearest_feature(sf1, sf2)
  
  # Calculate distances between each feature in sf1 and its nearest feature in sf2
  distances <- st_distance(sf1, sf2[nearest_indices, ], by_element = TRUE)
  
  # Calculate similarity and categorize matches
  match_result <- sapply(1:length(col1), function(i) {
    similarity <- 1 - stringdist::stringdist(col1[i], col2[nearest_indices[i]], method = "lv") / max(nchar(col1[i]), nchar(col2[nearest_indices[i]]))
    if (similarity >= 0.9) {
      "TRUE"
    } else if (similarity >= 0.7) {  # Updated threshold for MAYBE to 70%-90%
      "MAYBE"
    } else {
      "FALSE"
    }
  })
  
  # Create result object to store modified geometry
  result <- sf1
  
  # Snap TRUE matches to the nearest feature
  for (i in which(match_result == "TRUE")) {
    snapped_geometry <- st_nearest_points(sf1[i, ], sf2[nearest_indices[i], ])
    snapped_point <- st_cast(snapped_geometry, "POINT")[2] # Extract the snapped point
    
    if (!st_is_empty(snapped_point)) {
      result[i, ] <- st_set_geometry(result[i, ], snapped_point) # Update the geometry
    }
  }
  
  # Handle cases where match is FALSE by searching nearby features and snapping coordinates
  for (i in which(match_result == "FALSE")) {
    nearby_indices <- which(as.numeric(st_distance(sf1[i, ], sf2, by_element = FALSE)) <= as.numeric(set_units(searchdist, "m")))
    if (length(nearby_indices) > 0) {
      for (j in nearby_indices) {
        similarity <- 1 - stringdist::stringdist(col1[i], col2[j], method = "lv") / max(nchar(col1[i]), nchar(col2[j]))
        if (similarity >= 0.9) { # Only consider TRUE matches for snapping
          match_result[i] <- "TRUE"  # Ensure initial FALSE matches that find a TRUE match are set to TRUE
          distances[i] <- st_distance(sf1[i, ], sf2[j, ], by_element = TRUE)
          nearest_indices[i] <- j
          
          # Extract the nearest point on the line
          snapped_geometry <- st_nearest_points(sf1[i, ], sf2[j, ])
          snapped_point <- st_cast(snapped_geometry, "POINT")[2] # Extract the snapped point
          
          if (!st_is_empty(snapped_point)) {
            result[i, ] <- st_set_geometry(result[i, ], snapped_point) # Update the geometry
          }
          break
        }
      }
    }
  }
  
  # Add the match result and distance to the result object
  result$match <- match_result
  result$distance_to_nearest <- set_units(distances, "m") # Ensure distance is in meters
  
  return(result)
}




# Comprehensive example usage:
library(sf)
library(ggplot2)

# Create the first spatial object (sf1) with names and coordinates representing data collection points
sf1 <- st_as_sf(
  data.frame(
    id = 1:6,
    name = c("Alice Creek", "Rock River", "Charlie Creek", "David Brook", "DONKEY Creek", "Frank Creek"),
    lon = c(0.5, 1.1, 2.3, 3, 1.5, 3),
    lat = c(-1.4, 0.9, 1.2, 1, -0.7, -1.1)
  ),
  coords = c("lon", "lat"),
  crs = 4326
)

# Create the second spatial object (sf2) as a river system with tributaries flowing into a main river
sf2 <- st_as_sf(
  data.frame(
    id = 1:4,
    name = c("ROCK River", "Charley Creek", "Frank Creek", "Donkey Creek"),
    wkt = c(
      "LINESTRING (0 2, 1 1, 2 0, 3 -1)",   # Rock River, flowing from top-left to lower-right
      "LINESTRING (2 0, 2.5 1, 3 2)",       # Charlene Creek, flowing into Rock River
      "LINESTRING (3 -1, 3.5 0, 4 1)",      # Frank Creek, flowing into Rock River
      "LINESTRING (0 -2, 1 -1, 2 0, 3 -1, 4 -2)" # Main River, connecting tributaries
    )
  ),
  wkt = "wkt",
  crs = 4326
)

# Run rivmatch to match data points to the river system
result <- rivmatch(sf1, sf2, "name", searchdist = 1000000) # 1,000,000 meters search distance
print(result)

# VIEW ORIGINAL LOCATIONS
sf1 %>%
  ggplot() +
  geom_sf() +
  geom_sf_text(aes(label = name)) +
  geom_sf(data = sf2, color = "blue", size = 1) +
  geom_sf_text(data = sf2, aes(label = name), color="blue", size=2)

# VIEW Updated Object
sf1 %>%
  ggplot() +
  geom_sf(data = sf2, color = "blue", size = 1) +
  geom_sf_text(data = sf2, aes(label = name), color="blue", size=2)+ 
  geom_sf_text(data = result, aes(label = name)) +
  geom_sf(data = result, aes(color = match, size = match))
