# Primary region: Sydney. Disaster-recovery region: Melbourne. Both are in Australia,
# so data stays onshore even when the DR copy is switched on.
provider "aws" {
  region = var.region

  default_tags {
    tags = merge({
      Project     = "nice-cxone-enterprise-insurance-lab"
      Environment = var.environment
      ManagedBy   = "opentofu"
    }, var.tags)
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  default_tags {
    tags = merge({
      Project     = "nice-cxone-enterprise-insurance-lab"
      Environment = var.environment
      ManagedBy   = "opentofu"
    }, var.tags)
  }
}
