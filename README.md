# Trinket OSS self-hosted deployment with HTTPS and Microsoft Entra SSO

This branch provides a repeatable self-hosted deployment path for Trinket OSS on Ubuntu Server using Docker, Docker Compose, MongoDB, direct HTTPS hosting, and optional Microsoft Entra ID sign-in using OpenID Connect.

## Current tested status

This deployment has been tested successfully with:

- Ubuntu Server VM
- Docker and Docker Compose
- `trinket/app` container
- `mongo:5` container
- host networking for the app container
- MongoDB using `127.0.0.1`
- generated `config/local.yaml`
- generated `docker-compose.minimal.yml`
- local signup and login
- auto-login after signup
- Python editor loading
- Python Hello World execution
- persistent MongoDB data after reboot
- container restart after reboot
- direct HTTPS hosting on port `3000`
- direct HTTPS hosting on port `443`
- Microsoft Entra OpenID Connect sign-in
- Microsoft-authenticated user provisioning into Trinket

Microsoft Entra SSO is optional and disabled by default unless enabled through setup-script environment variables.

## Architecture overview

The minimal deployment uses:

```text
Browser
  -> HTTPS directly to Trinket Node/Hapi app
  -> Trinket app container using host networking
  -> MongoDB container bound to 127.0.0.1:27017
```

No reverse proxy is required for the tested direct HTTPS model.

## HTTPS behaviour

The Trinket Node/Hapi application can serve HTTPS directly.

The setup script supports:

- generated self-signed certificates for testing
- provided certificate and key files for production or internal CA use
- HTTPS on port `3000`
- HTTPS on port `443`

When using port `443`, the container still runs as the non-root `trinket` user. The Docker image grants the Node binary the capability required to bind to privileged ports:

```text
cap_net_bind_service
```

The generated Docker Compose file also grants:

```yaml
cap_add:
  - NET_BIND_SERVICE
```

This avoids running the application as root.

## Fresh Ubuntu VM deployment

On a blank Ubuntu Server VM, install Git first:

```bash
sudo apt-get update
sudo apt-get install -y git
```

Clone the branch explicitly:

```bash
sudo git clone --branch feature/direct-https-hosting https://github.com/marc-hundley-oasisuk-org/trinket-oss.git /opt/trinket-oss
```

Run the setup script:

```bash
cd /opt/trinket-oss
sudo bash autosetup/setup-trinket-oss.sh
```

The script will:

- install Docker and Docker Compose if required
- generate `config/local.yaml`
- generate `docker-compose.minimal.yml`
- build the Trinket app container
- start MongoDB and Trinket
- validate that Trinket responds

## Basic HTTP deployment

For a simple HTTP deployment:

```bash
cd /opt/trinket-oss
sudo bash autosetup/setup-trinket-oss.sh
```

The generated service will be available at:

```text
http://<vm-ip>:3000
```

Microsoft SSO will be disabled by default.

## Direct HTTPS deployment on port 3000

For HTTPS testing on port `3000` using a generated self-signed certificate:

```bash
cd /opt/trinket-oss
sudo TRINKET_HTTPS_ENABLED="true" TRINKET_HOSTNAME="<vm-ip-or-hostname>" TRINKET_PORT="3000" bash autosetup/setup-trinket-oss.sh
```

Test from the VM:

```bash
curl -k https://localhost:3000
```

Test from a browser:

```text
https://<vm-ip-or-hostname>:3000
```

A browser certificate warning is expected when using the generated self-signed certificate.

## Direct HTTPS deployment on port 443

For HTTPS testing or production-style hosting on port `443`:

```bash
cd /opt/trinket-oss
sudo TRINKET_HTTPS_ENABLED="true" TRINKET_HOSTNAME="<vm-ip-or-hostname>" TRINKET_PORT="443" bash autosetup/setup-trinket-oss.sh
```

Test from the VM:

```bash
curl -k https://localhost
```

Test from a browser:

```text
https://<vm-ip-or-hostname>
```

Expected container behaviour:

```text
Server started on port: 443
```

Verify the Node binary capability inside the container:

```bash
sudo docker exec -it trinket sh -c 'id && getcap "$(readlink -f "$(which node)")"'
```

Expected output should include:

```text
cap_net_bind_service+ep
```

