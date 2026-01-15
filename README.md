# Puppet Environment Management with g10k and GitHub Actions

This repository demonstrates a modern approach to managing Puppet environments using g10k and GitHub Actions, eliminating the need for on-premises r10k installations.

## Overview

This solution provides:
- Automated Puppet module management using g10k
- CI/CD pipeline for building Puppet environments
- Artifact-based deployment to Puppet servers
- No on-premises r10k installation required

## Architecture

### Build Pipeline (Public GitHub Runners)
1. Triggers on push to specific branches
2. Uses g10k to resolve and download Puppet modules from Puppetfile
3. Builds complete environment structure
4. Creates and uploads artifact

### Deployment Pipeline (Self-Hosted Runner)
1. Manually triggered workflow
2. Downloads environment artifact
3. Deploys via rsync to Puppet servers
4. Clears environment cache using Puppet Admin API

## Repository Structure

```
.
├── .github/
│   └── workflows/
│       ├── build-puppet-environment.yml    # Build pipeline
│       └── deploy-puppet-environment.yml   # Deployment pipeline
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

### For Build Pipeline (Public Runners)
- GitHub repository with Actions enabled
- No additional setup required

### For Deployment Pipeline (Self-Hosted Runner)
- Self-hosted GitHub Actions runner with label `self-hosted`
- SSH access to Puppet servers
- rsync installed on runner
- SSH key-based authentication configured

## Usage

### 1. Building Environments

Push to any supported branch to automatically trigger the build:

```bash
git checkout production
git add .
git commit -m "Update Puppet modules"
git push origin production
```

The pipeline will:
1. Install g10k
2. Download modules from Puppetfile
3. Create environment structure
4. Upload artifact: `puppet-environment-<branch>-<commit-sha>`

### 2. Deploying Environments

Navigate to **Actions** → **Deploy Puppet Environment** → **Run workflow**

Required inputs:
- **Environment**: Select the environment to deploy (production, qa, test)
- **Target servers**: Comma-separated list of Puppet server hostnames/IPs
- **Artifact name**: (Optional) Specific artifact to deploy, or leave empty for latest

Optional inputs:
- **rsync_user**: SSH user for deployment (default: root)
- **puppet_admin_api_port**: Puppet Admin API port (default: 8140)

Example:
```
Environment: production
Target servers: puppet1.example.com,puppet2.example.com
Artifact name: puppet-environment-production-abc1234
```

### 3. Adding New Modules

Edit the `Puppetfile`:

```ruby
mod "module_name",
  :git => "https://github.com/example/puppet-module",
  :tag => "v1.0.0"
```

Commit and push to trigger automatic rebuild.

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

1. **SSH Keys**: Use dedicated SSH keys for deployment, not personal keys
2. **Secrets**: Store sensitive data in GitHub Secrets
3. **Permissions**: Use least-privilege SSH user where possible
4. **Self-Hosted Runner**: Ensure runner is in a secure network segment

## Advanced Usage

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
4. **Automation**: Fully automated build and deployment
5. **Testing**: Test branches allow safe environment testing
6. **Rollback**: Easy rollback using previous artifacts

## References

- [g10k Documentation](https://github.com/xorpaul/g10k)
- [Puppet Admin API](https://www.puppet.com/docs/puppet/7/server/admin-api/v1/environment-cache.html)
- [GitHub Actions](https://docs.github.com/en/actions)

## License

This is a demonstration repository. Adjust for your organization's needs.
