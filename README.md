# Self-Hosted Ubuntu Deployment with Optional Microsoft Entra SSO

This fork includes a minimal self-hosted deployment path for Trinket OSS on Ubuntu Server using Docker, Docker Compose, MongoDB, and optional Microsoft Entra ID sign-in using OpenID Connect.

## Current status

This branch has been tested successfully with:

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

Microsoft Entra SSO is optional and disabled by default.

## Important HTTPS note for Microsoft Entra SSO

Microsoft Entra app registrations require the redirect URI to be registered exactly.

For local development, Microsoft allows `http://localhost` redirect URIs. For an internal server reached by IP address or hostname, use HTTPS.

Suitable for Microsoft Entra SSO:

```text
https://trinket.internal.example.org/auth/microsoft/callback
```

Not suitable for a Web redirect URI unless using localhost:

```text
http://172.27.105.81:3000/auth/microsoft/callback
```

The application currently runs on port `3000`. Before enabling Microsoft Entra SSO for non-localhost testing, configure Trinket to be available over HTTPS and ensure the callback URL in `config/local.yaml` exactly matches the redirect URI registered in Microsoft Entra.

## Fresh Ubuntu VM deployment

On a blank Ubuntu Server VM, install Git first:

```bash
sudo apt-get update
sudo apt-get install -y git
```

Clone this branch explicitly:

```bash
sudo git clone --branch feature/entra-oidc-auth https://github.com/marc-hundley-oasisuk-org/trinket-oss.git /opt/trinket-oss
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
- validate that Trinket responds on port `3000`

After completion, test from the VM:

```bash
curl http://localhost:3000
```

Test from a browser:

```text
http://<vm-ip>:3000
```

## Setup script configuration options

The setup script supports environment variables for the application URL and Microsoft Entra SSO configuration.

## Basic HTTP deployment

```bash
sudo bash autosetup/setup-trinket-oss.sh
```

This generates Microsoft SSO as disabled:

```yaml
app:
  auth:
    microsoft:
      enabled: false
      tenantId: ''
      clientID: ''
      clientSecret: ''
      callbackURL: 'http://<vm-ip>:3000/auth/microsoft/callback'
      allowedDomains: []
      autoCreateUsers: true
```

## HTTPS deployment values

When HTTPS is available, run the setup script with explicit URL values:

```bash
sudo \
TRINKET_PROTOCOL="https" \
TRINKET_HOSTNAME="trinket.internal.example.org" \
TRINKET_PORT="443" \
bash autosetup/setup-trinket-oss.sh
```

If using Microsoft Entra SSO, set the callback URL explicitly to avoid an unwanted `:443` mismatch:

```bash
sudo \
TRINKET_PROTOCOL="https" \
TRINKET_HOSTNAME="trinket.internal.example.org" \
TRINKET_PORT="443" \
MICROSOFT_SSO_ENABLED="true" \
MICROSOFT_TENANT_ID="<directory-tenant-id>" \
MICROSOFT_CLIENT_ID="<application-client-id>" \
MICROSOFT_CLIENT_SECRET="<client-secret-value>" \
MICROSOFT_CALLBACK_URL="https://trinket.internal.example.org/auth/microsoft/callback" \
MICROSOFT_ALLOWED_DOMAINS="example.org" \
MICROSOFT_AUTO_CREATE_USERS="true" \
bash autosetup/setup-trinket-oss.sh
```

Do not include real secrets in commits, screenshots, documentation, or issue reports.

## Microsoft Entra app registration

Create an app registration in Microsoft Entra:

```text
Microsoft Entra admin centre
→ Identity
→ Applications
→ App registrations
→ New registration
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

After creating the app registration, record:

```text
Application (client) ID
Directory (tenant) ID
```

Create a client secret:

```text
App registrations
→ <your app>
→ Certificates & secrets
→ Client secrets
→ New client secret
```

Copy the secret **Value** immediately.

Do not use the Secret ID as the application secret.

## Enterprise application configuration

After the app registration is created, Microsoft Entra will also create an Enterprise Application.

Review the Enterprise Application:

```text
Microsoft Entra admin centre
→ Identity
→ Applications
→ Enterprise applications
→ <your app>
```

Depending on tenant policy, you may need to configure:

- user assignment
- admin consent
- application visibility
- permitted users or groups

If assignment is required:

```text
Enterprise applications
→ <your app>
→ Users and groups
→ Add user/group
```

Add the appropriate users or groups who should be allowed to use Trinket.

