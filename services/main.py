#!/usr/bin/env python3
"""
Cloud Run Service: Image Processing Engine
Processes images from Pub/Sub messages and saves to Cloud Storage
"""

import os
import json
import logging
import asyncio
import aiohttp
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime
from PIL import Image, ImageOps
from PIL.ExifTags import TAGS
import io
import hashlib
import uuid
from concurrent.futures import ThreadPoolExecutor
import time

from flask import Flask, request, jsonify
from google.cloud import storage, pubsub_v1, firestore
from google.cloud.exceptions import NotFound

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', 'your-project-id')
BUCKET_NAME = os.environ.get('BUCKET_NAME', 'your-bucket-images')
PUBSUB_SUBSCRIPTION = os.environ.get('PUBSUB_SUBSCRIPTION', 'pixelpipe-processing-sub-dev')

# Initialize clients
storage_client = storage.Client()
subscriber = pubsub_v1.SubscriberClient()
firestore_client = firestore.Client()

# Flask app
app = Flask(__name__)

class ImageProcessor:
    """Advanced image processing with multiple output formats"""
    
    def __init__(self, bucket_name: str):
        self.bucket = storage_client.bucket(bucket_name)
        self.max_image_size = 50 * 1024 * 1024  # 50MB
        self.timeout = 30  # seconds
        
    async def download_image(self, url: str) -> Tuple[bytes, Dict[str, Any]]:
        """Download image from URL with metadata"""
        
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=self.timeout)) as session:
            try:
                async with session.get(url) as response:
                    if response.status != 200:
                        raise Exception(f"HTTP {response.status}: {response.reason}")
                    
                    # Check content type
                    content_type = response.headers.get('content-type', '').lower()
                    if not content_type.startswith('image/'):
                        raise Exception(f"Invalid content type: {content_type}")
                    
                    # Check file size
                    content_length = int(response.headers.get('content-length', 0))
                    if content_length > self.max_image_size:
                        raise Exception(f"Image too large: {content_length} bytes")
                    
                    # Download image data
                    image_data = await response.read()
                    
                    # Create download metadata
                    metadata = {
                        'original_url': url,
                        'content_type': content_type,
                        'content_length': len(image_data),
                        'download_timestamp': datetime.utcnow().isoformat(),
                        'http_status': response.status,
                        'content_hash': hashlib.sha256(image_data).hexdigest()
                    }
                    
                    return image_data, metadata
                    
            except asyncio.TimeoutError:
                raise Exception(f"Download timeout for URL: {url}")
            except Exception as e:
                raise Exception(f"Download failed: {str(e)}")
    
    def extract_image_metadata(self, image_data: bytes) -> Dict[str, Any]:
        """Extract comprehensive image metadata"""
        
        try:
            with Image.open(io.BytesIO(image_data)) as img:
                metadata = {
                    'format': img.format,
                    'mode': img.mode,
                    'size': img.size,
                    'width': img.width,
                    'height': img.height,
                    'has_transparency': img.mode in ('RGBA', 'LA') or 'transparency' in img.info
                }
                
                # Extract EXIF data
                exif_data = {}
                if hasattr(img, '_getexif') and img._getexif():
                    exif = img._getexif()
                    for tag_id, value in exif.items():
                        tag_name = TAGS.get(tag_id, tag_id)
                        exif_data[tag_name] = str(value)
                
                metadata['exif'] = exif_data
                
                # Color analysis
                if img.mode == 'RGB':
                    # Get dominant colors (simplified)
                    img_small = img.resize((50, 50))
                    colors = img_small.getcolors(maxcolors=256)
                    if colors:
                        dominant_color = max(colors, key=lambda x: x[0])[1]
                        metadata['dominant_color'] = dominant_color
                
                return metadata
                
        except Exception as e:
            logger.error(f"Failed to extract metadata: {str(e)}")
            return {'error': str(e)}
    
    def resize_image(self, image_data: bytes, target_sizes: List[str], output_formats: List[str]) -> Dict[str, bytes]:
        """Create multiple resized versions of the image"""
        
        results = {}
        
        try:
            with Image.open(io.BytesIO(image_data)) as img:
                # Auto-orient based on EXIF
                img = ImageOps.exif_transpose(img)
                
                # Convert to RGB if necessary (for JPEG)
                if img.mode in ('RGBA', 'LA', 'P'):
                    rgb_img = Image.new('RGB', img.size, (255, 255, 255))
                    if img.mode == 'P':
                        img = img.convert('RGBA')
                    rgb_img.paste(img, mask=img.split()[-1] if img.mode in ('RGBA', 'LA') else None)
                    img = rgb_img
                
                for size_str in target_sizes:
                    try:
                        # Parse size string (e.g., "800x600")
                        width, height = map(int, size_str.split('x'))
                        
                        # Calculate aspect-preserving size
                        img_ratio = img.width / img.height
                        target_ratio = width / height
                        
                        if img_ratio > target_ratio:
                            # Image is wider than target
                            new_width = width
                            new_height = int(width / img_ratio)
                        else:
                            # Image is taller than target
                            new_height = height
                            new_width = int(height * img_ratio)
                        
                        # Resize image with high-quality resampling
                        resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                        
                        # Create versions in different formats
                        for fmt in output_formats:
                            output_buffer = io.BytesIO()
                            
                            if fmt.lower() == 'jpeg':
                                resized_img.save(output_buffer, format='JPEG', quality=85, optimize=True)
                            elif fmt.lower() == 'webp':
                                resized_img.save(output_buffer, format='WEBP', quality=85, optimize=True)
                            elif fmt.lower() == 'png':
                                resized_img.save(output_buffer, format='PNG', optimize=True)
                            else:
                                continue  # Skip unsupported format
                            
                            key = f"{size_str}_{fmt.lower()}"
                            results[key] = output_buffer.getvalue()
                            
                    except Exception as e:
                        logger.error(f"Failed to resize to {size_str}: {str(e)}")
                        continue
                
        except Exception as e:
            logger.error(f"Failed to process image for resizing: {str(e)}")
            
        return results
    
    def create_thumbnail(self, image_data: bytes, size: Tuple[int, int] = (150, 150)) -> bytes:
        """Create a square thumbnail"""
        
        try:
            with Image.open(io.BytesIO(image_data)) as img:
                # Auto-orient
                img = ImageOps.exif_transpose(img)
                
                # Create square thumbnail
                img.thumbnail(size, Image.Resampling.LANCZOS)
                
                # Convert to RGB for JPEG
                if img.mode in ('RGBA', 'LA', 'P'):
                    rgb_img = Image.new('RGB', img.size, (255, 255, 255))
                    if img.mode == 'P':
                        img = img.convert('RGBA')
                    rgb_img.paste(img, mask=img.split()[-1] if img.mode in ('RGBA', 'LA') else None)
                    img = rgb_img
                
                # Save as JPEG
                output_buffer = io.BytesIO()
                img.save(output_buffer, format='JPEG', quality=80, optimize=True)
                return output_buffer.getvalue()
                
        except Exception as e:
            logger.error(f"Failed to create thumbnail: {str(e)}")
            raise
    
    async def upload_to_storage(self, file_data: bytes, file_path: str, content_type: str = 'image/jpeg', 
                               metadata: Optional[Dict[str, str]] = None) -> str:
        """Upload processed image to Cloud Storage"""
        
        try:
            blob = self.bucket.blob(file_path)
            
            # Set metadata
            if metadata:
                blob.metadata = metadata
            
            # Upload file
            await asyncio.get_event_loop().run_in_executor(
                None, 
                lambda: blob.upload_from_string(file_data, content_type=content_type)
            )
            
            # Make file publicly readable (for demo purposes)
            blob.make_public()
            
            return f"gs://{self.bucket.name}/{file_path}"
            
        except Exception as e:
            logger.error(f"Failed to upload {file_path}: {str(e)}")
            raise
    
    async def process_image_job(self, job: Dict[str, Any]) -> Dict[str, Any]:
        """Process a complete image job"""
        
        job_id = job['job_id']
        image_id = job['image_id']
        url = job['url']
        
        logger.info(f"Processing job {job_id}: {url}")
        
        result = {
            'job_id': job_id,
            'image_id': image_id,
            'original_url': url,
            'status': 'processing',
            'started_at': datetime.utcnow().isoformat(),
            'outputs': {},
            'metadata': {},
            'errors': []
        }
        
        try:
            # Step 1: Download original image
            logger.info(f"Downloading image: {url}")
            image_data, download_metadata = await self.download_image(url)
            result['metadata']['download'] = download_metadata
            
            # Step 2: Extract image metadata
            logger.info(f"Extracting metadata for {job_id}")
            image_metadata = self.extract_image_metadata(image_data)
            result['metadata']['image'] = image_metadata
            
            # Step 3: Save original image
            original_path = f"original/{image_id}/{image_id}_original.jpg"
            original_url = await self.upload_to_storage(
                image_data, 
                original_path,
                content_type=download_metadata.get('content_type', 'image/jpeg'),
                metadata={'job_id': job_id, 'type': 'original'}
            )
            result['outputs']['original'] = original_url
            
            # Step 4: Create thumbnail
            if job.get('processing_options', {}).get('create_thumbnail', True):
                logger.info(f"Creating thumbnail for {job_id}")
                thumbnail_data = self.create_thumbnail(image_data)
                thumbnail_path = f"thumbnails/{image_id}/{image_id}_thumb.jpg"
                thumbnail_url = await self.upload_to_storage(
                    thumbnail_data,
                    thumbnail_path,
                    metadata={'job_id': job_id, 'type': 'thumbnail'}
                )
                result['outputs']['thumbnail'] = thumbnail_url
            
            # Step 5: Create resized versions
            processing_options = job.get('processing_options', {})
            resize_formats = processing_options.get('resize_formats', ['400x300'])
            output_formats = processing_options.get('output_formats', ['jpeg'])
            
            if resize_formats:
                logger.info(f"Creating resized versions for {job_id}")
                resized_images = self.resize_image(image_data, resize_formats, output_formats)
                
                result['outputs']['resized'] = {}
                for size_format, resized_data in resized_images.items():
                    resized_path = f"resized/{image_id}/{image_id}_{size_format}"
                    resized_url = await self.upload_to_storage(
                        resized_data,
                        resized_path,
                        metadata={'job_id': job_id, 'type': 'resized', 'variant': size_format}
                    )
                    result['outputs']['resized'][size_format] = resized_url
            
            # Success!
            result['status'] = 'completed'
            result['completed_at'] = datetime.utcnow().isoformat()
            
            # Calculate processing time
            start_time = datetime.fromisoformat(result['started_at'].replace('Z', '+00:00'))
            end_time = datetime.fromisoformat(result['completed_at'].replace('Z', '+00:00'))
            result['processing_time_seconds'] = (end_time - start_time).total_seconds()
            
            logger.info(f"Successfully processed job {job_id}")
            
        except Exception as e:
            result['status'] = 'failed'
            result['errors'].append(str(e))
            result['failed_at'] = datetime.utcnow().isoformat()
            logger.error(f"Failed to process job {job_id}: {str(e)}")
        
        return result

