#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

if [ "$#" -lt 1 ]; then
  echo "usage: $0 KUBERNETES_MINOR_VERSION [BINARY_BUCKET_REGION] [BINARY_BUCKET_NAME]"
  echo "  BINARY_BUCKET_REGION defaults to us-west-2"
  echo "  BINARY_BUCKET_NAME defaults to amazon-eks"
  exit 1
fi

MINOR_VERSION="${1}"
BINARY_BUCKET_REGION="${2:-us-west-2}"  # Default to us-west-2 if not provided
BINARY_BUCKET_NAME="${3:-amazon-eks}"    # Default to amazon-eks if not provided

export AWS_DEFAULT_REGION=$BINARY_BUCKET_REGION
export AWS_CA_BUNDLE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"
# Set S3 domain based on region
S3_DOMAIN="amazonaws.com"
if [ "$BINARY_BUCKET_REGION" = "cn-north-1" ] || [ "$BINARY_BUCKET_REGION" = "cn-northwest-1" ]; then
  S3_DOMAIN="amazonaws.com.cn"
elif [ "$BINARY_BUCKET_REGION" = "us-iso-east-1" ] || [ "$BINARY_BUCKET_REGION" = "us-iso-west-1" ]; then
  S3_DOMAIN="c2s.ic.gov"
elif [ "$BINARY_BUCKET_REGION" = "us-isob-east-1" ]; then
  S3_DOMAIN="sc2s.sgov.gov"
elif [ "$BINARY_BUCKET_REGION" = "eu-isoe-west-1" ]; then
  S3_DOMAIN="cloud.adc-e.uk"
elif [ "$BINARY_BUCKET_REGION" = "us-isof-south-1" ]; then
  S3_DOMAIN="csp.hci.ic.gov"
fi

# Handle GovCloud regions
if [[ "$BINARY_BUCKET_NAME" == "amazon-eks" ]] && [[ "$BINARY_BUCKET_REGION" =~ (us-gov-east-1|us-gov-west-1) ]]; then
    QUERY_REGION="us-west-2"
else
    QUERY_REGION="${BINARY_BUCKET_REGION}"
fi

# Construct the S3 endpoint URL
S3_ENDPOINT="https://${BINARY_BUCKET_NAME}.s3.${QUERY_REGION}.${S3_DOMAIN}"

# First try using aws s3api
echo "Attempting to fetch binaries using aws s3api..."
LATEST_BINARIES=$(aws s3api list-objects-v2 \
    --region "${QUERY_REGION}" \
    --no-sign-request \
    --bucket "${BINARY_BUCKET_NAME}" \
    --prefix "${MINOR_VERSION}" \
    --query 'Contents[*].[Key]' \
    --output text 2>/dev/null | \
    grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}/bin/linux' | \
    cut -d'/' -f-2 | \
    sort -Vru | \
    head -n1) || true

# If s3api failed, try curl
if [ -z "${LATEST_BINARIES}" ]; then
    echo "s3api failed, attempting to fetch using curl..."
    if ! command -v xmllint >/dev/null 2>&1; then
        echo "Error: xmllint is required but not installed" >&2
        exit 1
    fi
    
    LATEST_BINARIES=$(curl -sf "${S3_ENDPOINT}/?prefix=${MINOR_VERSION}" | \
        xmllint --format --nocdata - 2>/dev/null | \
        grep -E "<Key>${MINOR_VERSION}.*[0-9]{4}-[0-9]{2}-[0-9]{2}/bin/linux" | \
        sed -E 's/.*<Key>([0-9]+\.[0-9]+\.[0-9]+\/[0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/' | \
        sort -Vu | \
        tail -n 1) || {
            echo "Error: Failed to fetch binaries using both s3api and curl" >&2
            exit 1
        }
fi

if [ -z "${LATEST_BINARIES}" ] || [ "${LATEST_BINARIES}" == "None" ]; then
    echo "Error: No binaries available for minor version: ${MINOR_VERSION}" >&2
    exit 1
fi

if ! echo "${LATEST_BINARIES}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+/[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "Error: Invalid binary version format: ${LATEST_BINARIES}" >&2
    exit 1
fi

LATEST_VERSION=$(echo "${LATEST_BINARIES}" | cut -d'/' -f1)
LATEST_BUILD_DATE=$(echo "${LATEST_BINARIES}" | cut -d'/' -f2)

echo "kubernetes_version=${LATEST_VERSION} kubernetes_build_date=${LATEST_BUILD_DATE}"