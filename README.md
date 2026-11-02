# FFxF MCP server

Remote [Model Context Protocol](https://modelcontextprotocol.io) server for [FFxF](https://ffxf.net), a cloud provider in Montréal, Canada. It lets an AI agent rent and manage KVM virtual machines, managed databases, private networks, firewalls, load balancers and GitHub Actions runners through the FFxF API.

- **Endpoint:** `https://ffxf.net/mcp` (Streamable HTTP, stateless)
- **Auth:** `Authorization: Bearer <FFxF API key>`. The catalogue tools work without a key.
- **Official MCP registry:** `net.ffxf/cloud`
- **Docs:** https://ffxf.net/agents and https://ffxf.net/docs/mcp/

This repository documents the hosted server and gives ready-to-use client configurations. The server itself runs at FFxF; its source is not published here, and there is nothing to install.

## Get an API key

Create a key at https://console.ffxf.net/account/api-keys and give it only the scopes the agent needs:

| Scope | Allows |
|---|---|
| `vms.read` | Read machines, networks, firewalls, load balancers, databases, runners |
| `vms.create` | Order machines |
| `vms.action` | Power, rename, reinstall |
| `vms.destroy` | Destroy machines |
| `network.write` | Private networks, firewalls, load balancers, reverse DNS |
| `databases.write` | Managed databases, users, extensions |
| `backups.write` | On-demand database backups |
| `sshkeys.write` | Add and remove SSH keys |
| `billing.read` | Credit balance and budget caps |

In CI, the bearer can instead be a short-lived OIDC token (GitHub Actions, GitLab CI) bound to scopes in the console under Account → OIDC.

## Connect a client

Replace `ffxf_live_…` with your key. Ready-made files are in [`examples/`](examples/).

**Claude Code**

```sh
claude mcp add --transport http ffxf https://ffxf.net/mcp \
  --header "Authorization: Bearer ffxf_live_…"
```

**Cursor** (`~/.cursor/mcp.json`) and other clients that read `mcpServers`

```json
{
  "mcpServers": {
    "ffxf": {
      "url": "https://ffxf.net/mcp",
      "headers": {
        "Authorization": "Bearer ffxf_live_…"
      }
    }
  }
}
```

**VS Code** (`.vscode/mcp.json`)

```json
{
  "servers": {
    "ffxf": {
      "type": "http",
      "url": "https://ffxf.net/mcp",
      "headers": {
        "Authorization": "Bearer ${input:ffxf-api-key}"
      }
    }
  },
  "inputs": [
    {
      "id": "ffxf-api-key",
      "type": "promptString",
      "description": "FFxF API key",
      "password": true
    }
  ]
}
```

To try it without a key, call `list_plans`: the catalogue is public.

## How agents should use it

The server sends these rules to the client at `initialize`; they are summarised here.

1. Read the catalogue first: `list_regions`, `list_plans`, `list_images`.
2. Call `estimate_vm` and show the price to the user before `create_vm`.
3. Creation, reinstall and power changes are asynchronous: poll `get_action` until its status leaves `running`.
4. `destroy_vm`, `reinstall_vm`, `delete_database` and `delete_logical_database` erase data. Ask the user first. `destroy_vm` and `reinstall_vm` require the machine's exact hostname, and `delete_database` the database's exact name, as confirmation.
5. When adding a firewall, keep TCP 22 (or 3389 on Windows) open unless the user says otherwise.

Hourly machines draw on prepaid credit; monthly machines raise an invoice. Prices are in Canadian dollars, taxes included: https://ffxf.net/pricing

## Tools

71 tools in version 1.12.0. Each tool carries MCP annotations (read-only, destructive) so clients can ask before acting.

### Catalogue (no key)

| Tool | What it does |
|---|---|
| `list_regions` | Where machines can run. |
| `list_plans` | Plans with their resources and prices (hourly and monthly, in CAD). |
| `list_images` | Operating systems and ready-to-use application images. |

### Account and SSH keys

| Tool | What it does |
|---|---|
| `get_account` | Credit balance, hourly burn rate and runway, quota and budget caps. |
| `list_ssh_keys` | SSH keys saved on the account, to pass to create_vm. |
| `add_ssh_key` | Saves a public key on the account so new machines can be reached without a password. |
| `delete_ssh_key` | Removes a key from the account. |

### Virtual machines

| Tool | What it does |
|---|---|
| `list_vms` | The account's machines with their status, addresses and billing. |
| `get_vm` | One machine: status, IPv4, IPv6 /64, specs, traffic (Internet only, this traffic month: used_gb, limit_gb, period_ends_at), billing, suspension. |
| `get_vm_metrics` | CPU, memory, disk and network as measured from outside the machine. |
| `estimate_vm` | Runs every check of create_vm and prices it, without creating anything: would_succeed, hourly rate, monthly price, credit required. |
| `create_vm` | Orders a machine and spends credit (hourly) or raises an invoice (monthly). |
| `power_vm` | start, shutdown (clean ACPI), reboot, or stop (hard power-off). |
| `rename_vm` | Changes the hostname, inside the guest and in the console. |
| `reinstall_vm` | ERASES THE DISK and redeploys another image. |
| `destroy_vm` | DESTROYS the machine and its disk, with no undo and no backup kept. |
| `get_action` | Follows an asynchronous action (create, reinstall, power…). |
| `list_vm_actions` | History of actions on one machine, from the API and the console. |
| `get_vm_network` | IPv4 and IPv6 addresses of a machine with their reverse DNS, and its private networks. |
| `set_reverse_dns` | Sets the PTR record of one of the machine's addresses; null restores the default. |

### Private networks (VPC)

| Tool | What it does |
|---|---|
| `list_vpcs` | The account's private networks with their range, gateway and connected machines, plus the quota. |
| `get_vpc` | One private network and the machines on it, with their private address. |
| `create_vpc` | Creates an isolated private network; ready when the call returns. |
| `delete_vpc` | Deletes an empty private network. |
| `connect_vpc` | Hot-adds a card on the private network and sets its address in the system, without a restart. |
| `disconnect_vpc` | Removes the machine's private address and card, without a restart. |
| `move_vpc` | Joins the target network, then leaves this one, so the machine is never cut off. |

### Firewalls

| Tool | What it does |
|---|---|
| `list_firewalls` | The account's firewalls with their inbound rules and the machines they protect, plus the quota. |
| `get_firewall` | One firewall: its rules and the machines it protects, with the status of each (applied, pending, error). |
| `create_firewall` | Creates a reusable set of inbound and outbound rules. |
| `update_firewall` | rules REPLACES the whole list and is applied at once to every attached machine: send every rule to keep, not only the new one (read get_firewall first). |
| `delete_firewall` | Deletes a firewall attached to no machine. |
| `attach_firewall` | From now on the machine refuses inbound traffic no rule of its firewalls opens; enforced within about ten seconds of the call. |
| `detach_firewall` | Removes the firewall's rules from the machine; with no other firewall it accepts all inbound traffic again. |

### Load balancers

| Tool | What it does |
|---|---|
| `list_load_balancers` | The account's load balancers with their addresses, pools, targets and health, listeners and rules, certificates; plus the quota. |
| `get_load_balancer` | One load balancer in full: status, ipv4/ipv6 to put in DNS, pools with targets (health, sessions, response time), listeners with rules in evaluation order, certificates. |
| `get_load_balancer_metrics` | Requests by response class, connections, bytes in/out and peak sessions over 1h (1-minute buckets), 24h (15 minutes) or 7d (1 hour), plus totals. |
| `create_load_balancer` | Orders a load balancer in a private network, billed by the hour from now (the account needs 24 hours of credit), or by the month (7.30 CAD) or the year (73 CAD) with billing. |
| `delete_load_balancer` | Deletes the load balancer, its address and its configuration; billing stops. |
| `upsert_pool` | Without pool: creates one (name required, up to 10). |
| `delete_pool` | Removes a pool, its targets and the rules leading to it. |
| `set_targets` | REPLACES the pool's targets with exactly this list (up to 25): send every target to keep. |
| `upsert_listener` | An entry port on the load balancer's address. |
| `delete_listener` | Closes the port and removes its rules. |
| `set_rules` | REPLACES the http/https listener's rules: each sends a hostname and/or path prefix to an http pool (up to 25). |

### Managed databases

| Tool | What it does |
|---|---|
| `list_databases` | The account's managed databases with their status, private and public addresses, disk, backups and billing (no passwords), plus the quota. |
| `get_database_options` | What can be ordered: engines and versions, extensions, sizes with their hourly, monthly and yearly prices per region, and the price of disk beyond what a size includes. |
| `get_database` | One database: status, connection (host, private ip, port, defaultdb and ffxfadmin; on Valkey no database and default), public access and sources, disk usage and cap, users with their databases (null: all) and read_only, logical databases and extensions, Valkey's eviction policy and data memory, backups and restore window, maintenance window, fork link, warning. |
| `get_database_credentials` | Every user with its password, databases and read_only, and its own connection_uri; ready-made connection strings for the admin (private network, and public when open). |
| `get_database_metrics` | CPU, memory, connections and commits per minute (commands per minute on Valkey) over 1h (1-minute buckets), 24h (10 minutes) or 7d (1 hour); only buckets with samples. |
| `get_slow_queries` | The 20 queries with the most total time (pg_stat_statements, values replaced by $1, $2…; performance_schema on MySQL and MariaDB, values replaced by ?): calls, total and mean time, rows. |
| `list_database_backups` | Completed backups (weekly full, daily differential; the transaction log is archived continuously) and the restore window: any minute in it can be restored with restore_database. |
| `create_database` | Orders a managed database (PostgreSQL, MySQL, MariaDB or Valkey) in a private network, billed by the hour from now (the account needs 24 hours of credit), or by the month (730 hours) or the year (ten months) with billing; get_database_options gives each price. |
| `restore_database` | Creates a NEW database, billed like any other, holding the data as it was at a given minute of the source's restore window (list_database_backups; Valkey: the last snapshot before that minute), with the same users and passwords. |
| `fork_database` | Creates a NEW database, billed like any other, whose data is an instant copy of this one (for a test or staging copy), with the same users and passwords. |
| `detach_database_fork` | Gives a linked fork its own copy of the data; the database is unavailable for about 30 seconds, then its backups start. |
| `resize_database` | Moves the database to a LARGER size (more vCPU, memory and included disk; see get_database_options): same data, users, names and addresses. |
| `delete_database` | DELETES the database and its data; billing stops. |
| `update_database` | Any of: the name; the weekly maintenance window (day 0 = Sunday, start hour, Montréal time, 2 hours long; minor updates, usually under 2 minutes of downtime); the disk cap (the disk grows by itself at 80 % full, up to the cap; disk beyond what the size includes is billed per GB); on Valkey, the eviction policy. |
| `set_database_public_access` | Opens the database to the internet at its public host and port (IPv4 and IPv6, TLS and password still required), or closes it. |
| `backup_database` | Starts a differential backup within a minute, for example before a risky migration. |
| `create_database_user` | Creates a user with a generated password, returned here once (also readable with get_database_credentials); live within seconds. |
| `set_database_user_access` | Sets the logical databases a user connects to (databases: a list, or null for all of them, future ones included) and whether it only reads; a field left out keeps its value. |
| `reset_database_password` | Gives the user a new password, returned here; the old one stops working within seconds, so update the application first or right after. |
| `delete_database_user` | Hands the user's objects to the admin, then drops the user. |
| `create_logical_database` | Creates another database inside the managed database (like defaultdb), owned by the admin; up to 30. |
| `delete_logical_database` | DROPS the logical database with everything in it (the backups keep it 7 days). |
| `enable_extension` | PostgreSQL only: enables an extension such as pgvector, PostGIS or pg_trgm in one logical database. |
| `disable_extension` | Drops the extension without CASCADE: if objects depend on it, it stays and get_database shows why in warning. |

### GitHub Actions runners

| Tool | What it does |
|---|---|
| `get_runners` | The runs-on labels with their vCPU, memory and price per minute, the account's concurrency (vCPU of jobs starting or running, and the cap), the linked GitHub organizations and accounts, this month's minutes and cost per repository, the actions cache next to the runners (bytes, entries and last use per repository, price per GB per month), and the Docker cache per repository (enabled in the console, bytes, last successful job). |
| `list_runner_jobs` | Jobs that ran or wait on FFxF runners, most recent first: repository, workflow and job, label, status (queued with waiting_reason credit, budget or account; running; succeeded; failed, stopped_for_credit when the credit ran out; cancelled; refused with refusal), times, billed minutes and amount, link to the run. |

## Support

- Status: https://status.ffxf.net
- Discord: https://discord.gg/JpM5NMKrwM
- Email: contact@ffxf.net

Issues about this documentation are welcome in this repository.

## License

The documentation and examples in this repository are under the MIT license.
