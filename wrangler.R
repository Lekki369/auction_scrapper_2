source("R/R.R")

message("------------ FORECLOSE ------------")
message("Convert raw JSON to CSV")
auction_foreclose <- json2tbl("history/auction_data.json", "FORECLOSURE")
save_auction_csv(auction_foreclose, "foreclose")
message("Combine with previous data")
foreclose <- combine_data("auction_data.rds", auction_foreclose)
saveRDS(foreclose, file = "auction_data.rds")

