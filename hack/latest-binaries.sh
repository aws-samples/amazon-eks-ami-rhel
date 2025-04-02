#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

if [ "$#" -lt 1 ]; then
  echo "usage: $0 KUBERNETES_MINOR_VERSION [AWS_REGION] [BINARY_BUCKET_REGION] [BINARY_BUCKET_NAME]"
  echo "  AWS_REGION defaults to BINARY_BUCKET_REGION"
  echo "  BINARY_BUCKET_REGION defaults to us-west-2"
  echo "  BINARY_BUCKET_NAME defaults to amazon-eks"
  exit 1
fi

MINOR_VERSION="${1}"
BINARY_BUCKET_REGION="${3:-us-west-2}"  # Default to us-west-2 if not provided
AWS_REGION="${2:-$BINARY_BUCKET_REGION}" # Default to BINARY_BUCKET_REGION if not provided
BINARY_BUCKET_NAME="${4:-amazon-eks}"    # Default to amazon-eks if not provided

export AWS_DEFAULT_REGION=$BINARY_BUCKET_REGION
export AWS_CA_BUNDLE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

# Handle GovCloud regions
if [[ "$BINARY_BUCKET_NAME" == "amazon-eks" ]] && [[ "$BINARY_BUCKET_REGION" =~ (us-gov-east-1|us-gov-west-1) ]]; then
    QUERY_REGION="us-west-2"
else
    QUERY_REGION="${BINARY_BUCKET_REGION}"
fi

# pass in the --no-sign-request flag if crossing partitions from a us-gov region to a non us-gov region
NO_SIGN_REQUEST=""
if [[ "${AWS_REGION}" == *"us-gov"* ]] && [[ "${BINARY_BUCKET_REGION}" != *"us-gov"* ]]; then
  NO_SIGN_REQUEST="--no-sign-request"
fi

# retrieve the available "VERSION/BUILD_DATE" prefixes
LATEST_BINARIES=$(aws s3api list-objects-v2 \
    "${NO_SIGN_REQUEST}" \
    --region "${QUERY_REGION}" \
    --bucket "${BINARY_BUCKET_NAME}" \
    --prefix "${MINOR_VERSION}" \
    --query 'Contents[*].[Key]' \
    --output text | \
    grep -E '/[0-9]{4}-[0-9]{2}-[0-9]{2}/bin/linux' | \
    cut -d'/' -f-2 | \
    sort -Vru | \
    head -n1)

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