class PubSubHandler:
    """Handles Pub/Sub message processing"""
    
    def __init__(self):
        self.processor = ImageProcessor(BUCKET_NAME)
        self.subscription_path = subscriber.subscription_path(PROJECT_ID, PUBSUB_SUBSCRIPTION)
        
    def update_job_status(self, job_id: str, result: Dict[str, Any]):
        """Update job status in Firestore"""
        try:
            doc_ref = firestore_client.collection('pixelpipe_jobs').document(job_id)
            doc_ref.update({
                'status': result['status'],
                'processing_result': result,
                'updated_at': firestore.SERVER_TIMESTAMP
            })
            logger.info(f"Updated job status for {job_id}: {result['status']}")
        except Exception as e:
            logger.error(f"Failed to update job status: {str(e)}")
    
    async def process_message(self, message):
        """Process a single Pub/Sub message"""
        try:
            # Parse message data
            job_data = json.loads(message.data.decode('utf-8'))
            job_id = job_data.get('job_id')
            
            logger.info(f"Received message for job {job_id}")
            
            # Process the image
            result = await self.processor.process_image_job(job_data)
            
            # Update job status
            self.update_job_status(job_id, result)
            
            # Acknowledge message
            message.ack()
            logger.info(f"Acknowledged message for job {job_id}")
            
        except Exception as e:
            logger.error(f"Failed to process message: {str(e)}")
            message.nack()

