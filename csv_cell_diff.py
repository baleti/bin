import csv
import sys

RED = '\033[31m'
GREEN = '\033[32m'
RESET = '\033[0m'

def load_csv_by_key(file_path, key_column, no_headers=False):
    with open(file_path, newline='') as f:
        if no_headers:
            # Read as regular reader, create synthetic headers
            reader = csv.reader(f)
            rows_list = list(reader)
            if not rows_list:
                return [], {}

            # Create synthetic headers based on column count
            num_cols = len(rows_list[0]) if rows_list else 0
            headers = [f"col{i}" for i in range(num_cols)]

            # If key_column is None, use first column (col0)
            if key_column is None:
                key_column = "col0"

            # Build dictionary using the key column
            rows = {}
            for row_data in rows_list:
                # Create dict from row data
                row_dict = {headers[i]: row_data[i] if i < len(row_data) else ''
                           for i in range(len(headers))}
                key = row_dict.get(key_column, '')
                if key:  # Only add if key is not empty
                    rows[key] = row_dict
        else:
            # Read with headers
            reader = csv.DictReader(f)
            rows_list = list(reader)
            headers = reader.fieldnames or []

            # If key_column is None, use first column
            if key_column is None and headers:
                key_column = headers[0]

            rows = {row.get(key_column, ''): row for row in rows_list
                   if row.get(key_column, '')}  # Only add if key is not empty

        return headers, rows

def load_csv_as_list(file_path, no_headers=False):
    """Load CSV as a list of rows for line-by-line comparison"""
    with open(file_path, newline='') as f:
        if no_headers:
            reader = csv.reader(f)
            rows_list = list(reader)
            if not rows_list:
                return [], []

            # Create synthetic headers
            num_cols = max(len(row) for row in rows_list) if rows_list else 0
            headers = [f"col{i}" for i in range(num_cols)]

            # Convert to list of dicts
            rows = []
            for row_data in rows_list:
                row_dict = {headers[i]: row_data[i] if i < len(row_data) else ''
                           for i in range(len(headers))}
                rows.append(row_dict)
        else:
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = reader.fieldnames or []

        return headers, rows

def color_diff(val1, val2, highlight):
    if val1 == val2:
        return val1
    if not highlight:
        if val1 and val2:
            return f"{val1} → {val2}"
        elif val1:
            return f"{val1} → (deleted)"
        elif val2:
            return f"(new) → {val2}"
        else:
            return ''
    # Highlight mode
    if val1 and val2:
        return f"{RED}{val1}{RESET} → {GREEN}{val2}{RESET}"
    elif val1:
        return f"{RED}{val1} → (deleted){RESET}"
    elif val2:
        return f"(new) → {GREEN}{val2}{RESET}"
    else:
        return ''

def diff_csv_line_by_line(file1, file2, highlight=False, no_headers=False):
    """Compare CSV files line by line"""
    headers1, data1 = load_csv_as_list(file1, no_headers)
    headers2, data2 = load_csv_as_list(file2, no_headers)

    # Merge headers preserving order
    headers = list(dict.fromkeys(headers1 + headers2))

    # Print headers unless --no-headers was specified
    if not no_headers:
        print(','.join(headers))

    # Compare line by line
    max_lines = max(len(data1), len(data2))

    for i in range(max_lines):
        row1 = data1[i] if i < len(data1) else {}
        row2 = data2[i] if i < len(data2) else {}

        # If one file has fewer lines, treat missing row as all empty
        result_row = [
            color_diff(row1.get(col, ''), row2.get(col, ''), highlight)
            for col in headers
        ]
        print(','.join(result_row))

def diff_csv_by_key(file1, file2, key_column, highlight=False, sort_column=None, no_headers=False):
    headers1, data1 = load_csv_by_key(file1, key_column, no_headers)
    headers2, data2 = load_csv_by_key(file2, key_column, no_headers)

    # Merge headers preserving order
    headers = list(dict.fromkeys(headers1 + headers2))

    # Print headers unless --no-headers was specified
    if not no_headers:
        print(','.join(headers))

    all_keys = sorted(set(data1.keys()) | set(data2.keys()))

    def get_sort_key(row_key):
        row = data2.get(row_key) or data1.get(row_key) or {}
        return row.get(sort_column, '') if sort_column else row_key

    sorted_keys = sorted(all_keys, key=get_sort_key)

    for k in sorted_keys:
        row1 = data1.get(k, {})
        row2 = data2.get(k, {})
        result_row = [
            color_diff(row1.get(col, ''), row2.get(col, ''), highlight)
            for col in headers
        ]
        print(','.join(result_row))

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Diff two CSV files by key column or line-by-line.")
    parser.add_argument("file1", help="First CSV file (old)")
    parser.add_argument("file2", help="Second CSV file (new)")
    parser.add_argument("key_column", nargs='?', default=None,
                       help="Column name used as unique row identifier (defaults to first column, ignored with --line-by-line)")
    parser.add_argument("--highlight", action="store_true",
                       help="Enable colored output (ANSI)")
    parser.add_argument("--sort", help="Sort rows by this column name (not compatible with --line-by-line)")
    parser.add_argument("--no-headers", action="store_true",
                       help="Treat input files as having no headers")
    parser.add_argument("--line-by-line", action="store_true",
                       help="Compare files line by line instead of by key")

    args = parser.parse_args()

    if args.line_by_line:
        if args.sort:
            print("Warning: --sort is ignored in line-by-line mode", file=sys.stderr)
        diff_csv_line_by_line(
            args.file1,
            args.file2,
            highlight=args.highlight,
            no_headers=args.no_headers
        )
    else:
        diff_csv_by_key(
            args.file1,
            args.file2,
            args.key_column,
            highlight=args.highlight,
            sort_column=args.sort,
            no_headers=args.no_headers
        )
