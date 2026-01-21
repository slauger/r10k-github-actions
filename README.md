# Puppet Environment Management with g10k and GitHub Actions

This repository demonstrates a modern approach to managing Puppet environments using g10k and GitHub Actions, eliminating the need for on-premises r10k installations.

## Overview

This solution provides:
- Automated Puppet module management using g10k
- CI/CD pipeline for building Puppet environments
- Artifact-based deployment to Puppet servers
- No on-premises r10k installation required

## Architecture

### Unified CI/CD Pipeline

The workflow consists of two jobs that run sequentially:

#### Build Job (Public GitHub Runners)
1. Triggers on push to specific branches (production, qa, test, test_*)
2. Generates GitHub App token for private module access
3. Uses g10k to resolve and download Puppet modules from Puppetfile
4. Builds complete environment structure
5. Creates and uploads artifact

#### Deploy Job (Self-Hosted Runner)
1. Automatically runs after successful build (for production/qa/test/test_* branches)
2. Downloads environment artifact from build job
3. Creates backup of existing environment
4. Deploys via rsync to Puppet servers
5. Clears environment cache using Puppet Admin API

**Key Features:**
- Build and deploy happen in one workflow run
- Deploy only runs if build succeeds (`needs: build`)
- Only one deployment per environment at a time (concurrency control)
- Can be triggered manually via workflow_dispatch for custom deployments

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── build-puppet-environment.yml    # Unified CI/CD pipeline
│       └── deploy-eyaml-keys.yml           # eyaml keys synchronization
├── manifests/
│   └── site.pp                             # Main Puppet manifest
├── modules/
│   └── hello_world/                        # Custom Puppet module
│       ├── manifests/
│       │   └── init.pp
│       └── metadata.json
├── Puppetfile                              # Puppet module dependencies
└── g10k.yaml                               # g10k configuration
```

## Supported Environments

The build pipeline automatically triggers for:
- `production` branch
- `qa` branch
- `test` branch
- Any branch starting with `test_*`

Each branch creates a separate Puppet environment.

## Prerequisites

### For Build Job (Public Runners)
- GitHub repository with Actions enabled
- **For private Puppet modules**: GitHub App with repository access (see setup below)

### For Deploy Job (Self-Hosted Runner)
- Self-hosted GitHub Actions runner with label `self-hosted`
- SSH access to Puppet servers
- rsync installed on runner
- SSH key-based authentication configured (see Setup section)

## Setup

Follow these steps to configure the pipeline:

### GitHub App for Private Modules (Optional)

If you need to access private Puppet modules from your GitHub organization, you must set up a GitHub App:

#### 1. Create GitHub App

1. Go to your GitHub organization settings → Developer settings → GitHub Apps → New GitHub App
2. Configure the app:
   - **Name**: Puppet Module Access (or any name)
   - **Homepage URL**: Your organization URL
   - **Webhook**: Uncheck "Active"
   - **Repository permissions**:
     - Contents: Read
     - Metadata: Read (automatically assigned)
   - **Where can this GitHub App be installed?**: Only on this account

3. Click "Create GitHub App"

#### 2. Generate Private Key

1. On the app's settings page, scroll to "Private keys"
2. Click "Generate a private key"
3. Save the downloaded `.pem` file securely

#### 3. Install the App

1. On the app's settings page, click "Install App"
2. Select your organization
3. Choose repositories:
   - This repository (r10k-github-actions)
   - All private Puppet module repositories
4. Click "Install"

#### 4. Configure GitHub Secrets

Add the following secrets to this repository (Settings → Secrets and variables → Actions):

**For GitHub App (private modules):**
- **`GH_APP_ID`**: The App ID (found on the app's settings page)
- **`GH_APP_PRIVATE_KEY`**: Content of the `.pem` file (entire content including headers)

**For SSH deployment:**
- **`PUPPET_DEPLOY_SSH_KEY`**: SSH private key for accessing Puppet servers (see SSH setup below)

#### 5. Update Puppetfile

Private modules must use HTTPS URLs:

```ruby
# Private module from your organization
mod "my_private_module",
  :git => "https://github.com/your-org/puppet-my_private_module",
  :tag => "v1.0.0"

# Public modules can continue using HTTPS or SSH
mod "stdlib",
  :git => "https://github.com/puppetlabs/puppetlabs-stdlib",
  :tag => "v9.1.0"
