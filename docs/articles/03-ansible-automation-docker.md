---
title: "Immutable Host Configuration: Automating Docker CE Engine Setup with Ansible"
subtitle: "Part 3 of the Production DevOps Series: Managing Linux Package Locks, Upstream GPG Repositories, and Systemd Services without Shell Scripts"
tags: ["ansible", "docker", "devops", "linux", "automation", "sysadmin"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 3
canonical_url: ""
cover_image: ""
---

# Immutable Host Configuration: Automating Docker CE Engine Setup with Ansible

Terraform provisions cloud infrastructure, but provisioning a running Linux VM is only half the battle. If your deployment process relies on ad-hoc SSH sessions and copy-pasted `curl | bash` commands, you have replaced cloud drift with configuration drift.

In Part 3 of our DevOps engineering series, we automate host configuration using **Ansible**. We will configure our newly provisioned Ubuntu 24.04 server into an enterprise Docker host. Along the way, we solve real-world production challenges including `cloud-init` race conditions, Debian `dpkg` package locks, official GPG keyring authentication, and unprivileged user group membership.

---

## 1. Architectural Division of Labor: Terraform vs. Ansible

A clean infrastructure pipeline maintains a strict division of responsibility:

```text
 ┌────────────────────────────────────────────────────────┐
 │ Terraform (Infrastructure as Code - Day 0 Provisioning)│
 │  • AWS VPC, Subnet, Internet Gateway                   │
 │  • EC2 Host & Security Groups                          │
 │  • Generates Dynamic Ansible Inventory (hosts.ini)     │
 └───────────────────────────┬────────────────────────────┘
                             │
                             ▼
 ┌────────────────────────────────────────────────────────┐
 │ Ansible (Configuration Management - Day 1 Configuration│
 │  • Wait for SSH handshake & cloud-init completion      │
 │  • Acquire apt/dpkg locks cleanly                      │
 │  • Configure official upstream Docker GPG repo         │
 │  • Install Docker CE, Buildx & Compose plugins         │
 │  • Manage systemd daemon & user permissions            │
 └────────────────────────────────────────────────────────┘
```

Using shell scripts in EC2 `user_data` might seem simpler at first, but `user_data` executes blindly without state verification, error inspection, or idempotency. Ansible brings declarative desired-state management, reporting whether a task made a change (`changed`), found the system already in the desired state (`ok`), or encountered a failure (`failed`).

---

## 2. Directory Structure & Ansible Configuration

Organize your configuration codebase using modular Ansible roles:

```text
phase1/ansible/
├── ansible.cfg                    # Ansible runtime settings (SSH tuning, host checking)
├── inventory/
│   ├── hosts.ini.tpl              # Template evaluated by Terraform
│   └── hosts.ini                  # Generated dynamic inventory
├── playbooks/
│   └── site.yml                   # Master execution playbook with pre-tasks
└── roles/
    └── docker/
        └── tasks/
            └── main.yml           # Declarative Docker CE installation tasks
```

### Configuring Ansible Behavior (`ansible.cfg`)

Create `ansible.cfg` in your Ansible root to enable modern output formatting, SSH pipelining, and disable prompt-blocking host key verification in automated environments:

```ini
[defaults]
inventory          = inventory/hosts.ini
roles_path         = roles
remote_user        = ubuntu
host_key_checking  = False
retry_files_enabled = False
stdout_callback    = yaml
bin_ansible_callbacks = True

[privilege_escalation]
become             = True
become_method      = sudo
become_user        = root
become_ask_pass    = False

[ssh_connection]
pipelining         = True
ssh_args           = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
```

---

## 3. Resolving Real-World Boot Races: The Master Playbook (`site.yml`)

When an Ubuntu instance first boots on AWS, the OS background agent (`cloud-init`) immediately runs automatic package upgrades. If Ansible attempts to run `apt` concurrently, the playbook crashes with:

```text
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1234 (unattended-upgr)
```

We solve this cleanly in `playbooks/site.yml` using declarative `pre_tasks`:

```yaml
---
- name: Configure EC2 Docker Host
  hosts: docker_hosts
  become: true
  gather_facts: false # Do not gather facts until SSH connectivity is confirmed

  pre_tasks:
    - name: Wait for SSH port to respond
      ansible.builtin.wait_for_connection:
        delay: 10
        timeout: 300

    - name: Gather facts once connected
      ansible.builtin.setup:

    - name: Wait for cloud-init to finish first-boot tasks
      ansible.builtin.command: cloud-init status --wait
      changed_when: false

    - name: Wait for any active apt/dpkg file locks to be released
      ansible.builtin.shell: |
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
              fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
              fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
          sleep 3
        done
      args:
        executable: /bin/bash
      changed_when: false

    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Upgrade all packages to latest security baseline
      ansible.builtin.apt:
        upgrade: dist
        autoremove: true

  roles:
    - docker
```

---

## 4. Building the Modular Docker Role (`roles/docker/tasks/main.yml`)

Never install the outdated `docker.io` package from Ubuntu's default universe repository. Production environments demand official upstream Docker CE releases.

Here is the step-by-step role implementation:

```yaml
---
# 1. Install prerequisites for secure HTTPS package management
- name: Install apt prerequisites for Docker repository
  ansible.builtin.apt:
    name:
      - ca-certificates
      - curl
      - gnupg
    state: present
    update_cache: false

# 2. Prepare modern keyrings directory (compliant with Debian debsig standards)
- name: Create /etc/apt/keyrings directory
  ansible.builtin.file:
    path: /etc/apt/keyrings
    state: directory
    mode: "0755"

# 3. Securely download the official Docker GPG key
- name: Download Docker official GPG key
  ansible.builtin.get_url:
    url: https://download.docker.com/linux/ubuntu/gpg
    dest: /etc/apt/keyrings/docker.asc
    mode: "0644"
    force: false # Idempotent: do not re-download if file is already present

# 4. Register Docker apt repository with explicit GPG signature verification
- name: Add Docker apt repository
  ansible.builtin.apt_repository:
    repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present
    filename: docker
    update_cache: true

# 5. Install Docker CE Engine and modern CLI plugins
- name: Install Docker CE and official plugins
  ansible.builtin.apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    state: present

# 6. Ensure Docker daemon starts on boot and is running
- name: Start and enable Docker systemd service
  ansible.builtin.systemd:
    name: docker
    state: started
    enabled: true
    daemon_reload: true

# 7. Grant the unprivileged ubuntu user access to the Docker socket
- name: Add ubuntu user to docker group
  ansible.builtin.user:
    name: ubuntu
    groups: docker
    append: true

# 8. Smoke test container execution
- name: Verify Docker daemon functionality with hello-world
  ansible.builtin.command:
    cmd: docker run --rm hello-world
  changed_when: true
  become: true
```

---

## 5. Executing the Playbook & Analyzing Output

Execute Ansible from your local terminal against the dynamic inventory:

```bash
# Verify connectivity across inventory hosts
ansible -m ping docker_hosts

# Execute the complete configuration playbook
ansible-playbook playbooks/site.yml
```

### Analyzing the Play Recap

A healthy first run finishes with zero failed tasks:

```text
PLAY RECAP *********************************************************************
54.210.45.12               : ok=11   changed=8    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Verifying on the Remote Server

Connect via SSH to confirm Docker status, version, and socket permissions without `sudo`:

```bash
ssh -i ~/.ssh/zeetafin-key ubuntu@$(terraform -chdir=.. output -raw public_ip)

# 1. Check Docker service status
systemctl status docker --no-pager

# 2. Check installed Docker and Compose versions
docker version
docker compose version

# 3. Confirm access to Docker without sudo (new login session)
docker ps
```

---

## 6. Common Pitfalls & Troubleshooting

| Symptom | Root Cause | Solution |
| :--- | :--- | :--- |
| **`Host key verification failed`** | SSH host key for the new EC2 IP changed or is unknown. | Add `host_key_checking = False` in `ansible.cfg` or use `StrictHostKeyChecking=no`. |
| **`Permission denied (got 13)` accessing `/var/run/docker.sock`** | User was added to the `docker` group, but the current shell session has not refreshed its group claims. | Log out and start a fresh SSH session, or run `newgrp docker`. |
| **`Failed to download GPG key`** | Outbound HTTPS (port 443) blocked by security group egress. | Verify that your security group egress rule allows all outbound traffic (`0.0.0.0/0`). |

---

## 7. Production Takeaways

1. **Guard Against Startup Races:** Cloud virtual machines always run asynchronous initialization routines. Always wait for `cloud-init` and `dpkg` locks before modifying package managers.
2. **Standardize on Modern GPG Keys:** Do not use deprecated `apt-key add`. Modern Linux configurations isolate repository keys inside `/etc/apt/keyrings/`.
3. **Keep Roles Single-Purpose:** Separating your configuration into discrete roles (`roles/docker`, `roles/security`, `roles/monitoring`) makes playbooks reusable across development, staging, and production environments.

---

## Next Steps

With our host operational and Docker configured, we must test for idempotency and establish failure recovery protocols before handling application deployments.

👉 **Next in Series:** [Part 4: Production Verification: Ansible Idempotency Testing, Failure Recovery, and Infrastructure Auditing](./04-idempotency-testing-troubleshooting.md)
