terraform {
  required_version = ">= 1.6.0, <= 1.10.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.32.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# remote backend
terraform {
  backend "s3" {
    bucket         = "my-backend-devops-terraform"
    key            = "lambda-function/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
  }
}