# Initialize handler
pubsub_handler = PubSubHandler()

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'project_id': PROJECT_ID,
        'bucket_name': BUCKET_NAME
    })

@app.route('/process', methods=['POST'])
async def process_single_image():
    """HTTP endpoint for processing single image (for testing)"""
    try:
        job_data = request.get_json()
        if not job_data:
            return jsonify({'error': 'Request body must be JSON'}), 400
        
        # Add required fields if missing
        if 'job_id' not in job_data:
            job_data['job_id'] = str(uuid.uuid4())
        if 'image_id' not in job_data:
            job_data['image_id'] = str(uuid.uuid4())
        
        # Process image
        result = await pubsub_handler.processor.process_image_job(job_data)
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"HTTP processing failed: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/stats', methods=['GET'])
def get_processing_stats():
    """Get processing statistics"""
    try:
        # Query Firestore for job statistics
        jobs_ref = firestore_client.collection('pixelpipe_jobs')
        
        # Get counts by status
        stats = {
            'total_jobs': 0,
            'completed': 0,
            'failed': 0,
            'processing': 0,
            'queued': 0
        }
        
        # Simple aggregation (in production, use proper aggregation queries)
        docs = jobs_ref.limit(1000).stream()  # Limit for demo
        
        for doc in docs:
            data = doc.to_dict()
            status = data.get('status', 'unknown')
            stats['total_jobs'] += 1
            
            if status in stats:
                stats[status] += 1
        
        return jsonify(stats)
        
    except Exception as e:
        logger.error(f"Failed to get stats: {str(e)}")
        return jsonify({'error': str(e)}), 500

