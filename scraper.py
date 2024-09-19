# from auctionscraper import scraper
# import logging
# import json

# logging.basicConfig(level=logging.DEBUG)

# def scrape(category:str, output:str):
#     # LEVEL 1 - scrape schedules from calendars
#     # argument days is the number of day start from today
#     calendar_url_list = scraper.get_calendar_list(category, days=0)
#     box_url_list = scraper.get_box_list(calendar_url_list)
#     # LEVEL 2 - scrape the real data
#     data = scraper.get_data(box_url_list)
#     # save data
#     with open(output, 'w') as fout:
#          json.dump(data, fout)
#          logging.info(f"Data saved to {output}")

# if __name__ == '__main__':
#     scrape('foreclose', 'history/foreclose.json')
#     scrape('taxdeed', 'history/taxdeed.json')




from playwright.sync_api import sync_playwright
import logging
import json
import re

# Logger setup
logging.basicConfig(level=logging.DEBUG)

def scrape_auction_items(page):
    """ Scrape auction items from the current page """
    auction_items = page.query_selector_all('#Area_C > .AUCTION_ITEM.PREVIEW')
    auction_data = []
    
    for auction_item in auction_items:
        # Extract auction date from the page content
        auction_date_match = re.search(r'AUCTIONDATE=(\d{2}/\d{2}/\d{4})', page.url)
        auction_date = auction_date_match.group(1) if auction_date_match else 'Unknown'

        # Extract the "Sold To" field to check if it's a 3rd Party Bidder
        sold_to_element = auction_item.query_selector('.ASTAT_MSG_SOLDTO_MSG')
        sold_to = sold_to_element.inner_text().strip() if sold_to_element else None

        # Only process if sold to "3rd Party Bidder"
        if sold_to == "3rd Party Bidder":
            auction_info = {
                'auction_date': auction_date,
                'sold_to': sold_to
            }

            # Extract auction details (case number, property address, etc.)
            auction_details = {}
            auction_fields = auction_item.query_selector_all('tr > th')
            auction_values = auction_item.query_selector_all('tr > td')

            if len(auction_fields) == len(auction_values):
                for i in range(len(auction_fields)):
                    field = auction_fields[i].inner_text().strip().lower().replace(':', '').replace(' ', '_')
                    value = auction_values[i].inner_text().strip()
                    auction_details[field] = value

                auction_info.update(auction_details)

            auction_data.append(auction_info)
    
    return auction_data

def get_next_page(page):
    """ Check and navigate to the next page if it exists """
    try:
        next_button = page.query_selector('span.PageRight > img')
        if next_button and 'blank.gif' not in next_button.get_attribute('src'):  # Next page button is clickable
            next_button.click()
            page.wait_for_load_state('networkidle')  # Wait for next page to load
            return True
        return False
    except Exception as e:
        logging.error(f"Error navigating to next page: {e}")
        return False

def scrape_auction_data(url):
    """ Scrape auction data for a specific date from all pages """
    all_data = []
    with sync_playwright() as p:
        browser = p.firefox.launch(headless=True)  # Set to False for debugging
        page = browser.new_page()
        page.set_default_timeout(90000)
        
        logging.debug(f"Fetching auction items from {url}")
        try:
            page.goto(url)
            page.wait_for_selector('#Area_C > .AUCTION_ITEM.PREVIEW')  # Wait for auction items
            
            # Scrape data from all pages
            while True:
                auction_data = scrape_auction_items(page)
                all_data.extend(auction_data)
                
                # Check if there's a next page and navigate
                if not get_next_page(page):
                    break
        except Exception as e:
            logging.error(f"Failed to scrape data: {e}")
        finally:
            browser.close()

    return all_data

def save_to_json(data, output_file):
    """ Save the scraped data to a JSON file """
    with open(output_file, 'w') as json_file:
        json.dump(data, json_file, indent=4)
        logging.info(f"Data saved to {output_file}")

if __name__ == '__main__':
    auction_url = 'https://manatee.realforeclose.com/index.cfm?zaction=AUCTION&zmethod=PREVIEW&AuctionDate=09/16/2024'
    scraped_data = scrape_auction_data(auction_url)
    
    if scraped_data:
        save_to_json(scraped_data, 'history/auction_data.json')
    else:
        logging.info("No data scraped.")