```

**Note**: The workflow automatically converts SSH URLs to HTTPS, so both formats work for public repositories.

### SSH Key Setup for Deployment

The deploy job needs SSH access to your Puppet servers. Choose one of the following approaches:

#### Option 1: SSH Key on Self-Hosted Runner (Recommended)

Install the SSH key directly on your self-hosted runner:

```bash
# On the self-hosted runner machine:
# Generate SSH key
ssh-keygen -t ed25519 -C "github-actions-puppet-deploy" -f ~/.ssh/puppet_deploy -N ""

# Copy public key to all Puppet servers
ssh-copy-id -i ~/.ssh/puppet_deploy.pub root@puppet1.example.com
ssh-copy-id -i ~/.ssh/puppet_deploy.pub root@puppet2.example.com

# Add to SSH config for automatic use
cat >> ~/.ssh/config <<EOF
Host puppet*.example.com
    IdentityFile ~/.ssh/puppet_deploy
    StrictHostKeyChecking accept-new
EOF
```

**With this approach, you can remove the "Setup SSH key" step from the workflow** as the runner already has the key configured.

#### Option 2: SSH Key as GitHub Secret (More Flexible)

Store the SSH private key as a GitHub Secret (already configured in the workflow):

```bash
# Generate SSH key locally
ssh-keygen -t ed25519 -C "github-actions-puppet-deploy" -f puppet_deploy -N ""

# Copy public key to all Puppet servers
ssh-copy-id -i puppet_deploy.pub root@puppet1.example.com
ssh-copy-id -i puppet_deploy.pub root@puppet2.example.com

# Copy private key content to GitHub Secret
cat puppet_deploy  # Copy this entire output to PUPPET_DEPLOY_SSH_KEY secret
```

Then add the secret:
- Go to repository Settings → Secrets and variables → Actions → Secrets
- Click "New repository secret"
- Name: `PUPPET_DEPLOY_SSH_KEY`
- Value: Paste the entire private key content (including `-----BEGIN OPENSSH PRIVATE KEY-----` headers)

**Advantages of Option 2:**
- Key can be rotated via GitHub UI
- Works across multiple self-hosted runners
- Easier to audit and manage centrally

### Configure Required GitHub Variables

Configure these variables in your repository (Settings → Secrets and variables → Actions → Variables):

**Required:**
- **`PUPPET_SERVERS`**: Comma-separated list of all Puppet servers
  - Example: `puppet1.example.com,puppet2.example.com,puppet3.example.com`
  - All environments (production, qa, test) deploy to these servers
  - Each environment creates its own directory: `/etc/puppetlabs/code/environments/{env_name}/`

**Optional (with defaults):**
- **`PUPPET_RSYNC_USER`**: SSH user for deployment
  - Default: `root`
  - Example: `puppet-deploy`
- **`PUPPET_ADMIN_API_PORT`**: Puppet Admin API port
  - Default: `8140`
  - Change if using non-standard port

**How to add variables:**
1. Go to your repository on GitHub
2. Navigate to Settings → Secrets and variables → Actions
3. Click on the "Variables" tab
4. Click "New repository variable"
5. Add each variable with its value

### Summary: Required Configuration

Before running the pipeline, ensure you have configured:

**Secrets (for private modules - optional):**
- ✅ `GH_APP_ID` - GitHub App ID
- ✅ `GH_APP_PRIVATE_KEY` - GitHub App private key

**Secrets (for deployment - required):**
- ✅ `PUPPET_DEPLOY_SSH_KEY` - SSH private key for Puppet servers

**Variables (required):**
- ✅ `PUPPET_SERVERS` - List of Puppet servers

**Variables (optional):**
- `PUPPET_RSYNC_USER` (default: root)
- `PUPPET_ADMIN_API_PORT` (default: 8140)

The workflow will validate these settings and fail with clear error messages if required configuration is missing.

## Usage

### 1. Automatic Build and Deploy

Push to any supported branch to automatically trigger the full CI/CD pipeline:

```bash
git checkout production
git add .
git commit -m "Update Puppet modules"
git push origin production
```

The pipeline will automatically:
1. **Build Job**: Install g10k, download modules, create artifact
2. **Deploy Job**: Download artifact, deploy to all Puppet servers, clear cache

**Deployment behavior**:
- All branches deploy to the **same set of Puppet servers** (configured in `PUPPET_SERVERS`)
- Each branch/environment creates its own directory: `/etc/puppetlabs/code/environments/{environment_name}/`
- Example: `production` branch → `/etc/puppetlabs/code/environments/production/`
- Example: `test_feature` branch → `/etc/puppetlabs/code/environments/test_feature/`

### 2. Manual Deployment

For custom deployments, use the workflow_dispatch trigger:

Navigate to **Actions** → **Puppet Environment CI/CD** → **Run workflow**

Inputs:
- **Environment**: Environment name (production, qa, test, or test_*)
- **Skip deployment**: Check to build only without deploying

Example use cases:
- Build a specific environment without deploying
- Rebuild an environment for testing
- Deploy to custom test environment

### 3. Adding New Modules

Edit the `Puppetfile`:

```ruby
mod "module_name",
  :git => "https://github.com/example/puppet-module",
  :tag => "v1.0.0"
