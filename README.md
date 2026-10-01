# SCS | Tidbits | Drift Detection

> **Bite-sized how-to** | ~20 min setup


## What is Drift Detection?

An artifact "drifts" from its approved provenance when what's running in production no longer matches what your pipeline actually built and signed -- most simply, someone rebuilds an image outside CI and pushes it under a trusted tag.

Harness SCS (Supply Chain Security) lets you attach a signed SLSA provenance attestation to every artifact your pipeline builds, then independently re-verify that attestation -- and the artifact's Cosign signature -- before that artifact is trusted downstream. An unsigned rebuild has no valid attestation and no valid signature at all, so verification fails outright.


## What does this Tidbit demonstrate?

A two-stage CI pipeline that builds a signed, attested artifact and can independently re-verify any tag for drift:

1. **Build, Sign and Attest** -- builds and pushes the Docker image, signs it with Cosign (`SscaArtifactSigning`), and generates a signed SLSA provenance attestation for it (`provenance`)
2. **Verify and Detect Drift** -- independently re-checks the artifact's signature (`SscaArtifactVerification`) and its SLSA provenance (`SlsaVerification`) for any tag you give it

A `scripts/simulate_drift.sh` script rebuilds the same app *outside* the pipeline and pushes it under a tag of your choice, with no signature and no provenance -- so you can point the Verify stage at it and watch drift get caught.


## Key Concepts

**SLSA Provenance** -- a signed record of where an artifact came from: the build platform, the process that built it, and its source materials. Harness generates this automatically during the build and signs it with Cosign.

**`provenance` step** -- generates and signs the SLSA provenance attestation for a just-built image and pushes it alongside the artifact.

**`SlsaVerification` step** -- re-verifies a provenance attestation's signature for a given artifact tag/digest.

**`SscaArtifactSigning` / `SscaArtifactVerification` steps** -- sign an artifact with Cosign, and independently verify that signature. This checks the artifact itself, separate from its provenance.