def pull_messages():
    """Pull messages from Pub/Sub subscription"""
    
    def callback(message):
        """Callback for processing messages"""
        # Run async processing in thread
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        try:
            loop.run_until_complete(pubsub_handler.process_message(message))
        finally:
            loop.close()
    
    # Configure subscriber
    flow_control = pubsub_v1.types.FlowControl(max_messages=10)
    
    logger.info(f"Starting to pull messages from {pubsub_handler.subscription_path}")
    
    # Start pulling messages
    streaming_pull_future = subscriber.subscribe(
        pubsub_handler.subscription_path,
        callback=callback,
        flow_control=flow_control
    )
    
    return streaming_pull_future

if __name__ == '__main__':
    # Start Pub/Sub subscriber in background thread
    import threading
    
    def start_subscriber():
        try:
            streaming_pull_future = pull_messages()
            
            # Keep subscriber running
            try:
                streaming_pull_future.result()
            except KeyboardInterrupt:
                streaming_pull_future.cancel()
                logger.info("Subscriber cancelled")
                
        except Exception as e:
            logger.error(f"Subscriber failed: {str(e)}")
    
    # Start subscriber thread
    subscriber_thread = threading.Thread(target=start_subscriber, daemon=True)
    subscriber_thread.start()
    
    # Start Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)