## API permissions and consent

The Trinket OIDC implementation uses Microsoft sign-in only. It does not call Microsoft Graph.

The application requests these OpenID Connect scopes:

```text
openid profile email
```

For first testing, avoid adding unnecessary Microsoft Graph delegated permissions.

If users see a **Need admin approval** screen, check:

```text
App registrations
→ <your app>
→ API permissions
```

Recommended first test:

- Remove unnecessary Graph permissions.
- Avoid adding optional email claims that require extra consent unless needed.
- If tenant policy still blocks user consent, an administrator must grant admin consent.

Admin consent can be granted from:

```text
App registrations
→ <your app>
→ API permissions
→ Grant admin consent
```

Depending on tenant policy, the Enterprise Application may also need assignment:

```text
Enterprise applications
→ <your app>
→ Users and groups
→ Add user/group
```

## Optional claims

For initial testing, do not add unnecessary optional claims.

The current Trinket implementation checks the ID token for:

- `email`
- `preferred_username`
- `upn`

In most Microsoft 365 work account scenarios, `preferred_username` or `upn` should be sufficient for matching and provisioning users.

If you later require the `email` claim specifically, add it under:

```text
App registrations
→ <your app>
→ Token configuration
→ Add optional claim
→ ID token
→ email
```

Be aware that enabling some optional claims or related Graph permissions may trigger admin consent requirements in some tenants.

## Generated local.yaml Microsoft configuration

Expected enabled configuration:

```yaml
app:
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

To allow multiple domains, provide a comma-separated list to the setup script:

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

## Microsoft SSO behaviour

When enabled, Trinket adds:

```text
GET /auth/microsoft
GET /auth/microsoft/callback
```

The login page displays:

```text
Sign in with Microsoft
```

The Microsoft sign-in flow:

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

## Local login and signup

Local login and signup remain available.

This is intentional during testing so that administrators can still access the platform if Microsoft SSO configuration is incorrect.

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

Test in browser:

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

Run:

```bash
sudo docker logs -f trinket
```

Then browse to:

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

### Redirect URI must start with HTTPS

For internal hostname or IP-based testing, use HTTPS.

`http://localhost` is treated as a local-development exception.

`http://<server-ip>:3000` is not suitable for the Web redirect URI.

### Need admin approval

This is usually caused by tenant consent policy or added permissions that require administrator approval.

Check:

```text
App registrations
→ <your app>
→ API permissions
```

Remove unnecessary Microsoft Graph permissions for first testing.

If approval is still required, ask an administrator to grant consent:

```text
App registrations
→ <your app>
→ API permissions
→ Grant admin consent
```

Also check whether assignment is required:

```text
Enterprise applications
→ <your app>
→ Properties
→ Assignment required
```

If assignment is required, add the appropriate users or groups:

```text
Enterprise applications
→ <your app>
→ Users and groups
→ Add user/group
```

### Trinket returns "Microsoft sign-in failed"

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

### Local login stops working

Microsoft SSO should not disable local login.

Check:

```bash
sudo docker logs trinket --tail=200
```

Also confirm the generated session configuration in:

```bash
cat /opt/trinket-oss/config/local.yaml
```

For HTTP testing, the session cookie should not be secure:

```yaml
isSecure: false
```

For HTTPS production use, this should be changed to:

```yaml
isSecure: true
```

## Current known limitation

This branch adds optional Microsoft Entra OIDC sign-in and setup-script configuration.

Direct HTTPS hosting for the Trinket Node application should be completed before production Entra SSO testing if a reverse proxy is not being used.

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
sudo docker compose -f docker-compose.minimal.yml build --no-cache app
sudo docker compose -f docker-compose.minimal.yml up -d
```

If using older Docker Compose:

```bash
cd /opt/trinket-oss
sudo docker-compose -f docker-compose.minimal.yml build --no-cache app
sudo docker-compose -f docker-compose.minimal.yml up -d
```

Do not run plain `docker-compose up -d` unless intentionally using the upstream compose file.

## References

Microsoft identity platform redirect URI guidance:

```text
https://learn.microsoft.com/en-us/entra/identity-platform/reply-url
```

Microsoft identity platform OpenID Connect guidance:

```text
https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc
```

Microsoft identity platform authorization code flow guidance:

```text
https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow
```

Microsoft identity platform admin consent guidance:

```text
https://learn.microsoft.com/en-us/entra/identity-platform/v2-admin-consent
```