**Keyless (OIDC) signing/verification** -- Cosign identities backed by short-lived, OIDC-issued certificates (Harness's own OIDC provider, in this Tidbit) instead of long-lived key pairs. No key material to manage or leak.

**Drift** -- an artifact under a trusted tag whose actual signature/provenance no longer matches what your pipeline approved. This Tidbit demonstrates the simplest and most common case: no valid attestation at all, because the artifact never went through the pipeline.


## Prerequisites

Before you start, make sure you have:

- A Harness account with the SCS module enabled
- A Harness CI pipeline with build infrastructure -- Harness Cloud or a Kubernetes cluster with a Harness delegate
- A Docker Hub connector configured in Harness
- A GitHub connector pointing to this repository
- Docker installed locally (for `scripts/simulate_drift.sh`)


## Step 0 -- Set Up Connectors

Configure two connectors in **Project Settings -> Connectors -> + New Connector**:

**GitHub Connector**
- Select **GitHub** as the connector type
- Enter your GitHub repository URL and credentials (personal access token or OAuth)
- Test the connection
- Note the **connector identifier** -- you will need it for the pipeline YAML

**Docker Hub Connector**
- Select **Docker Registry** as the connector type
- Provider: Docker Hub
- Enter your Docker Hub username and access token
- Test the connection
- Note the **connector identifier** -- you will need it for the pipeline YAML

> **Note:** The Docker Hub connector serves three purposes here -- it pushes the built image, signs/attests it, and later re-verifies whatever tag you point the Verify stage at.


## Project Structure

```
scs-tidbits-drift-detection/
├── .harness/
│   └── pipeline.yaml                     — CI pipeline (Build+Sign+Attest, Verify)
├── app/
│   ├── app.py                            — minimal Flask app
│   └── requirements.txt
├── Dockerfile
└── scripts/
    └── simulate_drift.sh                 — rebuilds + pushes an unsigned, unattested image
```


## Step 1 -- Update the Pipeline Placeholders

Open `.harness/pipeline.yaml` and replace:

| Placeholder | Value |
|---|---|
| `<YOUR_PROJECT_ID>` | Your Harness project identifier |
| `<YOUR_ORG_ID>` | Your Harness org identifier |
| `<YOUR_GITHUB_CONNECTOR>` | Your GitHub connector identifier from Step 0 |
| `<YOUR_DOCKERHUB_CONNECTOR>` | Your Docker Hub connector identifier from Step 0 |
| `<YOUR_DOCKERHUB_USERNAME>` | Your Docker Hub username |

Commit and push.


## Step 2 -- Import and Run the Pipeline

1. Go to **Pipelines -> Import From Git** -> select your GitHub connector -> import `.harness/pipeline.yaml`
2. Click **Run Pipeline** -> set `artifact_tag` to something memorable, e.g. `v1` -> Run (both stages)


## Pipeline Walkthrough

**Stage 1: Build, Sign and Attest**

- **Build and Push Docker Image** -- builds the Dockerfile and pushes `<YOUR_DOCKERHUB_USERNAME>/scs-tidbit-drift-app:<artifact_tag>`
- **Sign Artifact (`SscaArtifactSigning`)** -- Cosign-signs that image keylessly (via Harness's OIDC identity) and pushes the signature alongside it
- **Generate SLSA Provenance (`provenance`)** -- generates and signs a SLSA provenance attestation describing this build, and pushes it alongside the artifact

**Stage 2: Verify and Detect Drift**

- **Verify Artifact Signature (`SscaArtifactVerification`)** -- independently re-checks the Cosign signature on `artifact_tag`. No valid signature -> step fails.
- **Verify SLSA Provenance (`SlsaVerification`)** -- independently re-checks the provenance attestation's signature on `artifact_tag`. No valid, signed provenance -> step fails.

Because this stage has `cloneCodebase: false` and no dependency on Stage 1's build output, you can run it **on its own**, against any tag, at any time -- which is exactly what you'll do to check a suspect artifact for drift.


## Demonstrating Drift Detection

1. Run the full pipeline once with `artifact_tag = v1`. Both stages should pass -- this is your approved, attested baseline.
2. Simulate drift: `./scripts/simulate_drift.sh <your-dockerhub-username> v1-drift`. This rebuilds the same app *outside* Harness and pushes it straight to the registry with plain `docker push` -- no signature, no provenance.
3. In Harness, **Run Pipeline** again, but this time select **only the "Verify and Detect Drift" stage** (via `allowStageExecutions`), and set `artifact_tag = v1-drift`.
4. Watch **Verify Artifact Signature** and **Verify SLSA Provenance** fail -- the drifted tag has no valid attestation to check.


## Viewing Results

After a run:

1. Go to **Supply Chain Security -> Artifacts -> `<YOUR_DOCKERHUB_USERNAME>/scs-tidbit-drift-app`**
2. Click the tag you ran (e.g. `v1` or `v1-drift`) to open the artifact overview
3. The **Chain of Custody** panel shows the full event history for that tag -- signing, provenance generation, and each verification attempt, with pass/fail and links to the execution
4. For a failed run, open the **Verify SLSA Provenance** step's execution log to see exactly why the signature/attestation check failed


## Resources

- [SLSA Overview](https://developer.harness.io/software-supply-chain-assurance/use-scs/artifact-security/slsa/overview)
- [Generate SLSA Provenance](https://developer.harness.io/docs/software-supply-chain-assurance/artifact-security/slsa/generate-slsa/)
- [Verify SLSA Provenance](https://developer.harness.io/docs/software-supply-chain-assurance/artifact-security/slsa/verify-slsa/)
- [Sign Artifacts with Harness SCS](https://developer.harness.io/docs/software-supply-chain-assurance/artifact-security/sign-verify/sign-artifacts/)
- [Harness SCS Key Concepts](https://developer.harness.io/docs/software-supply-chain-assurance/get-started/key-concepts/)