```

Commit and push to trigger automatic build and deployment.

### 4. Creating Custom Modules

Add modules to the `modules/` directory:

```bash
mkdir -p modules/mymodule/manifests
cat > modules/mymodule/manifests/init.pp <<EOF
class mymodule {
  # Your Puppet code here
}
EOF
```

## Deployment Process Details

### Backup
Before deployment, existing environments are backed up to:
```
/etc/puppetlabs/code/environments-backup/<environment>-<timestamp>/
```

### Rsync Deployment
The environment is synced to:
```
/etc/puppetlabs/code/environments/<environment>/
```

### Cache Clearing
After deployment, the environment cache is cleared using:
```bash
curl -X DELETE \
  --cert /etc/puppetlabs/puppet/ssl/certs/$(hostname -f).pem \
  --key /etc/puppetlabs/puppet/ssl/private_keys/$(hostname -f).pem \
  --cacert /etc/puppetlabs/puppet/ssl/certs/ca.pem \
  https://localhost:8140/puppet-admin-api/v1/environment-cache?environment=<environment>
```

Alternatively, if API call fails, manually reload:
```bash
puppetserver reload
# or
service puppetserver reload
```

## Environment Structure

The final deployed environment structure:

```
/etc/puppetlabs/code/environments/<environment>/
├── environment.conf          # Environment configuration
├── manifests/
│   └── site.pp              # Main manifest
├── modules/                 # Custom modules
│   └── hello_world/
├── forge/                   # Forge modules (from Puppetfile)
│   ├── stdlib/
│   ├── apache/
│   └── ...
└── Puppetfile              # Module definition
```

## Configuration Files

### environment.conf
```ini
modulepath = modules:forge:$basemodulepath
manifest = manifests/site.pp
```

### g10k.yaml
- **cachedir**: Git repository cache directory
- **sources**: Environment source configuration
- **forge**: Puppet Forge settings
- **deploy**: Deployment and purge settings

## Troubleshooting

### Build Pipeline Issues

**Problem**: g10k fails to download modules
```
Solution: Check Puppetfile syntax and module availability
```

**Problem**: Artifact upload fails
```
Solution: Verify GitHub Actions storage quota
```

### Deployment Pipeline Issues

**Problem**: SSH connection fails
```
Solution:
- Verify SSH keys are configured on self-hosted runner
- Check target server hostnames/IPs
- Test: ssh user@server 'echo test'
```

**Problem**: rsync fails with permission denied
```
Solution:
- Ensure SSH user has write permissions to /etc/puppetlabs/code/
- Check SELinux/AppArmor policies
```

**Problem**: Cache clearing fails
```
Solution:
- Verify Puppet server certificates exist
- Check Puppet Admin API is enabled
- Manually reload: puppetserver reload
```

### Testing the Deployment

After deployment, test on a Puppet agent:
```bash
puppet agent -t --environment=<environment>
```

Check for the hello_world module:
```bash
cat /tmp/hello_world.txt
```

## Security Considerations

1. **SSH Keys**: Use dedicated SSH keys for deployment
   - Generate a dedicated key pair specifically for GitHub Actions deployments
   - Do NOT use personal SSH keys
   - Restrict key to specific commands if possible (using `authorized_keys` restrictions)
   - Rotate keys regularly
2. **GitHub App**: Use a dedicated GitHub App for module access
   - App tokens are automatically scoped and time-limited
   - More secure than using personal access tokens (PATs)
   - Easier to audit and rotate credentials
3. **Secrets**: Store sensitive data in GitHub Secrets
   - Never commit private keys or tokens to the repository
   - Rotate GitHub App private keys regularly
4. **Permissions**: Use least-privilege SSH user where possible
5. **Self-Hosted Runner**: Ensure runner is in a secure network segment

## Advanced Usage

### Syncing eyaml Encryption Keys

When using Hiera-eyaml for encrypted secrets in Puppet, all Puppet servers need to have identical encryption keys. This workflow synchronizes the eyaml keys from a master server to all other servers.

**When to use:**
- Setting up new Puppet servers
- Rotating eyaml keys across your infrastructure
- Recovering from key mismatches

**How it works:**
1. Downloads keys from the **first server** in `PUPPET_SERVERS` (master)
2. Deploys keys to **all other servers** in the list
3. Sets correct permissions (directory: 0500, keys: 0400, owner: puppet:root)

**To sync keys:**

Navigate to **Actions** → **Deploy eyaml Keys** → **Run workflow**

The workflow will:
- Download from master: `/etc/puppetlabs/puppet/keys/private_key.pkcs7.pem` and `public_key.pkcs7.pem`
- Deploy to all other servers with correct permissions
- Verify deployment on all servers

**Requirements:**
- **At least 2 servers** configured in `PUPPET_SERVERS` (workflow will fail if only 1 server)
- eyaml keys must exist on the first server (master)
- SSH access to all servers (via `PUPPET_DEPLOY_SSH_KEY`)

**Note:** If you only have one Puppet server, this workflow is not needed - there's nothing to sync!

**Security notes:**
- Keys are temporarily stored on the self-hosted runner during sync
- Keys are automatically cleaned up after deployment
- Only accessible via manual workflow dispatch
- Concurrency control prevents parallel key syncs

**Example workflow:**
```bash
# 1. Generate keys on master server (first in PUPPET_SERVERS list)
ssh root@puppet1.example.com
eyaml createkeys --pkcs7-private-key=/etc/puppetlabs/puppet/keys/private_key.pkcs7.pem \
                 --pkcs7-public-key=/etc/puppetlabs/puppet/keys/public_key.pkcs7.pem