## Using an internal CA or production certificate

To provide your own certificate and key:

```bash
cd /opt/trinket-oss
sudo TRINKET_HTTPS_ENABLED="true" TRINKET_HOSTNAME="trinket.internal.example.org" TRINKET_PORT="443" TRINKET_HTTPS_CERT_SOURCE="/path/to/trinket.crt" TRINKET_HTTPS_KEY_SOURCE="/path/to/trinket.key" bash autosetup/setup-trinket-oss.sh
```

The setup script copies these into:

```text
/opt/trinket-oss/certs/trinket.crt
/opt/trinket-oss/certs/trinket.key
```

The container mounts them read-only at:

```text
/usr/local/node/trinket/certs/trinket.crt
/usr/local/node/trinket/certs/trinket.key
```

Do not commit certificates, keys, generated `certs/` content, or secrets.

## Microsoft Entra SSO overview

Microsoft Entra SSO is implemented using OpenID Connect Authorization Code Flow.

When enabled, Trinket adds:

```text
GET /auth/microsoft
GET /auth/microsoft/callback
```

The login page displays:

```text
Sign in with Microsoft
```

The sign-in flow:

1. Redirects the user to the tenant-specific Microsoft identity endpoint.
2. Uses OpenID Connect Authorization Code Flow.
3. Exchanges the returned code for tokens.
4. Validates the Microsoft ID token.
5. Validates the tenant ID.
6. Optionally validates the user's email or UPN domain.
7. Finds an existing Trinket user by Microsoft profile ID or email.
8. Auto-creates a Trinket user if enabled.
9. Stores Microsoft identity information under `profiles.microsoft`.
10. Logs the user into Trinket using the existing Yar session mechanism.

Local login and signup remain available.

## Microsoft Entra app registration

Create an app registration in Microsoft Entra:

```text
Microsoft Entra admin centre
-> Identity
-> Applications
-> App registrations
-> New registration
```

Recommended values:

```text
Name:
OCL - Trinket OSS

Supported account types:
Accounts in this organisational directory only

Platform:
Web

Redirect URI:
https://trinket.internal.example.org/auth/microsoft/callback
```

For an IP-based test on port 443:

```text
https://<vm-ip>/auth/microsoft/callback
```

For a port 3000 test:

```text
https://<vm-ip>:3000/auth/microsoft/callback
```

The redirect URI in Entra must exactly match the `callbackURL` generated in `config/local.yaml`.

After creating the app registration, record:

```text
Application (client) ID
Directory (tenant) ID
```

Create a client secret:

```text
App registrations
-> <your app>
-> Certificates & secrets
-> Client secrets
-> New client secret
```

Copy the secret `Value` immediately. Do not use the Secret ID as the application secret.

## Enterprise application configuration

After the app registration is created, Microsoft Entra will also create an Enterprise Application.

Review:

```text
Microsoft Entra admin centre
-> Identity
-> Applications
-> Enterprise applications
-> <your app>
```

Depending on tenant policy, configure:

- user assignment
- admin consent
- application visibility
- permitted users or groups

If assignment is required:

```text
Enterprise applications
-> <your app>
-> Users and groups
-> Add user/group
```

Add the appropriate users or groups who should be allowed to use Trinket.

## API permissions and consent

The Trinket OIDC implementation uses Microsoft sign-in only. It does not call Microsoft Graph.

The application requests these OpenID Connect scopes:

```text
openid profile email
```

For first testing, avoid adding unnecessary Microsoft Graph delegated permissions.

If users see a `Need admin approval` screen:

```text
App registrations
-> <your app>
-> API permissions
```

Recommended first test:

- Remove unnecessary Graph permissions.
- Avoid adding optional email claims unless needed.
- If tenant policy blocks user consent, an administrator must grant admin consent.

Admin consent can be granted from:

```text
App registrations
-> <your app>
-> API permissions
-> Grant admin consent
```

## Optional claims

For initial testing, do not add unnecessary optional claims.

The current Trinket implementation checks the ID token for:

- `email`
- `preferred_username`
- `upn`

In most Microsoft 365 work account scenarios, `preferred_username` or `upn` should be sufficient for matching and provisioning users.

Only add the `email` optional claim if testing proves that the ID token does not contain a usable email-like identifier.

## Enabling HTTPS and Microsoft SSO together

