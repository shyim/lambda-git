#!/usr/bin/env bash

set -euo pipefail
ROOTDIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")/../")
export ROOTDIR
cd "$ROOTDIR"

BUCKET_PREFIX="shyim-lambda-git-"

source "./includes/utils.sh"
source "./includes/aws_utils.sh"


ARCH="${1:-}"
if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" ]]; then
    fatal 129 "Missing architecture argument"
fi

GIT_VERSION="$(cat ./git_version)"
if [[ -z "${REVISION:-}" ]]; then
    REVISION=""
else
    REVISION="-${REVISION}"
fi

LAYER_PREFIX="shyim-git-"
S3_FILENAME="layer-${GIT_VERSION}${REVISION}-${ARCH}.zip"
DESCRIPTION="Git ${GIT_VERSION}, OpenSSH and OpenSSL for ${ARCH} AWS Lambdas"
ARM_SUPPORTED_REGIONS="eu-central-1"

if [[ "${ARCH}" == "x86_64" ]]; then
    REGIONS="$ARM_SUPPORTED_REGIONS"
elif [[ "${ARCH}" == "arm64" ]]; then
    REGIONS="$ARM_SUPPORTED_REGIONS"
else
    REGIONS=""
fi
step "Publishing ${ARCH} layer"

# Upload to the first region on the list
FIRST_REGION="$(echo $REGIONS | cut -d' ' -f1)"
info "Uploading layer to S3 on ${FIRST_REGION}"
aws --region $FIRST_REGION s3api get-object-acl --bucket "${BUCKET_PREFIX}${FIRST_REGION}" --key releases/${S3_FILENAME} --output text >/dev/null 2>&1 && warn "Layer already exists in ${FIRST_REGION}, skipping upload" \
    || aws --region ${FIRST_REGION} s3api put-object --bucket "${BUCKET_PREFIX}${FIRST_REGION}" --key "releases/${S3_FILENAME}" --body "${ROOTDIR}/outputs/layer-git-${GIT_VERSION}-${ARCH}.zip" >s3_upload.log 2>&1 || fatal 135 "S3 upload failed. See ${ROOTDIR}/s3_upload.log for details."
rm -f s3_upload.log

# Publish on all regions
for region in $REGIONS; do
    info "Publishing lambda layer in ${region}…"
    ARCH_STRING="--compatible-architectures ${ARCH}"
    if [[ $ARM_SUPPORTED_REGIONS != *"${region}"* ]]; then
        ARCH_STRING=""
    fi
    LAYER_VERSION=$(aws --region $region lambda publish-layer-version \
            --layer-name "${LAYER_PREFIX}${ARCH}" \
            --content "S3Bucket=${BUCKET_PREFIX}${region},S3Key=releases/${S3_FILENAME}" \
            --description "$DESCRIPTION" \
            --query Version \
            ${ARCH_STRING} \
            --output text 2>layer_publish.log) \
        || fatal 137 "Layer publishing failed. See ${ROOTDIR}/layer_publish.log for details."
    rm -f layer_publish.log
    info "Published ${region} layer version ${LAYER_VERSION}"
    info "Adding layer permissions…"
    aws --region $region lambda add-layer-version-permission \
        --layer-name "${LAYER_PREFIX}${ARCH}" \
        --statement-id sid1337 \
        --action lambda:GetLayerVersion \
        --principal '*' \
        --version-number "${LAYER_VERSION}" >lambda_permissions.log 2>&1 || fatal 136 "Assigning permissions failed. See ${ROOTDIR}/s3lambda_permissions_copy.log for details."
    rm -f lambda_permissions.log
    info "${region} finished"
done
