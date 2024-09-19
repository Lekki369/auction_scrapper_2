# library(dplyr, warn.conflicts = FALSE)
# library(googlesheets4)
# library(jsonlite)

# #' Import New Auction Data from JSON
# #' @param json json file
# #' @param category category, FORECLOSURE or TAXDEED
# #' 
# json2tbl <- function(json, category) {
#   if (!(category %in% c("FORECLOSURE", "TAXDEED"))) {
#     stop("Argument 'category' must be FORECLOSURE or TAXDEED")
#   }
#   data <- fromJSON(suppressWarnings(readLines(json))) %>% 
#     dplyr::filter(
#       auction_type == category,
#       !is.na(auction_date),
#       !is.na(property_address)
#     ) %>% 
#     as_tibble()
#   if (category == "FORECLOSURE") {
#     data <- data %>% 
#       select(
#         auction_date,
#         judgment_amount = final_judgment_amount,
#         address = property_address,
#         city,
#         state,
#         zip = zipcode
#       )
#   } else { # TAXDEED
#     data <- data %>% 
#       select(
#         auction_date,
#         opening_bid,
#         address = property_address,
#         city,
#         state,
#         zip = zipcode
#       )
#   }
#   # filter invalid location data
#   invalid_addr <- c("UNKNOWN", "NOT ASSIGNED", "UNASSIGNED")
#   data <- data %>% 
#     dplyr::filter(
#       !(is.na(city) | 
#           grepl(pattern = "^NO\\s", x = .$address) | 
#           address %in% invalid_addr)
#     )
#   return(data)
# }

# #' Combine Old Auction Data with the Newest
# #' @param old_data_rds old rds file
# #' @param new_data new imported data from json
# #' 
# combine_data <- function(old_data_rds, new_data) {
#   # reshape old data
#   auction_past <- readRDS(old_data_rds) %>% 
#     mutate(id = paste(address, city, state, zip, sep = ", "),
#            .keep = "unused", .before = 1) %>% 
#     select(id, date_added) %>%
#     distinct()
#   # combine old data with the newest data
#   auction_data <- new_data %>% 
#     mutate(id = paste(address, city, state, zip, sep = ", ")) %>% 
#     left_join(auction_past, by = "id") %>% 
#     select(-id) %>% 
#     mutate(
#       date_added = ifelse(
#         is.na(date_added),
#         format(Sys.Date(), "%m/%d/%Y"),
#         date_added),
#       auction_date = as.Date(auction_date, "%m/%d/%Y")
#     ) %>% 
#     arrange(auction_date, city, zip) %>% 
#     mutate(auction_date = format(auction_date, "%m/%d/%Y")) %>% 
#     distinct()
#   return(auction_data)
# }

# #' Save New Combined Auction Data to CSV for History
# #' @param new_data new imported data from json
# #' @param category category, foreclose or taxdeed
# #' 
# save_auction_csv <- function(new_data, category) {
#   if (!(category %in% c("foreclose", "taxdeed"))) {
#     stop("Argument 'category' must foreclose or taxdeed")
#   }
#   date_created <- format(Sys.Date(), "%Y-%m-%d")
#   write.csv(
#     x = new_data,
#     file = sprintf("history/%s/auction_%s.csv", category, date_created),
#     row.names = FALSE,
#     na = ""
#   )
# }

# #' Push Auction Data to Google Sheets
# #' @param category category, foreclose or taxdeed
# #' 
# push_auction <- function(category) {
#   auction_data <- readRDS(paste0(category, ".rds"))
#   if (category == "foreclose") {
#     names(auction_data) <- c(
#       "Auction Date", 
#       "Judgment Amount", 
#       "Address", "City", 
#       "State", 
#       "Zip",
#       "Date Added"
#     )
#   } else { # taxdeed
#     names(auction_data) <- c(
#       "Auction Date", 
#       "Opening Bid", 
#       "Address", "City", 
#       "State", 
#       "Zip",
#       "Date Added"
#     )
#   }
#   gs4_auth(path = Sys.getenv("CRED_PATH"))
#   tryCatch({
#     if (Sys.getenv(paste0("SHEETS_", toupper(category))) == "") {
#       sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
#     }
#     else {
#       sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(category))), "Raw")
#     }
#     # sheet_write(auction_data, Sys.getenv(paste0("SHEETS_", toupper(category))), "Raw")
#     # sheet_write(auction_data, Sys.getenv("SHEETS_TEST"), "Raw")
#     msg <- sprintf("%s data is now available on Google Sheets!", toupper(category))
#     message(msg)
#   }, error = function(e) message("CANNOT send data to Google Sheets!"))
#   gs4_deauth()
# }













library(dplyr)
library(googlesheets4)
library(jsonlite)

#' Import Auction Data from JSON
#' @param json_file JSON file path
json2tbl <- function(json_file) {
  auction_data <- fromJSON(json_file) %>%
    as_tibble() %>%
    filter(
      auction_type == "FORECLOSURE", # Filter for foreclosure only
      !is.na(auction_date), 
      auction_date != "Unknown"
    ) %>%
    select(
      auction_date, 
      sold_to, 
      auction_type, 
      case_no = `case_#`, 
      cert_no = `certificate_#`, 
      judgment_amount = final_judgment_amount,  # Assuming this field exists for foreclosure
      parcel_id, 
      property_address, 
      assessed_value
    )

  # Convert auction_date to Date type
  auction_data <- auction_data %>%
    mutate(auction_date = as.Date(auction_date, format = "%m/%d/%Y"))
  
  return(auction_data)
}

#' Save Auction Data to CSV
#' @param data Auction data tibble
save_auction_csv <- function(data) {
  file_name <- sprintf("history/foreclosure_data_%s.csv", format(Sys.Date(), "%Y-%m-%d"))
  tryCatch({
    write.csv(data, file = file_name, row.names = FALSE, na = "")
    message("Data successfully saved to CSV file: ", file_name)
  }, error = function(e) {
    message("Failed to save data to CSV: ", e$message)
  })
}

#' Main Process for Foreclosure Auction Data
process_auction_data <- function(json_file) {
  message("------------- FORECLOSURE AUCTION DATA -------------")
  message("Convert raw JSON to CSV")
  
  auction_data <- json2tbl(json_file)
  save_auction_csv(auction_data)

  # Save the new auction data to a new RDS file
  rds_file_name <- paste0("foreclosure_data_", Sys.Date(), ".rds")
  saveRDS(auction_data, file = rds_file_name)
  
  message("-----------------------------------")
  message("Wrangler succeeded!")
  message("--------------- END ---------------")
}

# Call the process for foreclosure auction data
process_auction_data("auction_data.json")