# 2. Set permissions on master
chown -R puppet:root /etc/puppetlabs/puppet/keys
chmod 0500 /etc/puppetlabs/puppet/keys
chmod 0400 /etc/puppetlabs/puppet/keys/*.pem

# 3. Run "Deploy eyaml Keys" workflow in GitHub Actions
# Keys are now synchronized to all servers

# 4. Verify on any server
ssh root@puppet2.example.com
ls -la /etc/puppetlabs/puppet/keys/
```

### Custom Environment Names

For branches starting with `test_*`, the environment name matches the branch:
```bash
git checkout -b test_feature_x
# Creates environment: test_feature_x
```

### Module Pinning

Always pin modules to specific versions in Puppetfile:
```ruby
# Good
mod "apache", :git => "...", :tag => "v10.1.0"

# Bad - not recommended
mod "apache", :git => "...", :branch => "main"
```

### Artifact Retention

Artifacts are retained for 30 days by default. Adjust in build pipeline:
```yaml
retention-days: 30
```

## Benefits

1. **No On-Prem Dependencies**: No r10k installation required on Puppet servers
2. **Version Control**: All environments are Git-based and versioned
3. **Reproducibility**: Artifacts ensure consistent deployments
4. **Automation**: Fully automated build and deployment in a single workflow
5. **Sequential Execution**: Deploy only runs if build succeeds
6. **Concurrency Control**: Only one deployment per environment at a time
7. **Testing**: Test branches allow safe environment testing
8. **Private Module Support**: GitHub App integration for private repositories
9. **Flexible Deployment**: Automatic or manual deployment options

## References

- [g10k Documentation](https://github.com/xorpaul/g10k)
- [Puppet Admin API](https://www.puppet.com/docs/puppet/7/server/admin-api/v1/environment-cache.html)
- [GitHub Actions](https://docs.github.com/en/actions)

## License

This is a demonstration repository. Adjust for your organization's needs.