Recommended production-style command using HTTPS on port `443`:

```bash
cd /opt/trinket-oss
sudo TRINKET_HTTPS_ENABLED="true" TRINKET_HOSTNAME="trinket.internal.example.org" TRINKET_PORT="443" MICROSOFT_SSO_ENABLED="true" MICROSOFT_TENANT_ID="<directory-tenant-id>" MICROSOFT_CLIENT_ID="<application-client-id>" MICROSOFT_CLIENT_SECRET="<client-secret-value>" MICROSOFT_CALLBACK_URL="https://trinket.internal.example.org/auth/microsoft/callback" MICROSOFT_ALLOWED_DOMAINS="example.org" MICROSOFT_AUTO_CREATE_USERS="true" bash autosetup/setup-trinket-oss.sh
```

For an IP-based test:

```bash
cd /opt/trinket-oss
sudo TRINKET_HTTPS_ENABLED="true" TRINKET_HOSTNAME="<vm-ip>" TRINKET_PORT="443" MICROSOFT_SSO_ENABLED="true" MICROSOFT_TENANT_ID="<directory-tenant-id>" MICROSOFT_CLIENT_ID="<application-client-id>" MICROSOFT_CLIENT_SECRET="<client-secret-value>" MICROSOFT_CALLBACK_URL="https://<vm-ip>/auth/microsoft/callback" MICROSOFT_ALLOWED_DOMAINS="example.org" MICROSOFT_AUTO_CREATE_USERS="true" bash autosetup/setup-trinket-oss.sh
```

Do not include real secrets in commits, screenshots, documentation, or issue reports.

## Generated local.yaml example

Expected HTTPS and Microsoft SSO configuration:

```yaml
app:
  hostname: 0.0.0.0
  port: 443
  url:
    hostname: trinket.internal.example.org
    port: 443
    protocol: https
  basePath: "/"

  https:
    enabled: true
    keyPath: '/usr/local/node/trinket/certs/trinket.key'
    certPath: '/usr/local/node/trinket/certs/trinket.crt'

  plugins:
    session:
      cookieOptions:
        password: '<generated-session-secret>'
        isSecure: true

  auth:
    microsoft:
      enabled: true
      tenantId: '<directory-tenant-id>'
      clientID: '<application-client-id>'
      clientSecret: '<client-secret-value>'
      callbackURL: 'https://trinket.internal.example.org/auth/microsoft/callback'
      allowedDomains:
        - 'example.org'
      autoCreateUsers: true
```

To allow multiple domains:

```bash
MICROSOFT_ALLOWED_DOMAINS="example.org,example.com"
```

This generates:

```yaml
allowedDomains:
  - 'example.org'
  - 'example.com'
```

If `allowedDomains` is empty, domain restriction is not enforced.

## Regression test checklist

After running the setup script, confirm:

```bash
sudo docker ps
sudo docker logs trinket --tail=150
```

Expected containers:

```text
trinket
mongodb
```

For HTTPS on port 443:

```bash
curl -k https://localhost
```

For HTTPS on port 3000:

```bash
curl -k https://localhost:3000
```

Browser tests:

- Home page loads.
- `/signup` loads.
- `/login` loads.
- Local signup works.
- Auto-login after signup works.
- Local login works.
- Python editor loads.
- Python Hello World runs.
- No browser console errors.
- Containers restart successfully.

Restart test:

```bash
sudo docker restart trinket mongodb
```

Then confirm:

- the application still loads
- MongoDB data persists
- existing users can still log in

## Microsoft SSO test checklist

Before testing:

- Trinket is reachable over HTTPS.
- The browser can resolve the Trinket hostname.
- The Trinket server has outbound HTTPS access to Microsoft identity endpoints.
- The Entra redirect URI exactly matches `callbackURL`.
- The app registration is single tenant.
- `tenantId`, `clientID`, and `clientSecret` are correct.
- `allowedDomains` is configured as required.
- the Enterprise Application allows the test user or group, if assignment is required.
- admin consent has been granted, if required by tenant policy.

Follow logs:

```bash
sudo docker logs -f trinket
```

Browse to:

```text
https://trinket.internal.example.org/login
```

Click:

```text
Sign in with Microsoft
```

Expected result:

