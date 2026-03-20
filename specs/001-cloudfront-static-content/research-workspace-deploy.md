## Research: HCP Terraform consumer deployment decisions for workspace `sandbox_consumer_cloudfrontcopilot-02` in org `hashi-demos-apj` project `sandbox`

### Decision
Use a **CLI-driven HCP Terraform workspace** named `sandbox_consumer_cloudfrontcopilot-02` in project `sandbox` with **remote execution**, **project-inherited AWS dynamic credentials**, **no direct workspace credential variables**, and an **explicit plan/apply/destroy cycle** for development validation; note that this workspace does **not currently exist** and must be created before deployment.

### Modules Identified

- **Primary Configuration**: HCP Terraform workspace `hashi-demos-apj/sandbox/sandbox_consumer_cloudfrontcopilot-02`
  - **Purpose**: Remote execution target for sandbox validation of the CloudFront static content consumer deployment
  - **Key Inputs**: organization, project, workspace name, execution mode, Terraform version, cloud backend binding from `cloud {}`
  - **Key Outputs**: run URL, run status, state, resource counts, destroy status
  - **Secure Defaults**: remote state isolation, HCP locking, project-scoped RBAC, inherited dynamic credentials
- **Supporting Configuration**:
  - **Project**: `sandbox` — isolated development project boundary in HCP Terraform
  - **Variable Set**: `agent_AWS_Dynamic_Creds` — provides inherited AWS workload identity configuration
  - **Backend Binding**: `terraform { cloud { organization = "hashi-demos-apj" workspaces { name = "sandbox_consumer_cloudfrontcopilot-02" project = "sandbox" } } }`
- **Glue Resources Needed**: None for workspace authentication or deployment flow itself
- **Wiring Considerations**:
  - Workspace authentication is inherited from the **project variable set**, not configured directly on the workspace
  - Consumer Terraform should define **provider region(s) and tags only**; it must **not** define AWS access keys, secret keys, or session tokens
  - CLI/GitHub Actions runs use the `cloud {}` backend to upload configuration and execute remotely in HCP Terraform

### Workspace Configuration

| Setting | Decision | Evidence / Notes |
|---------|----------|------------------|
| Organization | `hashi-demos-apj` | Confirmed by prompt and API queries |
| Project | `sandbox` | Project exists (`prj-QueMgU3LXgV2Ag7s`) |
| Workspace | `sandbox_consumer_cloudfrontcopilot-02` | Requested target name; API lookup currently returns `404 not found` |
| Workspace existence | Create before deploy | No existing workspace matched exact or partial CloudFront/copilot searches |
| Execution mode | `remote` | Existing sandbox consumer workspaces use `remote`; aligns with consumer constitution |
| Terraform version | Pin workspace to `1.14.x` | Existing sandbox workspaces use `1.14.7`; constitution requires `>= 1.14` |
| Auto-apply | **Recommended: `false` for development** | Sandbox allows auto-apply, but explicit apply is safer for iterative dev validation and easier run review |
| VCS connection | None | Example sandbox workspace `sandbox_consumer_web_stack` has `vcs_repo = null`; CLI-driven is the documented primary mode |
| Working directory | Root (`null` / default) unless repo layout requires otherwise | Existing sandbox workspace uses default root working directory |
| Speculative plans | Enabled | Existing sandbox workspace shows `speculative_enabled = true` |
| Direct workspace vars | None expected | Example sandbox workspace has `0` direct vars; auth comes from inherited varset |

### Dynamic Credentials Expectations

The sandbox project is already wired for **AWS dynamic provider credentials** via a project-level variable set, so the target workspace should inherit the same pattern automatically.

- **Project variable sets attached to `sandbox`**: exactly **one** discovered
  - `agent_AWS_Dynamic_Creds`
- **Inherited env vars in that variable set**:
  - `TFC_AWS_PROVIDER_AUTH = true`
  - `TFC_AWS_RUN_ROLE_ARN = <sandbox run role ARN>`
  - `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE = aws.workload.identity`
