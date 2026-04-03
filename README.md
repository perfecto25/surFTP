# SurFTP

<img src="logo.jpg" alt="jane" width="256">

** THIS PROJECT IS IN DEVELOPMENT - DO NOT USE IN PRODUCTION YET **

SurFTP is both an FTP server and an FTP client.

Its primary goal is to simplify automation of FTP jobs for both senders and receivers. 

surFTP has many features described below, including built-in user management. 

SurFTP uses libssh to provide a built-in SSH/SFTP server with fully virtual users backed by SQLite — no system accounts needed.

## Requirements

- Linux
- Crystal >= 1.19.1
- libssh development library (debian: `libssh-dev`, fedora: `libssh-devel`)
- libyaml development library (debian: `libyaml-dev`, fedora: `libyaml-devel`, rocky9: dnf config-manager --set-enabled crb && dnf install libyaml-devel)
- SQLite3 development libraries (debian: `libsqlite3-dev`, fedora: `sqlite-devel`)
- dnf install libyaml-devel
- `sshpass` (optional, required for password-based outbound client connections)

## Installation

```sh
shards install
crystal build src/surftp.cr -o surftp
sudo cp surftp /usr/local/bin/
```

## Architecture

SurFTP runs an in-process SSH/SFTP server using libssh. Users are virtual — they exist only in the SQLite database with no corresponding Linux accounts. Each user's files are stored under their home directory (default: `/srv/surftp/<username>/files/`). Path sandboxing is enforced in code to prevent directory traversal.

The `surftp server start` command runs in the foreground. Use systemd or similar to daemonize:

```ini
[Unit]
Description=SurFTP SFTP Server
After=network.target

[Service]
ExecStart=/usr/local/bin/surftp server start --port 2222
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## Configuration

### File Locations

| Path | Purpose |
|------|---------|
| `/var/lib/surftp/surftp.db` | SQLite database (user data, server config) |
| `/etc/surftp/ssh_host_ed25519_key` | Host key (auto-generated on first start) |
| `/etc/surftp/master.key` | Encryption key for client passwords |
| `/etc/surftp/clients/*.yaml` | Outbound client connection configs |

### Server Port

The default port is **2222**. Change it when starting the server:

```sh
sudo surftp server start --port 2222
```

The port is saved in the database and reused on subsequent starts.

### User Home Directories

Each user gets a directory under `/srv/surftp/` by default. For a user named `alice`, files are stored at `/srv/surftp/alice/files/`.

Override per user:

```sh
surftp user add alice --home /data/sftp/alice
```

### Authentication

SurFTP supports both password and public key authentication:

- Passwords are set via `--password` on user creation or changed with `user passwd`
- SSH public keys are managed with `user key add` / `user key remove`
- All credentials are stored in the SQLite database

## CLI Reference

### Server Management

```sh
surftp server start [--port 2222]   # Start the SFTP server (foreground)
surftp server stop                  # Stop the SFTP server
surftp server status                # Show server status
```

### User Management

```sh
# Add a user
surftp user add <username> [--password <pass>] [--home <dir>]

# Remove a user
surftp user remove <username>

# List all users
surftp user list

# Show detailed info for a user
surftp user show <username>

# Enable or disable a user
surftp user enable <username>
surftp user disable <username>

# terminate active SFTP connections for a user
surftp user kill <username>

# show all active FTP sessions on the server
surftp sessions

# Change a user's password (prompts for input)
surftp user passwd <username>
```

### SSH Key Management

```sh
# Add a public key from a file
surftp user key add <username> <pubkey_file>

# Remove a key by its index (shown in `user show`)
surftp user key remove <username> <key_index>
```

### Terminal UI

```sh
surftp tui
```

Interactive interface with views for:

- **Users** -- list, add, edit, enable/disable, delete users
- **Server** -- view status, start/stop the server

Navigate with arrow keys, Enter to select, Esc to go back.

--- 

### Outbound Client Connections

SurFTP can connect to remote SFTP servers to push or pull files. Each remote connection is defined in a YAML config file.

#### Setup

```sh
# Generate the master encryption key (required for password auth)
sudo surftp client init-master-key

# Encrypt a password for use in config files (prompts for input)
surftp client encrypt-password
```

The master key is stored at `/etc/surftp/master.key` (root-readable only). Encrypted passwords are stored in config files as `ENC:<ciphertext>:<iv>:<hmac>` strings.

#### Client Config Files

Create one YAML file per client in `/etc/surftp/clients/<clientname>.yaml`. Each file can contain multiple environments:

```yaml
prod:
  action: push
  host: somehostftp.com
  port: 22
  username: user1
  password: "ENC:base64ciphertext:base64iv:base64hmac"
  auth_type: password
  remote_path: /upload
  local_path: /data/outbound

dev:
  action: pull
  host: dev.somehostftp.com
  port: 2500
  username: devuser1
  auth_type: key
  private_key: /path/to/private/key
  remote_path: /remote/data
  local_path: /data/inbound
```

| Field | Description |
|-------|-------------|
| `action` | `push` or `pull` |
| `host` | Remote SFTP server hostname |
| `port` | Remote port (default: 22) |
| `username` | Remote username |
| `password` | Encrypted password string (use `surftp client encrypt-password` to generate) |
| `auth_type` | `password` or `key` |
| `private_key` | Path to SSH private key file (when `auth_type: key`) |
| `remote_path` | Directory on the remote server |
| `local_path` | Local directory for files |

#### Connect Commands

```sh
# List files on the remote server
surftp connect -c <client> -e <env> -l

# Push or pull a file (action is determined by the env config)
surftp connect -c <client> -e <env> -f <filename>

# create a client config YAML
surftp connect --generate <client>
```



**Examples:**

```sh
# List files on the dev environment of "acme" client
surftp connect -c acme -e dev -l

# Pull a file from the dev environment
surftp connect -c acme -e dev -f report.csv

# Push a file to the prod environment
surftp connect -c acme -e prod -f upload.csv
```

#### Requirements

- Password auth requires `sshpass` to be installed on the system
- Key auth uses the standard `sftp` command with `-i`

## Example Workflow

```sh
# Start the server (foreground, use systemd to daemonize)
surftp server start

# In another terminal, create a user with a password
surftp user add alice --password s3cret

# Add an SSH key for the user
surftp user key add alice ~/.ssh/id_ed25519.pub

# Verify the user was created
surftp user show alice

# Connect via SFTP
sftp -P 2222 alice@localhost

# Stop the server (Ctrl+C or kill)
```

## Development

```sh
shards install
crystal build src/surftp.cr
```
