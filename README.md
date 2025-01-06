# Deploy AWS Lambda Function with S3 Trigger Using Terraform

## Scenario
A team receives numerous files from a third-party vendor, who uploads them to an S3 bucket. These files are suffixed with date stamps. Over time, more than a thousand files were accumulated, presenting challenges because S3 doesn’t allow sorting objects by date when the number exceeds 1,000.

The team performed daily checks, downloading the current day’s file for processing. However, they struggled to efficiently locate the latest files. To address this issue, a Lambda function was developed to organize files in a specific path into folders structured by `year/month/day`.

---

## Implementation
1. **Terraform** provisions the Lambda function and supporting AWS resources.
2. **Python** is used as the Lambda runtime.
3. The Python script:
   - Identifies files uploaded to a specific S3 path.
   - Moves them to folders structured by `year/month/day`.
4. **S3 notifications** trigger the Lambda function whenever new files are uploaded.

---

## Prerequisites
- AWS services knowledge (Lambda, S3, IAM, etc.).
- Familiarity with Python and the `boto3` SDK.
- Basic Terraform knowledge and installation.

---

## Project Structure
```plaintext
.
├── lambda_functions
│   └── main.py          # Python script for the Lambda function
├── versions.tf          # Terraform providers and backend configuration
├── lambda.tf            # Terraform resources for Lambda and S3
├── backend.tf           # Optional: Separate backend configuration
├── pre-setup-script.sh  # Test script to upload files
```

---

## Python Script for Lambda Function

**File:** `lambda_functions/main.py`
```python
import os
import boto3

def lambda_handler(event, context):
    # Initialize S3 client
    s3 = boto3.client('s3')
    bucket_name = os.getenv("BUCKET_NAME")
    prefix = os.getenv("BUCKET_PATH")

    # List objects in the specified prefix
    response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

    if 'Contents' in response:
        for obj in response['Contents']:
            key = obj['Key']
            # Extract year, month, and day from the file name
            date_parts = key.split('-')[-1].replace('.txt', '').split('/')
            if len(date_parts) == 3:
                year, month, day = date_parts
                new_key = f"organized/{year}/{month}/{day}/{os.path.basename(key)}"
                # Copy the file to the new path and delete the original
                s3.copy_object(Bucket=bucket_name, CopySource={'Bucket': bucket_name, 'Key': key}, Key=new_key)
                s3.delete_object(Bucket=bucket_name, Key=key)
```

---

## Deployment with Terraform

### Setting Up Terraform Providers and Backend
**File:** `versions.tf`
```hcl
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "my-backend-devops-terraform"
    key            = "lambda/terraform.tfstate"
    region         = "ap-south-1"
  }
}
```

### Creating the Lambda Function and Trigger
**File:** `lambda.tf`
```hcl
resource "aws_lambda_function" "s3_organizer" {
  function_name    = "s3-organizer"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "main.lambda_handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = "inbound-bucket-customer"
      BUCKET_PATH = "incoming"
    }
  }
}
```

### Lambda Execution Role and Policies
**File:** `lambda.tf`
```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "lambda_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::inbound-bucket-customer",
          "arn:aws:s3:::inbound-bucket-customer/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
```

---

## Testing the Setup
**File:** `pre-setup-script.sh`
```bash
#!/bin/bash

# Define the S3 bucket name
S3_BUCKET="inbound-bucket-customer"

# Create 10 files and upload them to S3
for i in {1..10}; do
    RANDOM_NUMBER=$((1 + RANDOM % 1000))
    FILENAME="filename-$RANDOM_NUMBER-$(date +%Y-%m-%d).txt"
    echo "This is file number $i" > $FILENAME
    aws s3 cp $FILENAME s3://$S3_BUCKET/incoming/
done
```

---

## Deployment Commands
```bash
# Initialize Terraform
terraform init

# Plan Terraform
terraform plan

# Apply Terraform
terraform apply
```

---

## Troubleshooting
- **Error: Bucket does not exist**: Ensure the S3 bucket exists before running the Terraform configuration.
- **Lambda Invocation Errors**: Check IAM permissions for the Lambda function and S3 bucket.

---
