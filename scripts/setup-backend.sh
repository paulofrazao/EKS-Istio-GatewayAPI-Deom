#!/bin/bash

# Print a starting message
echo "Starting script execution..."

# First command - show current working directory
echo "Start LocalStack:"
localstack start -d
sleep 4  # Pause for 3 seconds

# Second command - show current directory contents
echo "Create S3 bucket for store Terraform state"
aws --endpoint-url http://localhost:4566 --region us-east-1 s3 mb s3://aws_s3_bucket
sleep 3  # Pause for 2 seconds


# Third command - display system information
echo "Terraform init:"
#tflocal init
sleep 2  # Pause for 2 seconds

# Third command - display system information
echo "Terraform apply:"
tflocal apply --auto-approve

# Final message
echo "Script execution complete!"