- Microsoft sign-in page appears.
- User authenticates.
- Browser returns to `/auth/microsoft/callback`.
- User lands on `/welcome` or `/home`.
- New user is auto-created if no matching account exists and `autoCreateUsers` is true.

## Troubleshooting

### Microsoft button does not appear

Check:

```bash
grep -A10 -n "microsoft:" /opt/trinket-oss/config/local.yaml
```

Microsoft sign-in appears only when:

```yaml
enabled: true
clientID: '<non-empty-value>'
```

Restart after config changes:

```bash
sudo docker restart trinket
```

### AADSTS90013 invalid input

Usually caused by placeholder or invalid values.

Check:

- tenant ID
- client ID
- app registration exists
- URL is using the expected tenant
- no placeholder values remain in `config/local.yaml`

### AADSTS50011 reply URL mismatch

The callback URL sent by Trinket does not exactly match the redirect URI in Entra.

Compare:

```yaml
callbackURL:
```

with the Entra app registration Redirect URI.

These must match exactly, including:

- protocol
- hostname
- port
- path
- trailing slash behaviour

### Need admin approval

This is usually caused by tenant consent policy or added permissions that require administrator approval.

Check:

```text
App registrations
-> <your app>
-> API permissions
```

Remove unnecessary Microsoft Graph permissions for first testing.

If approval is still required, ask an administrator to grant consent:

```text
App registrations
-> <your app>
-> API permissions
-> Grant admin consent
```

Also check whether assignment is required:

```text
Enterprise applications
-> <your app>
-> Properties
-> Assignment required
```

If assignment is required, add the appropriate users or groups:

```text
Enterprise applications
-> <your app>
-> Users and groups
-> Add user/group
```

### Trinket returns Microsoft sign-in failed

Check logs:

```bash
sudo docker logs trinket --tail=200
```

Likely causes:

- incorrect client secret
- callback URL mismatch
- token validation failure
- tenant ID mismatch
- blocked email domain
- user auto-creation disabled
- disabled local user account

### HTTPS port 443 does not start

Check logs:

```bash
sudo docker logs trinket --tail=100
```

If you see:

```text
listen EACCES: permission denied 0.0.0.0:443
```

verify the Node binary capability:

```bash
sudo docker exec -it trinket sh -c 'id && getcap "$(readlink -f "$(which node)")"'
```

Expected:

```text
cap_net_bind_service+ep
```

Also verify the container capability:

```bash
sudo docker inspect trinket --format '{{json .HostConfig.CapAdd}}'
```

Expected:

```text
["NET_BIND_SERVICE"]
```

### Local login stops working

Microsoft SSO should not disable local login.

Check:

```bash
sudo docker logs trinket --tail=200
```

Also confirm the generated session configuration:

```bash
cat /opt/trinket-oss/config/local.yaml
```

For HTTPS production use, the session cookie should be secure:

```yaml
isSecure: true
```

For HTTP-only testing, this should be:

```yaml
isSecure: false
```

## Generated files and secrets

Do not commit:

- `config/local.yaml`
- `docker-compose.minimal.yml`
- `certs/`
- private keys
- client secrets
- session secrets

The following files are generated during deployment:

```text
/opt/trinket-oss/config/local.yaml
/opt/trinket-oss/docker-compose.minimal.yml
/opt/trinket-oss/certs/trinket.crt
/opt/trinket-oss/certs/trinket.key
```

## Useful commands

View running containers:

```bash
sudo docker ps
```

View Trinket logs:

```bash
sudo docker logs trinket --tail=150
```

Follow Trinket logs:

```bash
sudo docker logs -f trinket
```

Restart the app:

```bash
sudo docker restart trinket
```

Restart both app and database:

```bash
sudo docker restart trinket mongodb
```

Rebuild using the minimal compose file:

```bash
cd /opt/trinket-oss
sudo docker-compose -f docker-compose.minimal.yml build --no-cache app
sudo docker-compose -f docker-compose.minimal.yml up -d
```

Do not run plain `docker-compose up -d` unless intentionally using another compose file.

## Current known follow-up items

Planned improvements:

- reduce reliance on long environment-variable setup commands
- improve Microsoft-created display names if required


# Promote an existing user to administrator

sudo docker-compose -f docker-compose.minimal.yml exec app \
npm run make-admin <email-address>