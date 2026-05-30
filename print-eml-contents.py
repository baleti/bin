#!/usr/bin/env python3
import email
import sys
import re

if len(sys.argv) < 2:
    print("Usage: print-eml-contents.py <file.eml>")
    sys.exit(1)

filename = sys.argv[1]

def remove_signature(text):
    """Remove common email signature patterns"""
    
    # Common signature delimiters
    signature_patterns = [
        r'\n-- \n.*',  # Standard signature delimiter (-- )
        r'\n--\n.*',   # Variation without spaces
        r'\n_{3,}.*',  # Three or more underscores
        r'\nBest regards,?\n.*',
        r'\nBest,?\n.*',
        r'\nRegards,?\n.*',
        r'\nSincerely,?\n.*',
        r'\nThanks,?\n.*',
        r'\nThank you,?\n.*',
        r'\nCheers,?\n.*',
        r'\nSent from my .*',  # "Sent from my iPhone" etc.
    ]
    
    # Try each pattern and cut at the earliest match
    earliest_pos = len(text)
    
    for pattern in signature_patterns:
        match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
        if match and match.start() < earliest_pos:
            earliest_pos = match.start()
    
    # Cut the text at the signature
    if earliest_pos < len(text):
        text = text[:earliest_pos].rstrip()
    
    return text

try:
    with open(filename, 'r', encoding='utf-8', errors='ignore') as f:
        msg = email.message_from_file(f)
        
        text_content = None
        
        if msg.is_multipart():
            for part in msg.walk():
                if part.get_content_type() == 'text/plain':
                    payload = part.get_payload(decode=True)
                    if payload:
                        text_content = payload.decode('utf-8', errors='ignore')
                    break
        else:
            payload = msg.get_payload(decode=True)
            if payload:
                text_content = payload.decode('utf-8', errors='ignore')
            else:
                text_content = msg.get_payload()
        
        if text_content:
            # Remove signature and print
            clean_text = remove_signature(text_content)
            print(clean_text)
        
except FileNotFoundError:
    print(f"Error: File '{filename}' not found")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
