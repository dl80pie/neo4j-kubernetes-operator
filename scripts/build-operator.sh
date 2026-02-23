#!/bin/bash
# Build script for Neo4j Enterprise Operator
# Optimized for OpenShift deployment

set -e

# Configuration
IMAGE_NAME="${IMAGE_NAME:-neo4j-operator}"
VERSION="${VERSION:-$(git describe --tags --always --dirty 2>/dev/null || echo "dev")}"
REGISTRY="${REGISTRY:-harbor.pietsch.uk/library/neo4j}"
DOCKERFILE="${DOCKERFILE:-Dockerfile.openshift}"
PLATFORMS="${PLATFORMS:-linux/amd64}"

# Parse command line arguments
TAG_ARG=""
PUSH_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag=*)
            TAG_ARG="${1#*=}"
            shift
            ;;
        --tag)
            shift
            TAG_ARG="$1"
            shift
            ;;
        --push)
            PUSH_ARG="1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Override VERSION if --tag is provided
if [[ -n "$TAG_ARG" ]]; then
    VERSION="$TAG_ARG"
fi

# Build metadata
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Neo4j Enterprise Operator Build ===${NC}"
echo "Version:    ${VERSION}"
echo "Build Date: ${BUILD_DATE}"
echo "VCS Ref:    ${VCS_REF}"
echo "Registry:   ${REGISTRY}"
echo "Dockerfile: ${DOCKERFILE}"
echo ""

# Detect container runtime
if command -v podman &> /dev/null; then
    CONTAINER_RUNTIME="podman"
elif command -v docker &> /dev/null; then
    CONTAINER_RUNTIME="docker"
else
    echo -e "${RED}Error: Neither podman nor docker found${NC}"
    exit 1
fi

echo -e "${YELLOW}Using container runtime: ${CONTAINER_RUNTIME}${NC}"

# Build the image
echo -e "${GREEN}Building image...${NC}"
${CONTAINER_RUNTIME} build \
    -f "${DOCKERFILE}" \
    -t "${IMAGE_NAME}:${VERSION}" \
    -t "${IMAGE_NAME}:latest" \
    --platform="linux/amd64" \
    --build-arg VERSION="${VERSION}" \
    --build-arg BUILD_DATE="${BUILD_DATE}" \
    --build-arg VCS_REF="${VCS_REF}" \
    .

echo -e "${GREEN}Build successful!${NC}"
echo ""

# Tag for registry
echo -e "${GREEN}Tagging for registry...${NC}"
${CONTAINER_RUNTIME} tag "${IMAGE_NAME}:${VERSION}" "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
${CONTAINER_RUNTIME} tag "${IMAGE_NAME}:latest" "${REGISTRY}/${IMAGE_NAME}:latest"

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo ""
echo "Local images:"
echo "  - ${IMAGE_NAME}:${VERSION}"
echo "  - ${IMAGE_NAME}:latest"
echo ""
echo "Registry images (ready to push):"
echo "  - ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo "  - ${REGISTRY}/${IMAGE_NAME}:latest"
echo ""
echo -e "${YELLOW}To push to registry:${NC}"
echo "  ${CONTAINER_RUNTIME} push ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
echo "  ${CONTAINER_RUNTIME} push ${REGISTRY}/${IMAGE_NAME}:latest"
echo ""

# Optional: Push if --push flag is provided
if [[ -n "$PUSH_ARG" ]]; then
    echo -e "${GREEN}Pushing to registry...${NC}"
    ${CONTAINER_RUNTIME} push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    ${CONTAINER_RUNTIME} push "${REGISTRY}/${IMAGE_NAME}:latest"
    echo -e "${GREEN}Push complete!${NC}"
fi
