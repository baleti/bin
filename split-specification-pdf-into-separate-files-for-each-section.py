# run this command first to obtain toc.txt file
# pdftk input.pdf dump_data output toc.txt
import re
import os
from concurrent.futures import ProcessPoolExecutor

toc_file = 'toc.txt'
input_pdf = '21630-XYZ-AB-ZZZ-DR-A-3000-PROJECT-NBS SPECIFICATION.pdf'  # Replace with your actual PDF file name

# Read the TOC file and parse the page ranges
page_ranges = []

with open(toc_file, 'r') as f:
    lines = f.readlines()

# Improved regex to match bookmark titles and their page numbers
title = None
page = None
for line in lines:
    title_match = re.match(r"BookmarkTitle: (.+)", line)
    page_match = re.match(r"BookmarkPageNumber: (\d+)", line)

    if title_match:
        title = title_match.group(1).strip()

    if page_match:
        page = int(page_match.group(1))
        if title and page:
            page_ranges.append((title, page))
            title = None  # Reset title for the next match

# Check if page_ranges were successfully populated
if not page_ranges:
    print("Error: No matches found in TOC. Please check the format of toc.txt.")
    exit(1)

# Process the page ranges to create splitting commands
output_ranges = []
for i in range(len(page_ranges) - 1):
    start_title, start_page = page_ranges[i]
    _, end_page = page_ranges[i + 1]
    output_ranges.append((start_title, start_page, end_page - 1))

# Last section runs to the end of the document
last_title, last_page = page_ranges[-1]
output_ranges.append((last_title, last_page, None))  # None indicates the last page

# Function to split the PDF and save the output
def split_pdf(title, start_page, end_page):
    # Generate a safe filename
    safe_title = f"{input_pdf}-{title.replace(' ', '_').replace('/', '_')}"

    # Wrap filenames in quotes to handle spaces
    input_pdf_quoted = f'"{input_pdf}"'
    output_pdf_quoted = f'"{safe_title}.pdf"'

    if end_page:
        os.system(f'pdftk {input_pdf_quoted} cat {start_page}-{end_page} output {output_pdf_quoted}')
    else:
        os.system(f'pdftk {input_pdf_quoted} cat {start_page}-end output {output_pdf_quoted}')

# Use ProcessPoolExecutor to parallelize the PDF splitting
with ProcessPoolExecutor() as executor:
    futures = []
    for title, start_page, end_page in output_ranges:
        futures.append(executor.submit(split_pdf, title, start_page, end_page))

    # Wait for all tasks to complete
    for future in futures:
        future.result()  # This will raise exceptions if any occurred in the tasks

