#!/usr/bin/env python3
"""
Cloud Function: CSV Ingestion Handler
Triggered when CSV is uploaded to bucket, processes URLs and sends to Pub/Sub
"""

import os
import json
import csv
import logging
from typing import Dict, List, Any
from datetime import datetime
import functions_framework
from google.cloud import storage, pubsub_v1, firestore
from io import StringIO
import uuid

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('GCP_PROJECT', 'aya-internship')
PUBSUB_TOPIC = os.environ.get('PUBSUB_TOPIC', 'pixelpipe-image-processing-dev')
FIRESTORE_COLLECTION = 'pixelpipe_jobs'

# Initialize clients
storage_client = storage.Client()
publisher = pubsub_v1.PublisherClient()
firestore_client = firestore.Client()

class CSVIngestionHandler:
    """Handles CSV ingestion and job distribution"""
    
    def __init__(self):
        self.topic_path = publisher.topic_path(PROJECT_ID, PUBSUB_TOPIC)
        
    def validate_csv_row(self, row: Dict[str, str]) -> Dict[str, Any]:
        """Validate a single CSV row"""
        validation_result = {
            'valid': True,
            'errors': [],
            'warnings': []
        }
        
        # Required fields
        required_fields = ['id', 'url', 'category', 'priority']
        for field in required_fields:
            if not row.get(field):
                validation_result['valid'] = False
                validation_result['errors'].append(f"Missing required field: {field}")
        
        # URL validation (basic)
        url = row.get('url', '')
        if url and not (url.startswith('http://') or url.startswith('https://')):
            validation_result['valid'] = False
            validation_result['errors'].append(f"Invalid URL format: {url}")
        
        # Priority validation
        valid_priorities = ['low', 'medium', 'high']
        priority = row.get('priority', '').lower()
        if priority and priority not in valid_priorities:
            validation_result['warnings'].append(f"Invalid priority: {priority}, defaulting to 'medium'")
            row['priority'] = 'medium'
            
        return validation_result, row
    
    def create_processing_job(self, row: Dict[str, str], job_id: str) -> Dict[str, Any]:
        """Create a processing job from CSV row"""
        return {
            'job_id': job_id,
            'image_id': row.get('id', str(uuid.uuid4())),
            'url': row['url'],
            'priority': row.get('priority', 'medium'),
            'category': row.get('category', 'unknown'),
            'expected_size': row.get('expected_size', 'unknown'),
            'processing_options': {
                'create_thumbnail': True,
                'extract_metadata': True,
                'resize_formats': ['800x600', '400x300', '200x150'],
                'output_formats': ['jpeg', 'webp']
            },
            'retry_count': 0,
            'max_retries': 3,
            'created_at': datetime.utcnow().isoformat(),
            'status': 'queued',
            'batch_id': job_id  # Group related jobs
        }
    
    def publish_job_to_pubsub(self, job: Dict[str, Any]) -> bool:
        """Publish job to Pub/Sub for processing"""
        try:
            # Serialize job data
            message_data = json.dumps(job).encode('utf-8')
            
            # Add message attributes for routing/filtering
            attributes = {
                'priority': job['priority'],
                'category': job['category'],
                'job_type': 'image_processing',
                'batch_id': job['batch_id']
            }
            
            # Publish message
            future = publisher.publish(
                topic=self.topic_path,
                data=message_data,
                **attributes
            )
            
            # Wait for confirmation
            message_id = future.result(timeout=30)
            logger.info(f"Published job {job['job_id']} to Pub/Sub: {message_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to publish job {job['job_id']}: {str(e)}")
            return False
    
    def save_job_metadata(self, job: Dict[str, Any], validation_result: Dict[str, Any]):
        """Save job metadata to Firestore for tracking"""
        try:
            doc_ref = firestore_client.collection(FIRESTORE_COLLECTION).document(job['job_id'])
            doc_ref.set({
                **job,
                'validation': validation_result,
                'firestore_created_at': firestore.SERVER_TIMESTAMP
            })
            logger.info(f"Saved job metadata for {job['job_id']}")
        except Exception as e:
            logger.error(f"Failed to save job metadata: {str(e)}")
    
    def process_csv_file(self, bucket_name: str, file_name: str) -> Dict[str, Any]:
        """Process uploaded CSV file"""
        logger.info(f"Processing CSV file: gs://{bucket_name}/{file_name}")
        
        try:
            # Download CSV from bucket
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(file_name)
            csv_content = blob.download_as_text()
            
            # Parse CSV
            csv_reader = csv.DictReader(StringIO(csv_content))
            
            # Process each row
            batch_id = str(uuid.uuid4())
            results = {
                'batch_id': batch_id,
                'total_rows': 0,
                'successful_jobs': 0,
                'failed_validations': 0,
                'failed_publishes': 0,
                'processing_started_at': datetime.utcnow().isoformat(),
                'jobs': []
            }
            
            for row_num, row in enumerate(csv_reader, 1):
                results['total_rows'] += 1
                job_id = f"{batch_id}_{row_num:03d}"
                
                # Validate row
                validation_result, validated_row = self.validate_csv_row(row)
                
                if not validation_result['valid']:
                    logger.error(f"Row {row_num} validation failed: {validation_result['errors']}")
                    results['failed_validations'] += 1
                    continue
                
                # Create processing job
                job = self.create_processing_job(validated_row, job_id)
                
                # Save job metadata
                self.save_job_metadata(job, validation_result)
                
                # Publish to Pub/Sub
                if self.publish_job_to_pubsub(job):
                    results['successful_jobs'] += 1
                    results['jobs'].append({
                        'job_id': job_id,
                        'url': job['url'],
                        'status': 'queued'
                    })
                else:
                    results['failed_publishes'] += 1
            
            results['processing_completed_at'] = datetime.utcnow().isoformat()
            logger.info(f"CSV processing completed: {results}")
            
            return results
            
        except Exception as e:
            logger.error(f"Failed to process CSV: {str(e)}")
            raise

