#!/usr/bin/env bash
# Simulates supply-chain "drift": rebuilds the same app OUTSIDE the Harness
# pipeline and pushes it straight to the registry with plain `docker push`.
# Because it never goes through the Build_Sign_and_Attest stage, the pushed
# tag has no Cosign signature and no SLSA provenance attestation attached --
# i.e. an "unsigned rebuild" masquerading under a tag you point the Verify
# stage at.
#
# Usage:
#   ./scripts/simulate_drift.sh <dockerhub-username> <drift-tag>
#
# Example:
#   ./scripts/simulate_drift.sh nidayra v1-drift
#
# Then in Harness: Run Pipeline -> run only the "Verify and Detect Drift"
# stage -> set artifact_tag to the drift tag above. The
# "Verify Artifact Signature" and "Verify SLSA Provenance" steps should fail.
#
# NOTE for Apple Silicon / ARM machines: Docker Desktop's DEFAULT buildx
# builder uses the "docker" driver, which silently ignores --platform for a
# non-native arch and just builds native anyway -- no error, no warning.
# Only the "docker-container" driver actually does QEMU-based cross-platform
# builds. This script creates/uses a dedicated builder with that driver
# (see below) so --platform linux/amd64 is honored regardless of what your
# default builder is set to.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <dockerhub-username> <drift-tag>" >&2
  exit 1
fi

DOCKERHUB_USER="$1"
DRIFT_TAG="$2"
IMAGE="docker.io/${DOCKERHUB_USER}/scs-tidbit-drift-app:${DRIFT_TAG}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDER_NAME="scs_tidbit_drift_builder"

echo "--- Ensuring a docker-container buildx builder exists (for real cross-platform builds) ---"
if ! docker buildx inspect "${BUILDER_NAME}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container
fi
docker buildx inspect "${BUILDER_NAME}" --bootstrap >/dev/null

echo "--- Building + pushing image OUTSIDE the Harness pipeline (no signing, no provenance) ---"
echo "    (forcing linux/amd64 so this matches what the Harness Cloud build produced."
echo "     --provenance=false keeps the pushed manifest to a single, plain image --"
echo "     Docker's own buildx provenance attestation is unrelated to the Harness SLSA"
echo "     attestation this Tidbit is about, and would otherwise show up as a confusing"
echo "     extra 'unknown/unknown' entry in 'docker manifest inspect'.)"
echo "    (buildx cannot --load a non-native-arch image into the local engine, so this"
echo "     pushes straight to the registry -- make sure you're logged in: docker login)"
docker buildx build \
  --builder "${BUILDER_NAME}" \
  --platform linux/amd64 \
  --provenance=false \
  --push \
  -t "${IMAGE}" \
  "${REPO_ROOT}"

echo "--- Verifying the pushed manifest is actually linux/amd64 ---"
docker buildx imagetools inspect "${IMAGE}"

cat <<EOF

Drift simulated: ${IMAGE} now exists in the registry with no Cosign
signature and no SLSA provenance attestation.

Next step: in Harness, run "scs-tidbits-drift-detection" -> select only the
"Verify and Detect Drift" stage -> set artifact_tag = ${DRIFT_TAG}
-> Run. Expect both verification steps to fail.
EOF
