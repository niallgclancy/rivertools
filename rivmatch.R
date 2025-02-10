# Optimized Function to Compare Values in Two Columns Across Spatial Objects (rivmatch)
# Now includes spatial clipping and NA removal for faster processing

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
  
  # Store rows with NA values from sf1 to add them back later
  sf1_na <- sf1[is.na(sf1[[column_name]]), ]
  
  # Remove rows in sf1 and sf2 with NA values in the column_name
  sf1 <- sf1[!is.na(sf1[[column_name]]), ]
  sf2 <- sf2[!is.na(sf2[[column_name]]), ]
  
  # Extract the columns and make them lowercase for case-insensitive comparison
  col1 <- tolower(sf1[[column_name]])
  col2 <- tolower(sf2[[column_name]])
  
  # Clip sf2 to the bounding box of sf1 with a buffer of searchdist
  bbox_buffer <- st_buffer(st_union(st_geometry(sf1)), dist = set_units(searchdist, "m"))
  sf2_clipped <- sf2[st_intersects(sf2, bbox_buffer, sparse = FALSE), ]
  
  # Find the nearest feature in sf2_clipped for each feature in sf1
  nearest_indices <- st_nearest_feature(sf1, sf2_clipped)
  
  # Calculate distances between each feature in sf1 and its nearest feature in sf2_clipped
  distances <- st_distance(sf1, sf2_clipped[nearest_indices, ], by_element = TRUE)
  
  # Calculate similarity and categorize matches
  match_result <- sapply(1:length(col1), function(i) {
    if (is.na(col1[i]) || is.na(col2[nearest_indices[i]])) {
      return("FALSE")
    }
    max_length <- max(nchar(col1[i]), nchar(col2[nearest_indices[i]]))
    if (max_length == 0) {
      return("FALSE")
    }
    similarity <- 1 - stringdist::stringdist(col1[i], col2[nearest_indices[i]], method = "lv") / max_length
    if (is.na(similarity)) {
      return("FALSE")
    } else if (similarity >= 0.9) {
      return("TRUE")
    } else if (similarity >= 0.7) {
      return("MAYBE")
    } else {
      return("FALSE")
    }
  })
  
  # Create result object to store modified geometry
  result <- sf1
  
  # Snap TRUE matches to the nearest feature
  for (i in which(match_result == "TRUE")) {
    snapped_geometry <- st_nearest_points(sf1[i, ], sf2_clipped[nearest_indices[i], ])
    snapped_point <- st_cast(snapped_geometry, "POINT")[2] # Extract the snapped point
    
    if (!st_is_empty(snapped_point)) {
      result[i, ] <- st_set_geometry(result[i, ], snapped_point) # Update the geometry
    }
  }
  
  # Handle cases where match is FALSE by searching nearby features and snapping coordinates
  for (i in which(match_result == "FALSE")) {
    nearby_indices <- which(as.numeric(st_distance(sf1[i, ], sf2_clipped, by_element = FALSE)) <= as.numeric(set_units(searchdist, "m")))
    if (length(nearby_indices) > 0) {
      for (j in nearby_indices) {
        if (is.na(col1[i]) || is.na(col2[j])) {
          next
        }
        max_length <- max(nchar(col1[i]), nchar(col2[j]))
        if (max_length == 0) {
          next
        }
        similarity <- 1 - stringdist::stringdist(col1[i], col2[j], method = "lv") / max_length
        if (is.na(similarity)) {
          next
        }
        if (similarity >= 0.9) { # Only consider TRUE matches for snapping
          match_result[i] <- "TRUE"
          distances[i] <- st_distance(sf1[i, ], sf2_clipped[j, ], by_element = TRUE)
          nearest_indices[i] <- j
          
          # Extract the nearest point on the line
          snapped_geometry <- st_nearest_points(sf1[i, ], sf2_clipped[j, ])
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
  
  # Add back rows with NA values (labelled as FALSE matches)
  if (nrow(sf1_na) > 0) {
    sf1_na$match <- "FALSE"
    sf1_na$distance_to_nearest <- NA
    result <- rbind(result, sf1_na)
  }
  
  return(result)
}





# Comprehensive example usage:
library(sf)
library(ggplot2)

# Create the first spatial object (sf1) with names and coordinates representing data collection points
sf1 <- st_as_sf(
  data.frame(
    id = 1:6,
    name = c("Alice Creek", NA, "Charlie Creek", "David Brook", "DONKEY Creek", "Frank Creek"),
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









###################est.month.mean function

# Load required libraries
library(dataRetrieval)
library(dplyr)
library(lubridate)
library(geosphere)  # For calculating distances between sites
library(readxl)  # For reading Excel files
library(sf)  # For handling spatial data
library(units)  # For handling units

# Load the Excel file with site numbers
sites_df <- read_excel("sitesnwisalltemps.xlsx")

# Ensure site numbers are treated as character to preserve leading zeros and filter for 8-digit site numbers
sites_df <- sites_df %>% 
  mutate(SiteNumber = as.character(SiteNumber)) %>% 
  filter(nchar(SiteNumber) == 8)

# Retrieve site metadata to get coordinates
site_metadata <- whatNWISsites(siteNumber = sites_df$SiteNumber)

# Filter for sites with valid latitude and longitude
site_metadata <- site_metadata %>% 
  filter(!is.na(dec_lat_va) & !is.na(dec_long_va)) %>% 
  select(site_no, dec_lat_va, dec_long_va)

# Function to estimate mean August temperatures for an sf object with instantaneous readings
est.month.mean <- function(instantaneous_sf, searchdist = set_units(50, "miles")) {  # Default search distance in miles
  # Ensure the sf object is in the correct CRS (WGS84)
  instantaneous_sf <- st_transform(instantaneous_sf, crs = 4326)
  
  # Combine date and time columns into a single datetime object
  instantaneous_sf <- instantaneous_sf %>%
    mutate(
      date.time = make_datetime(Year, Month, Day) + 
        hours(as.integer(substr(Time, 1, 2))) + 
        minutes(as.integer(substr(Time, 3, 4)))
    )
  
  # Convert site metadata to an sf object
  site_sf <- st_as_sf(site_metadata, coords = c("dec_long_va", "dec_lat_va"), crs = 4326)
  
  # Initialize an empty list to store results
  estimated_temps <- vector("list", nrow(instantaneous_sf))
  
  # Convert search distance to meters if necessary
  if (!inherits(searchdist, "units")) {
    searchdist <- set_units(searchdist, "m")
  }
  
  # Loop through each instantaneous reading
  for (i in seq_len(nrow(instantaneous_sf))) {
    inst_point <- instantaneous_sf[i, ]
    inst_temp <- inst_point$inst.temp
    inst_time <- inst_point$date.time
    
    # Find USGS sites within the specified distance
    distances <- st_distance(inst_point, site_sf)
    nearby_sites <- site_sf[distances <= searchdist, ]
    
    # Initialize variable to store best match
    best_estimate <- NA
    
    # Check each nearby site for matching time data
    for (j in seq_len(nrow(nearby_sites))) {
      site_no <- nearby_sites$site_no[j]
      
      # Retrieve continuous temperature data for August 2023
      continuous_data <- readNWISuv(siteNumbers = site_no, parameterCd = '00010', 
                                    startDate = '2023-08-01', endDate = '2023-08-31')
      
      # Identify the correct temperature column name dynamically
      temp_col <- grep('^X_00010_00000$', names(continuous_data), value = TRUE)
      
      # Skip if temperature data is missing
      if (length(temp_col) == 0) next
      
      # Prepare continuous data
      continuous_data <- continuous_data %>% 
        select(dateTime, temp_continuous = all_of(temp_col)) %>% 
        filter(!is.na(temp_continuous))
      
      # Find the closest reading within 1 hour
      closest_reading <- continuous_data %>% 
        filter(between(dateTime, inst_time - hours(1), inst_time + hours(1))) %>% 
        arrange(abs(difftime(dateTime, inst_time, units = "mins"))) %>% 
        slice(1)
      
      # If a close reading exists, estimate mean August temperature
      if (nrow(closest_reading) > 0) {
        temp_offset <- inst_temp - closest_reading$temp_continuous
        mean_august_temp <- mean(continuous_data$temp_continuous, na.rm = TRUE)
        estimated_mean_temp <- mean_august_temp + temp_offset
        
        # Select the first valid estimate
        best_estimate <- estimated_mean_temp
        break  # Stop checking other sites once a valid estimate is found
      }
    }
    
    # Store the estimated mean temperature
    estimated_temps[[i]] <- best_estimate
  }
  
  # Append the estimated temperatures to the original sf object
  instantaneous_sf$Estimated_Mean_August_Temp <- unlist(estimated_temps)
  
  return(instantaneous_sf)
}

# Example usage:
# instantaneous_sf <- st_read("path/to/your_instantaneous_readings.shp")
# result_sf <- est.month.mean(instantaneous_sf, searchdist = set_units(100, "km"))  # Search within 100 km
# print(result_sf)