@functions_framework.cloud_event
def csv_upload_trigger(cloud_event):
    """Cloud Function triggered by CSV upload to bucket"""
    
    # Extract event data
    event_data = cloud_event.data
    bucket_name = event_data['bucket']
    file_name = event_data['name']
    
    logger.info(f"Triggered by file upload: gs://{bucket_name}/{file_name}")
    
    # Only process CSV files
    if not file_name.lower().endswith('.csv'):
        logger.info(f"Ignoring non-CSV file: {file_name}")
        return {'status': 'ignored', 'reason': 'not a CSV file'}
    
    try:
        # Initialize handler and process CSV
        handler = CSVIngestionHandler()
        results = handler.process_csv_file(bucket_name, file_name)
        
        # Return success response
        return {
            'status': 'success',
            'message': f"Successfully processed {results['successful_jobs']} jobs from CSV",
            'batch_id': results['batch_id'],
            'details': results
        }
        
    except Exception as e:
        logger.error(f"Function execution failed: {str(e)}")
        return {
            'status': 'error', 
            'message': str(e)
        }

@functions_framework.http
def manual_csv_trigger(request):
    """HTTP endpoint for manual CSV processing"""
    
    if request.method != 'POST':
        return {'error': 'Only POST method allowed'}, 405
    
    try:
        # Parse request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Request body must be JSON'}, 400
            
        bucket_name = request_json.get('bucket_name')
        file_name = request_json.get('file_name')
        
        if not bucket_name or not file_name:
            return {'error': 'bucket_name and file_name are required'}, 400
        
        # Process CSV
        handler = CSVIngestionHandler()
        results = handler.process_csv_file(bucket_name, file_name)
        
        return {
            'status': 'success',
            'results': results
        }
        
    except Exception as e:
        logger.error(f"Manual trigger failed: {str(e)}")
        return {'error': str(e)}, 500

# Health check endpoint
@functions_framework.http 
def health_check(request):
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'project_id': PROJECT_ID,
        'pubsub_topic': PUBSUB_TOPIC
    }