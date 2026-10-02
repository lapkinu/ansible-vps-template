# Ansible VPS Template

Production VPS provisioning and deployment template for
[Symfony App Template](https://github.com/lapkinu/symfony-app-template).

The template provisions a Debian server for running an immutable application
image from GitHub Container Registry (GHCR).

It configures:

- administrator and deployment users;
- SSH hardening;
- Docker Engine and Docker Compose;
- host and Docker traffic firewall rules;
- application runtime configuration and secrets;
- restricted CI deployment through `sudo`;
- health checks and automatic rollback.

The tested production baseline is Debian 13 on `amd64`.

## Prerequisites

On the Ansible controller:

- Ansible;
- SSH key for the administrator;
- a separate SSH public key for the CI deployment user.

For the server:

- a fresh Debian 13 VPS;
- initial SSH access as `root`;
- DNS records pointing the configured application domains to the VPS before
  the application is deployed.

For private GHCR images, provide credentials with permission to pull the
application image.

## Quick start

### 1. Install Ansible dependencies

```bash
ansible-galaxy collection install -r requirements.yml
```

### 2. Configure the production host

Edit:

```text
inventory/production/hosts.yml
```

Set the VPS address:

```yaml
all:
  hosts:
    production:
      ansible_host: 203.0.113.10
```

Replace the example address with the real server IP address or hostname.

### 3. Configure non-secret variables

Edit:

```text
inventory/production/group_vars/all/main.yml
```

At minimum, configure:

```yaml
deployment_app_name: example-app

deployment_registry_username: username

deployment_image_repository: ghcr.io/username/example-app

deployment_main_server_name: example.com

deployment_server_name: dev.example.com

deployment_basic_auth_username: dev
```

Also verify the configured paths for the administrator and CI deployment SSH
public keys.

`deployment_app_name` is part of the deployment interface. It must match the
`DEPLOY_APP` GitHub Actions variable used by the application repository.

### 4. Create the encrypted Vault

Create the local Vault file from the provided example:

```bash
cp \
  inventory/production/group_vars/all/vault.example.yml \
  inventory/production/group_vars/all/vault.yml
```

The Vault contains:

```yaml
vault_ghcr_token:
vault_app_secret:
vault_basic_auth_password_hash:
vault_caddy_mercure_jwt_secret:
```

Generate or obtain the values as described below before encrypting the file.

#### Generate application secrets

Generate a Symfony application secret:

```bash
openssl rand -hex 32
```

Use the generated value as:

```yaml
vault_app_secret: <generated-value>
```

Generate a random Mercure JWT secret:

```bash
openssl rand -hex 32
```

Use a separate generated value as:

```yaml
vault_caddy_mercure_jwt_secret: <generated-value>
```

Do not reuse `vault_app_secret` as the Mercure JWT secret.

Generate the HTTP Basic Authentication password hash with Caddy:

```bash
docker run --rm caddy:2-alpine \
  caddy hash-password --plaintext 'replace-with-a-strong-password'
```

Store the resulting bcrypt hash as:

```yaml
vault_basic_auth_password_hash: '<generated-bcrypt-hash>'
```

Store the raw bcrypt hash in Vault. Do not replace `$` with `$$`; the
deployment template performs the escaping required by Docker Compose.

For `vault_ghcr_token`, use a GitHub credential that can pull the configured
private GHCR image.

Then encrypt the file:

```bash
ansible-vault encrypt inventory/production/group_vars/all/vault.yml
```

For later changes:

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

`vault.yml` is ignored by Git and must not be committed.

### 5. Bootstrap the VPS

The bootstrap playbook uses the initial `root` SSH access to prepare the
administrator account:

```bash
ansible-playbook playbooks/bootstrap.yml --ask-vault-pass
```

The bootstrap role preserves existing root authorized SSH keys, adds the
configured administrator key, and prepares passwordless `sudo`.

### 6. Configure the server

After bootstrap, apply the complete server configuration:

```bash
ansible-playbook playbooks/server.yml --ask-vault-pass
```

The server playbook connects as the administrator and configures users, SSH,
Docker, firewall rules, and the application deployment mechanism.

The playbooks are intended to be rerunnable when infrastructure configuration
changes.

## Configuration

The main deployment variables are stored in:

```text
inventory/production/group_vars/all/main.yml
```

Important values include:

- `deployment_app_name` — application/deployment identifier;
- `deployment_image_repository` — GHCR image repository;
- `deployment_registry_username` — GHCR username;
- `deployment_main_server_name` — public application domain;
- `deployment_server_name` — protected pre-launch application domain;
- `deployment_basic_auth_username` — HTTP Basic Authentication username.

Secrets are stored in the encrypted:

```text
inventory/production/group_vars/all/vault.yml
```

The deployment requires:

- `vault_ghcr_token`;
- `vault_app_secret`;
- `vault_basic_auth_password_hash`;
- `vault_caddy_mercure_jwt_secret`.

## Deployment contract

Application deployment is initiated by the application repository CI.

The expected flow is:

```text
GitHub Actions
    |
    | SSH as deploy user
    v
sudo /usr/local/sbin/deploy-<app> <40-character-git-sha>
    |
    v
GHCR immutable SHA image
    |
    v
Docker Compose
    |
    v
HTTPS health check
    |
    +-- healthy   -> deployment succeeds
    |
    +-- unhealthy -> previous image is restored
```

The deployment user is intentionally unprivileged. CI receives permission only
to invoke the root-owned deployment wrapper through the configured `sudoers`
rule.

The wrapper:

- accepts exactly one 40-character lowercase Git SHA;
- pulls the corresponding immutable image;
- validates the Compose configuration before changing the running application;
- serializes deployments with `flock`;
- starts the requested image;
- performs an HTTPS health check;
- restores the previous image when deployment or health validation fails.

Database migrations are not part of the current deployment contract.

## GitHub production environment

The companion application repository expects a GitHub Environment named:

```text
production
```

Configure these environment variables:

```text
DEPLOY_HOST
DEPLOY_USER
DEPLOY_APP
```

Configure these environment secrets:

```text
DEPLOY_SSH_PRIVATE_KEY
DEPLOY_SSH_KNOWN_HOSTS
```

For the companion Symfony application template, production deployment is
opt-in. Set the repository variable:

```text
DEPLOY_ENABLED=true
```

when the production server and GitHub Environment are ready.

The expected values are:

```text
DEPLOY_USER=deploy
DEPLOY_APP=<deployment_app_name>
```

`DEPLOY_HOST` is the server address reachable from GitHub Actions.

The private key in `DEPLOY_SSH_PRIVATE_KEY` must correspond to the CI public
key configured for the deployment user.

## Security model

The provisioned server follows a deliberately restricted deployment model:

- direct root SSH login is disabled after bootstrap;
- SSH password authentication is disabled;
- the deployment user is not a member of the Docker group;
- the deployment user does not receive direct access to the Docker socket;
- runtime configuration is root-owned and deployment secrets are readable only
  by root;
- deployment is exposed through a restricted `sudo` wrapper;
- deployment input is validated as an immutable Git SHA;
- concurrent deployments are rejected using `flock`;
- host and Docker traffic are covered by firewall configuration.

The application image is built by application CI. The production server does
not clone the application repository and does not build application images.

## Operations

Validate the playbooks:

```bash
ansible-playbook playbooks/bootstrap.yml --syntax-check
ansible-playbook playbooks/server.yml --syntax-check
```

Inspect the resolved production host configuration:

```bash
ansible-inventory --host production --ask-vault-pass
```

Edit encrypted secrets:

```bash
ansible-vault edit inventory/production/group_vars/all/vault.yml
```

After changing server infrastructure configuration, rerun:

```bash
ansible-playbook playbooks/server.yml --ask-vault-pass
```

Normal application releases are deployed by the application repository CI and
do not require rerunning Ansible.

## Companion application template

This repository provides the server side of the production deployment
contract.

The companion application template is:

[lapkinu/symfony-app-template](https://github.com/lapkinu/symfony-app-template)

The responsibilities are intentionally separated:

```text
symfony-app-template
    application tests
    production image build
    GHCR publication
    deployment initiation
            |
            | deploy-<app> <SHA>
            v
ansible-vps-template
    VPS provisioning
    Docker
    SSH hardening
    firewall
    runtime secrets
    deployment wrapper
    health validation
    rollback
```
