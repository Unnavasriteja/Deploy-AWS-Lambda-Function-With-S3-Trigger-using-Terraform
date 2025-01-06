# Deploy AWS Lambda Function with S3 Trigger Using Terraform

## Scenario
A team receives numerous files from a third-party vendor, who uploads them to an S3 bucket. These files are suffixed with date stamps. Over time, we accumulated over a thousand files, which presented a challenge since S3 doesn’t allow sorting objects by date when there are over 1,000 objects.

The team performs daily checks, downloading the current day’s file to process the information. However, they struggled to sort and locate the latest files efficiently. To address this issue, we developed a Lambda function that organizes files in a specific path into folders structured by year/month/day.

---

## Implementation
1. **Terraform** will provision the Lambda function.
2. **Python** will be used as the Lambda runtime.
3. The Python script will:
   - Pick the files uploaded to a path.
   - Move them to their respective folder structured by year, month, and date.
4. **S3 notification** will trigger the Lambda when new files are uploaded to a specific bucket path.

---

## Prerequisites
- Basic understanding of AWS services (Lambda, S3, IAM, etc.).
- Familiarity with Python and the `boto3` SDK.
- Basic knowledge of Terraform.

---

## Project Setup
The file structure will look like this:
```plaintext
.
├── lambda_functions
│   └── main.py
├── versions.tf
├── lambda.tf
├── backend.tf
├── pre-setup-script.sh
```

Before writing the Terraform code:
- Create a bucket named `inbound-bucket-custome` with a folder `incoming`.
- Create another bucket for storing the Terraform state: `my-backend-devops101-terraform`.

---

## Python Script for Lambda Function
**Path:** `lambda_functions/main.py`
```python
import os
import boto3

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    bucket_name = os.getenv("BUCKET_NAME")
    prefix = os.getenv("BUCKET_PATH")

    response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)

    if 'Contents' in response:
        for obj in response['Contents']:
            key = obj['Key']
            date_parts = key.split('-')[-1].replace('.txt', '').split('/')
            if len(date_parts) == 3:
                year, month, day = date_parts
                new_key = f"organized/{year}/{month}/{day}/{os.path.basename(key)}"
                s3.copy_object(Bucket=bucket_name, CopySource={'Bucket': bucket_name, 'Key': key}, Key=new_key)
                s3.delete_object(Bucket=bucket_name, Key=key)
```

---

## Terraform Deployment

### Setting up Terraform Providers and Backend
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
    bucket         = "my-backend-devops101-terraform"
    key            = "lambda/terraform.tfstate"
    region         = "ap-south-1"
  }
}
```

### Packaging Python Code as a Zip File
**File:** `lambda.tf`
```hcl
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_functions"
  output_path = "${path.module}/lambda_functions/main.zip"
}
```

### Creating Lambda Function
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
      BUCKET_NAME = "inbound-bucket-custome"
      BUCKET_PATH = "incoming"
    }
  }
}
```

### Creating Lambda Execution Role and Policies
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
          "arn:aws:s3:::inbound-bucket-custome",
          "arn:aws:s3:::inbound-bucket-custome/*"
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

### Creating S3 Trigger for Lambda
```hcl
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_organizer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::inbound-bucket-custome"
}

resource "aws_s3_bucket_notification" "s3_event" {
  bucket = "inbound-bucket-custome"

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_organizer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "incoming/"
  }
}
```

---

## Testing the Setup
**Script:** `pre-setup-script.sh`
```bash
#!/bin/bash

# Define the S3 bucket name
S3_BUCKET="inbound-bucket-custome"

# Create 10 files with the format filename-randomnumber-yyyy-mm-dd
for i in {1..10}; do
    RANDOM_NUMBER=$((1 + RANDOM % 1000))
    FILENAME="filename-$RANDOM_NUMBER-$(date +%Y-%m-%d).txt"
    echo "This is file number $i" > $FILENAME
    aws s3 cp $FILENAME s3://$S3_BUCKET/incoming/
done
```

Run the script to upload files to the bucket. This will trigger the Lambda function, which organizes the files into folders based on their date stamps.

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

