# SurFTP

<img src="logo.jpg" alt="jane" width="256">
  
** THIS PROJECT IS IN DEVELOPMENT - DO NOT USE IN PRODUCTION YET **

An SFTP server with built-in user management. SurFTP wraps OpenSSH's `sshd`/`internal-sftp` for protocol handling and provides a CLI and terminal UI for administration. User data is stored in SQLite.

## Requirements

- Linux
- Crystal >= 1.19.1
- OpenSSH (`sshd`)
- SQLite3 development libraries (`libsqlite3-dev`)
- Root access (required for system user creation, chroot, and sshd)

## Installation

```sh
shards install
crystal build src/surftp.cr -o surftp
sudo cp surftp /usr/local/bin/
```

## Configuration

### File Locations

| Path | Purpose |
|------|---------|
| `/var/lib/surftp/surftp.db` | SQLite database (user data, server data) |
| `/etc/surftp/sshd_config` | Auto-generated sshd config |
| `/etc/surftp/ssh_host_ed25519_key` | Host key (auto-generated on first start) |
| `/var/run/surftp/sshd.pid` | PID file for the sshd process |

### Server Port

The default port is **2222**. Change it when starting the server:

```sh
sudo surftp server start --port 2222
```

The port is saved in the database and reused on subsequent starts.

### User Home Directories

Each user gets a chroot directory. The default base path is `/srv/surftp/`. For a user named `alice`, the default home would be `/srv/surftp/alice/`.

Override per user:

```sh
sudo surftp user add alice --home /data/sftp/alice
```

Inside each home directory, a `files/` subdirectory is created where the user can read and write. The chroot directory itself is owned by root (required by OpenSSH).

### Authentication

SurFTP supports both password and public key authentication:

- Passwords are set via `--password` on user creation or changed with `user passwd`
- SSH public keys are managed with `user key add` / `user key remove`
- Keys are stored in the database and served to sshd via `AuthorizedKeysCommand`

## CLI Reference

### Server Management

```sh
sudo surftp server start [--port 2222]   # Start the SFTP server
sudo surftp server stop                  # Stop the SFTP server
surftp server status                     # Show server status (running/stopped, PID, port)
```

### User Management

```sh
# Add a user (requires root)
sudo surftp user add <username> [--password <pass>] [--home <dir>]

# Remove a user and their system account
sudo surftp user remove <username>

# List all users
surftp user list

# Show detailed info for a user
surftp user show <username>

# Enable or disable a user
surftp user enable <username>
surftp user disable <username>

# Change a user's password (prompts for input)
sudo surftp user passwd <username>
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

### Internal Commands

```sh
surftp auth-keys <username>
```

Used internally by sshd's `AuthorizedKeysCommand` to look up SSH keys from the database. Not intended to be called directly.

## Example Workflow

```sh
# Start the server on port 2222
sudo surftp server start

# Create a user with a password
sudo surftp user add alice --password s3cret

# Add an SSH key for the user
sudo surftp user key add alice ~/.ssh/id_ed25519.pub

# Verify the user was created
surftp user show alice

# Connect via SFTP
sftp -P 2222 alice@localhost

# Stop the server
sudo surftp server stop
```

## Development

```sh
shards install
crystal build src/surftp.cr
```
