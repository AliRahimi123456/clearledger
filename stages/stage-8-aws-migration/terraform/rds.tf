# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: RDS PostgreSQL — managed database replacing the in-cluster StatefulSet.
#          Credentials are pulled from Secrets Manager (secrets.tf).

# ── DB subnet group ───────────────────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "ClearLedger RDS database subnet group"
  subnet_ids  = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ── RDS security group: allow Postgres only from private (EKS) subnets ────────

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL from EKS private subnets only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL from EKS node subnets"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = aws_subnet.private[*].cidr_block
    # Why: RDS is not accessible from the public internet or the database subnets
    # themselves — only from EKS worker nodes in the private subnets.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# ── RDS instance ──────────────────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-postgres"

  engine         = "postgres"
  engine_version = "16"

  # db.t3.micro is free tier eligible (750 hours/month for 12 months).
  # Upgrade to db.t3.small or db.t3.medium for higher connection counts.
  instance_class = "db.t3.micro"

  db_name  = "clearledger"
  username = jsondecode(aws_secretsmanager_secret_version.postgres.secret_string)["username"]
  password = jsondecode(aws_secretsmanager_secret_version.postgres.secret_string)["password"]

  allocated_storage     = 20
  max_allocated_storage = 100 # Why: autoscaling up to 100GB prevents storage-full incidents
  storage_type          = "gp2"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Multi-AZ = false for lab to save cost (~$45/month difference).
  # WARNING: Set to true in production — single-AZ means downtime during
  # instance maintenance or AZ failure.
  multi_az = false

  # skip_final_snapshot = true for lab. In production, always take a final snapshot.
  skip_final_snapshot = true

  # deletion_protection = false for lab so terraform destroy works cleanly.
  # WARNING: Set to true in production to prevent accidental database deletion.
  deletion_protection = false

  backup_retention_period = 1 # minimum; free tier includes automated backups
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
