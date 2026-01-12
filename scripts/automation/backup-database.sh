#!/bin/bash
# Database backup script with cloud storage support

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/analytics_backup_$TIMESTAMP.sql"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo -e "${GREEN}Starting database backup...${NC}"

# Check if DATABASE_URL is set
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}ERROR: DATABASE_URL environment variable is not set${NC}"
    exit 1
fi

# Perform backup
echo -e "${YELLOW}Creating backup: $BACKUP_FILE${NC}"
pg_dump "$DATABASE_URL" > "$BACKUP_FILE"

# Compress backup
echo -e "${YELLOW}Compressing backup...${NC}"
gzip "$BACKUP_FILE"
BACKUP_FILE="$BACKUP_FILE.gz"

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo -e "${GREEN}Backup created: $BACKUP_FILE ($BACKUP_SIZE)${NC}"

# Upload to Azure Blob Storage (if configured)
if [ -n "$AZURE_STORAGE_ACCOUNT" ] && [ -n "$AZURE_STORAGE_KEY" ]; then
    echo -e "${YELLOW}Uploading to Azure Blob Storage...${NC}"
    az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name backups \
        --name "$(basename $BACKUP_FILE)" \
        --file "$BACKUP_FILE" \
        --overwrite
    echo -e "${GREEN}Uploaded to Azure Blob Storage${NC}"
fi

# Upload to AWS S3 (if configured)
if [ -n "$AWS_S3_BUCKET" ]; then
    echo -e "${YELLOW}Uploading to AWS S3...${NC}"
    aws s3 cp "$BACKUP_FILE" "s3://$AWS_S3_BUCKET/backups/$(basename $BACKUP_FILE)"
    echo -e "${GREEN}Uploaded to AWS S3${NC}"
fi

# Cleanup old backups
echo -e "${YELLOW}Cleaning up old backups (older than $RETENTION_DAYS days)...${NC}"
find "$BACKUP_DIR" -name "analytics_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
REMAINING=$(ls -1 "$BACKUP_DIR"/analytics_backup_*.sql.gz 2>/dev/null | wc -l)
echo -e "${GREEN}Local backups remaining: $REMAINING${NC}"

echo -e "${GREEN}✅ Backup completed successfully!${NC}"
