#!/usr/bin/env python3
"""
CSV Generator for Image URLs Database
Creates a structured CSV with 50 image URLs for processing
"""
#create a scraper 
import csv
import requests
import time
from datetime import datetime
from typing import List, Dict
import uuid

# Sample image URLs from various sources 
SAMPLE_URLS = [
    "https://picsum.photos/800/600?random=1",
    "https://picsum.photos/1200/800?random=2", 
    "https://picsum.photos/400/300?random=3",
    "https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800",
    "https://images.unsplash.com/photo-1519904981063-b0cf448d479e?w=800",
]

def validate_url(url: str, timeout: int = 5) -> Dict:
    """Validate if URL is accessible and get metadata"""
    try:
        response = requests.head(url, timeout=timeout)
        return {
            'status': response.status_code,
            'content_type': response.headers.get('content-type', 'unknown'),
            'content_length': response.headers.get('content-length', 0),
            'valid': response.status_code == 200
        }
    except Exception as e:
        return {
            'status': 0,
            'content_type': 'error',
            'content_length': 0,
            'valid': False,
            'error': str(e)
        }

def generate_image_database(num_rows: int = 50) -> List[Dict]:
    """Generate database of image URLs with metadata"""
    
    database = []
    
    for i in range(num_rows):
        # Cycle through sample URLs and add variation
        base_url = SAMPLE_URLS[i % len(SAMPLE_URLS)]
        
        # Add unique parameters to avoid duplicates
        if "picsum.photos" in base_url:
            url = f"https://picsum.photos/{800 + i*10}/{600 + i*5}?random={i+100}"
        else:
            url = base_url
            
        # Validate URL
        print(f"Validating URL {i+1}/{num_rows}: {url}")
        validation = validate_url(url)
        
        # Create record
        record = {
            'id': str(uuid.uuid4()),
            'url': url,
            'priority': 'high' if i < 10 else 'medium' if i < 30 else 'low',
            'expected_size': f"{800 + i*10}x{600 + i*5}",
            'category': ['landscape', 'portrait', 'abstract', 'nature'][i % 4],
            'created_at': datetime.now().isoformat(),
            'status': 'pending',
            'valid_url': validation['valid'],
            'content_type': validation.get('content_type', 'unknown'),
            'estimated_size_bytes': validation.get('content_length', 0)
        }
        
        database.append(record)
        
        # Rate limiting to be nice to servers
        time.sleep(0.1)
    
    return database

def save_to_csv(database: List[Dict], filename: str = 'image_database.csv'):
    """Save database to CSV file"""
    
    if not database:
        raise ValueError("Database is empty")
        
    fieldnames = database[0].keys()
    
    with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(database)
    
    print(f"✅ Database saved to {filename}")
    print(f"📊 Total records: {len(database)}")
    print(f"✅ Valid URLs: {sum(1 for r in database if r['valid_url'])}")
    print(f"❌ Invalid URLs: {sum(1 for r in database if not r['valid_url'])}")

def main():
    """Main execution function"""
    print("🚀 Generating Image URL Database...")
    
    # Generate database
    database = generate_image_database(50)
    
    # Save to CSV
    save_to_csv(database)
    
    # Generate summary report
    print("\n📈 SUMMARY REPORT:")
    print("-" * 40)
    
    categories = {}
    priorities = {}
    
    for record in database:
        # Count categories
        cat = record['category']
        categories[cat] = categories.get(cat, 0) + 1
        
        # Count priorities  
        pri = record['priority']
        priorities[pri] = priorities.get(pri, 0) + 1
    
    print("Categories:", categories)
    print("Priorities:", priorities)
    print("Ready for ingestion! 🎉")

if __name__ == "__main__":
    main()