- **Implication**:
  - HCP Terraform will mint short-lived AWS credentials for each run using workload identity/OIDC
  - The workspace should **not** have per-workspace static AWS credentials
  - The consumer root module should remain credential-agnostic and let HCP Terraform inject credentials at runtime

### Variable Sets

| Variable Set | Attachment Model | What It Does | Deployment Decision |
|--------------|------------------|--------------|---------------------|
| `agent_AWS_Dynamic_Creds` | Attached to project `sandbox` | Supplies workload identity variables for AWS provider auth | Reuse as-is; do not create workspace-local credential vars |

Additional notes:
- The discovered variable set has `priority = true`, so its values take precedence when inherited.
- The example sandbox workspace exposes the project varset through the workspace varsets API even though `workspace-count = 0`, confirming project inheritance.
- No additional project-level variable sets were discovered for `sandbox`, so environment-specific app inputs should come from Terraform variables / tfvars / non-secret workspace variables only if truly needed.

### AWS Provider Authentication Pattern

Use the standard consumer provider pattern: **region and tags in code, credentials from HCP Terraform runtime**.

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
    }
  }
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
      Project     = var.project_name
      Owner       = var.owner
    }
  }
}
```

Pattern decisions:
- **Do include** provider aliases for multi-region needs such as ACM in `us-east-1` and S3 content in `ap-southeast-2`
- **Do not include** `access_key`, `secret_key`, `token`, or static credential variables
- **Do not include** `assume_role` unless deployment must cross into another AWS account; current sandbox dynamic credentials already target the sandbox account
- All provider aliases in the workspace will use the same HCP Terraform-issued temporary credentials unless explicitly overridden

### Remote Execution Considerations

- **CLI-driven remote execution is the preferred mode** for this development workflow.
  - HCP Terraform docs captured in repo guidance and the uplift implementation plan explicitly prefer CLI-driven workspaces over VCS-backed workspaces for automated plan/apply control.
- **VCS-backed workspaces are a poor fit here**.
  - They block normal CLI apply, can create duplicate runs, and undermine deterministic CI control.
- **`hashicorp/setup-terraform` must set `terraform_wrapper: false`** when used in GitHub Actions.
  - Otherwise `terraform plan -detailed-exitcode` can be collapsed into a failing exit path.
- **Do not set `TF_WORKSPACE=""`** when using the `cloud {}` backend.
  - The demo guidance documents a `failed to create backend alias` error if an empty `TF_WORKSPACE` env var is injected.
- **Remote plan output includes the HCP Terraform run URL**.
  - CI can parse the run URL from `terraform plan` output for reporting and follow-up checks.
- Existing sandbox workspace runs show:
  - `source = terraform+cloud`
  - message `Triggered via CLI`
  - manual trigger reason
  - remote apply/destroy compatibility

### Sandbox Deployment / Destroy Workflow

Recommended development workflow for this feature:

1. **Create the workspace if absent**
   - Create `sandbox_consumer_cloudfrontcopilot-02` in org `hashi-demos-apj`, project `sandbox`
   - Set execution mode to `remote`
   - Pin Terraform version to `1.14.x`
   - Prefer `auto-apply = false` for development iterations

2. **Bind code to the workspace with `cloud {}`**
   - Root configuration should target org `hashi-demos-apj`, project `sandbox`, workspace `sandbox_consumer_cloudfrontcopilot-02`

3. **Run validation from CLI/CI**
   - `terraform init`
   - `terraform validate`
   - `tflint` / other static checks
   - `terraform plan -detailed-exitcode`
   - Expect HCP Terraform to execute the run remotely using inherited dynamic credentials

4. **Review and apply explicitly**
   - For a dev environment, keep the plan/apply split visible
   - If plan passes and changes are expected, run `terraform apply` against the same workspace
   - Capture run URL, status, and resource counts for the deployment report

5. **Validate runtime result**
   - Confirm CloudFront, S3, ACM, and monitoring modules deployed in the sandbox account
   - Inspect run tasks / policy / cost output where configured

6. **Destroy after validation**
   - Run a destroy in the same workspace after testing completes
   - Wait for destroy to reach a terminal success state
   - If the workspace is purely ephemeral, delete the workspace after destroy completes

7. **Treat destroy success as a release gate**
   - Consumer constitution requires both sandbox deploy **and** clean destroy before considering the deployment validated

### Rationale

The key constraint is that this is a **consumer** deployment, not a module-development workflow. The repository constitution requires HCP Terraform `cloud {}` backend usage, dynamic credentials, and sandbox validation before promotion. Live API inspection shows the `sandbox` project already exists and has a project-level dynamic credential variable set attached. It also shows that the requested workspace name does not currently exist, which means the correct operational choice is to treat this as a **workspace creation + deployment** decision rather than a tuning exercise on an existing workspace.

The strongest evidence for the authentication model is the discovered `agent_AWS_Dynamic_Creds` variable set: it explicitly enables AWS provider auth (`TFC_AWS_PROVIDER_AUTH=true`) and supplies both the run role ARN and workload identity audience. This is a textbook HCP Terraform dynamic credentials setup and removes the need for any static AWS credential material in Terraform code or workspace variables.

For execution mode, repository guidance is consistent: CLI-driven workspaces are the primary path because they support remote `terraform plan` and `terraform apply`, preserve `-detailed-exitcode`, and keep provider authentication inside the workspace. Existing sandbox consumer workspaces in the same project also confirm the pattern in practice: they are remote-execution workspaces with no VCS repo attached, and their runs are recorded as `terraform+cloud` / `Triggered via CLI`.

Finally, although sandbox auto-apply is allowed by platform guidance, a **development** environment benefits from keeping `auto-apply = false` so plan results can be reviewed before resource creation. This still uses the same dynamic credential and remote execution model, but gives clearer control during iterative CloudFront/S3/ACM testing.

### Alternatives Considered

| Alternative | Why Not |
|-------------|---------|
| VCS-backed workspace | Conflicts with documented CLI-driven workflow; CLI apply is constrained and duplicate runs are likely |
| Static AWS credentials in workspace variables or code | Violates consumer constitution and is unnecessary because project-level dynamic credentials already exist |
| Workspace-local credential variables | Duplicates project inheritance and increases drift / setup burden |
| `auto-apply = true` for this dev workspace | Allowed in sandbox, but less suitable for iterative development where explicit review of plan/apply is preferable |
| Reusing another existing sandbox workspace | Loses feature isolation and risks state collisions across unrelated consumer experiments |

### Sources

- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/projects?q=sandbox` — confirmed project `sandbox`
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/workspaces/sandbox_consumer_cloudfrontcopilot-02` — returned `404 not found`
- HCP Terraform API: `GET /api/v2/projects/prj-QueMgU3LXgV2Ag7s/varsets` — discovered `agent_AWS_Dynamic_Creds`
- HCP Terraform API: `GET /api/v2/varsets/varset-9BtXAvxByVGEnHWV/relationships/vars` and `GET /api/v2/vars/{id}` — confirmed `TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`, `TFC_AWS_WORKLOAD_IDENTITY_AUDIENCE`
- HCP Terraform API: `GET /api/v2/workspaces/ws-7qW2ak4SudBH7Yaw/varsets` and `/vars` for example workspace `sandbox_consumer_web_stack` — confirmed inherited varset model and no direct workspace vars
- HCP Terraform API: `GET /api/v2/organizations/hashi-demos-apj/workspaces/sandbox_consumer_web_stack` and `/runs` — confirmed remote execution, no VCS repo, CLI-triggered runs
- `/workspace/.foundations/memory/consumer-constitution.md` — sections 1.3, 3.1, 4.2, 5.1, 5.2
- `/workspace/docs/index.html` — HCP Terraform setup, dynamic credentials, sandbox isolation, and workspace lifecycle guidance
- `/workspace/specs/feat-consumer-uplift/implementation-plan.md` — Decision D7 on CLI-driven workspace compatibility
- `/workspace/specs/feat-consumer-uplift/demo/setup.sh` and `demo/README.md` — workspace creation defaults and operational workflow
