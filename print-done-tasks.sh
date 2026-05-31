#!/usr/bin/env sh
for file in $(ls *.org); do
  awk -v f="$file" '
    { sub(/\r$/, ""); }  # Remove the carriage return character (Windows line endings)
    /^\* done[[:space:]]*$/ {
      printf("* ~File: %s~\n", f);  # Print filename
      print $0;
      flag=1; next
    }
    flag' "$file";
done 2>/dev/null
