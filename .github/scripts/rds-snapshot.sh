#!/bin/bash
#================================================================
# HEADER
#================================================================
#% SYNOPSIS
#+    AWS RDS Snapshot Creation
#%
#% DESCRIPTION
#%    This script will intantiate a new AWS CLI instance and associated
#%    profile. Once intialized the CLI will then create a AWS RDS snapshot
#%    of the provided RDS database and await a set period of time for the backup to
#%    be completed before returning 0 (success) and allowing any follow up
#%    processing to be completed. All options are controlled by the .env
#%
#================================================================
#- IMPLEMENTATION
#-    version         1.0
#-    author          Brandon Mercer
#-    repository      https://github.com/noprotocol/devops-shared
#-
#================================================================
#  HISTORY
#     01/07/2023 : brandonm : Script creation
#     07/07/2023 : brandonm : Added remove old snapshots
#     21/07/2023 : brandonm : Added this descriptor
#
#================================================================
# END_OF_HEADER
#================================================================

set -e

createTimestampMessage() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    message="[$timestamp] - $1"
    echo "$message"
}

parseEnvFile() {
    filePath="$1"
    if [[ -f "$filePath" ]]; then
        while IFS='=' read -r key value; do
            if [[ ! -z "$key" && ! -z "$value" ]]; then
                export "$key"="$value"
            fi
        done <"$filePath"
    else
        echo " No local .env file detected. Falling back to SYSTEM environment variables."
    fi
}

removeOldSnapshots() {
    # Iterate over each snapshot in the JSON
    echo "$1" | jq -r '.DBSnapshots[] | .DBSnapshotIdentifier, .SnapshotCreateTime, .SnapshotType' |
        while read -r snapshot_identifier && read -r snapshot_create_time && read -r snapshot_type; do
            # Use the snapshot_identifier and snapshot_create_time in another function
            # Replace the following echo statement with your desired function call
            current_datetime=$(date -u +%Y-%m-%dT%H:%M:%S.%N%z)

            if [ -n "$snapshot_create_time" ]; then
                if [[ "$snapshot_create_time" != "null" && "$snapshot_type" != "automated" ]]; then
                    datetime_timestamp=$(date -u -d "$snapshot_create_time" +%s)
                    current_datetime_timestamp=$(date -u -d "$current_datetime" +%s)

                    seven_days_seconds=$((7 * 24 * 60 * 60))
                    threshold_timestamp=$((current_datetime_timestamp - seven_days_seconds))

                    if [[ $datetime_timestamp -lt $threshold_timestamp ]]; then
                        createTimestampMessage "deleting = $snapshot_identifier, reason = The snapshot is older than 7 days."
                        aws rds delete-db-snapshot --db-snapshot-identifier $snapshot_identifier
                    fi
                fi
            fi
        done
    oldSnapshotsRemoved=true
}

# Load environment variables from .env file or system environment variables
parseEnvFile "/var/www/html/.env"
environment="$APP_ENV"
createTimestampMessage "Environment - $environment"

if [[ "$environment" != "production" ]]; then
    createTimestampMessage "This is not a production environment. No automated snapshots will be created."
    exit 0
fi

# Configure AWS credentials and region
access_key="$AWS_RDS_ACCESS_KEY_ID"
secret_key="$AWS_RDS_SECRET_ACCESS_KEY"
region="$AWS_RDS_DEFAULT_REGION"

# Configure AWS Snapshot search
maxAttempts="$AWS_RDS_SNAPSHOT_SEARCH_ATTEMPTS"
delay="$AWS_RDS_SNAPSHOT_SEARCH_DELAY"

# Set the RDS instance identifier and snapshot identifier
rdsInstanceIdentifier="$AWS_RDS_INSTANCE_ID"
createTimestampMessage "RDS Instance Identifier: $rdsInstanceIdentifier"
snapshotIdentifier="$rdsInstanceIdentifier-$(date '+%Y%m%d-%H%M%S')"
createTimestampMessage "Snapshot Identifier: $snapshotIdentifier"

# Set AWS credentials and region for the AWS CLI profile
export AWS_ACCESS_KEY_ID="$access_key"
export AWS_SECRET_ACCESS_KEY="$secret_key"
export AWS_DEFAULT_REGION="$region"

# Create the RDS snapshot
aws rds create-db-snapshot --db-instance-identifier "$rdsInstanceIdentifier" --db-snapshot-identifier "$snapshotIdentifier"
createTimestampMessage "Creating snapshot: $snapshotIdentifier"

# Start the long polling loop
startTime=$(date +%s)
attempts=0
snapshotFound=false
oldSnapshotsRemoved=false

while true; do
    if [[ "$snapshotFound" == false ]]; then
        createTimestampMessage "Searching Snapshots for DBInstanceIdentifier: $snapshotIdentifier"
    fi

    result=$(aws rds describe-db-snapshots --db-instance-identifier "$rdsInstanceIdentifier")

    if [[ "$oldSnapshotsRemoved" == false ]]; then
        removeOldSnapshots "$result"
    fi

    snapshots=$(echo "$result" | jq '.DBSnapshots')
    if [[ $(echo "$snapshots" | jq 'length') -gt 0 ]]; then

        # There are snapshots, process them
        snapshotIdentifiers=$(echo "$snapshots" | jq -r '.[].DBSnapshotIdentifier')

        for currentSnapshotIdentifier in $snapshotIdentifiers; do

            # Rest of your code for processing each snapshot
            if [[ "$currentSnapshotIdentifier" == "$snapshotIdentifier" ]]; then
                if [[ "$snapshotFound" == false ]]; then
                    createTimestampMessage "Snapshot Found."
                    snapshotFound=true
                fi

                # Additional loop to continuously check progress
                while true; do
                    result=$(aws rds describe-db-snapshots --db-snapshot-identifier "$snapshotIdentifier")
                    snapshot=$(echo "$result" | jq -r '.DBSnapshots[] | select(.DBSnapshotIdentifier == "'"$snapshotIdentifier"'")')

                    if [[ -z "$snapshot" ]]; then
                        createTimestampMessage "Snapshot not found. Possible failure in the backup process."
                        exit 1
                    fi

                    status=$(echo "$snapshot" | jq -r '.Status')
                    progress=$(echo "$snapshot" | jq -r '.PercentProgress')
                    createTimestampMessage "Snapshot Status: $status Progress: $progress%"

                    if [[ "$status" == "available" ]]; then
                        createTimestampMessage "Snapshot creation completed successfully."
                        exit 0
                    fi

                    sleep $delay
                done
                # End of additional loop for progress checking
            fi
        done
    fi

    if [[ $(($(date +%s) - startTime)) -gt $maxAttempts ]]; then
        createTimestampMessage "Timeout: Snapshot creation did not complete within the allotted time."
        exit 1
    fi

    sleep $delay
done
