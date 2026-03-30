# AWX Quick Start Guide

Get started with AWX in 5 minutes! This guide walks you through setting up your first Ansible automation workflow.

## Prerequisites

- AWX successfully installed (see [README.md](README.md))
- Access to AWX web interface
- At least one Linux host to manage (target server)

## Step 1: Access AWX

Open your web browser and navigate to:
```
http://YOUR_SERVER_IP:30080
```

Login with credentials from installation (found in `/root/awx-credentials.txt`):
- **Username**: admin
- **Password**: (from installation output)

---

## Step 2: Create an Organization

Organizations separate different teams or projects.

1. Click **Organizations** in the left sidebar
2. Click the **Add** button
3. Fill in:
   - **Name**: My Organization
   - **Description**: Primary organization for automation
4. Click **Save**

---

## Step 3: Add SSH Credentials

AWX needs credentials to connect to managed hosts.

### Option A: SSH Key (Recommended)

1. Click **Credentials** in the left sidebar
2. Click **Add**
3. Fill in:
   - **Name**: My SSH Key
   - **Organization**: My Organization
   - **Credential Type**: Machine
   - **Username**: Your SSH username (e.g., ubuntu, root)
   - **SSH Private Key**: Paste your private key
     ```bash
     # On your AWX server, display your key:
     cat ~/.ssh/id_rsa
     # Copy and paste the entire key including BEGIN/END lines
     ```
4. Click **Save**

### Option B: SSH Password

1. Follow steps 1-3 above
2. Instead of SSH key:
   - **Username**: Your SSH username
   - **Password**: Your SSH password
3. Click **Save**

---

## Step 4: Create an Inventory

Inventories define which hosts to manage.

1. Click **Inventories** in the left sidebar
2. Click **Add → Add inventory**
3. Fill in:
   - **Name**: My Servers
   - **Organization**: My Organization
4. Click **Save**

### Add a Host

1. Click the **Hosts** tab
2. Click **Add**
3. Fill in:
   - **Name**: web-server-1
   - **Variables** (YAML format):
     ```yaml
     ansible_host: 192.168.1.100
     ansible_user: ubuntu
     ```
4. Click **Save**

### Add Multiple Hosts

For multiple hosts, use the **Sources** tab or add them one by one:

```yaml
# Example hosts with variables:
# Host: web-server-2
ansible_host: 192.168.1.101
ansible_user: ubuntu

# Host: db-server-1
ansible_host: 192.168.1.102
ansible_user: ubuntu
ansible_port: 22
```

---

## Step 5: Create a Project

Projects link to Git repositories containing your Ansible playbooks.

### Option A: Use Demo Project

AWX includes a demo project with sample playbooks:

1. Click **Projects** in the left sidebar
2. Look for **Demo Project** (already created)
3. Click on it and verify the **Status** is **Successful**

### Option B: Create Your Own Project

1. Click **Projects** → **Add**
2. Fill in:
   - **Name**: My Playbooks
   - **Organization**: My Organization
   - **SCM Type**: Git
   - **SCM URL**: Your Git repository URL
     ```
     Example: https://github.com/ansible/ansible-examples.git
     ```
   - **SCM Branch/Tag/Commit**: main (or master)
3. Check **Update Revision on Launch**
4. Click **Save**

AWX will clone the repository. Wait for the status to show **Successful**.

### Project Structure with Collections

If your playbooks use collections such as `community.postgresql` or `awx.awx`, organize your Git repository like this:

```text
my-ansible-project/
├── playbooks/
│   ├── site.yml
│   └── manage-awx.yml
├── inventory/
│   └── production.yml
├── group_vars/
│   └── all.yml
└── collections/
    └── requirements.yml
```

Example `collections/requirements.yml`:

```yaml
---
collections:
  - name: community.postgresql
    version: "3.4.0"
  - name: awx.awx
    version: "23.3.1"
```

Example playbook using `community.postgresql`:

```yaml
---
- name: Create PostgreSQL database
  hosts: db_servers
  become: true
  tasks:
    - name: Create application database
      community.postgresql.postgresql_db:
        name: myapp
        encoding: UTF-8
      become_user: postgres
```

For production, prefer putting these collections in a custom execution environment instead of downloading them on each job run. See [README.md](README.md#managing-ansible-collections) and [PACKAGE_INSTALLATION.md](PACKAGE_INSTALLATION.md#ansible-collections-installation).

---

## Step 6: Create a Job Template

Job Templates define what playbook to run and on which hosts.

1. Click **Templates** in the left sidebar
2. Click **Add → Add job template**
3. Fill in:
   - **Name**: Install Nginx
   - **Job Type**: Run
   - **Inventory**: My Servers
   - **Project**: Demo Project (or your project)
   - **Playbook**: Select from dropdown (e.g., `hello_world.yml`)
   - **Credentials**: My SSH Key
  - **Execution Environment**: Select your custom EE if the playbook uses additional collections
   - **Verbosity**: 0 (Normal)
4. Click **Save**

If your playbook uses `awx.awx`, `community.postgresql`, `amazon.aws`, or similar collections, make sure the selected execution environment includes them. Otherwise the job will fail with a "collection not found" error.

---

## Step 7: Launch Your First Job

1. On the **Templates** page, find your template
2. Click the **Rocket** icon (🚀) to launch
3. Watch the job execute in real-time!

You'll see:
- Job status and progress
- Console output as Ansible runs
- Task results (ok, changed, failed)
- Execution time and statistics

---

## Example: Simple Playbook Workflow

Let's create a complete automation workflow from scratch.

### 1. Create Local Git Repository

On any machine with Git:

```bash
# Create playbook directory
mkdir my-ansible-playbooks
cd my-ansible-playbooks

# Initialize Git
git init

# Create a simple playbook
cat > webserver.yml <<'EOF'
---
- name: Setup Web Server
  hosts: all
  become: yes
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
      when: ansible_os_family == "Debian"

    - name: Install Nginx
      apt:
        name: nginx
        state: present
      when: ansible_os_family == "Debian"

    - name: Start Nginx service
      service:
        name: nginx
        state: started
        enabled: yes

    - name: Create simple index page
      copy:
        content: |
          <html>
          <head><title>AWX Automation</title></head>
          <body>
            <h1>Success! Deployed by AWX</h1>
            <p>Automated at {{ ansible_date_time.iso8601 }}</p>
          </body>
          </html>
        dest: /var/www/html/index.html
        mode: '0644'

    - name: Display result
      debug:
        msg: "Web server deployed successfully! Visit http://{{ ansible_host }}"
EOF

# Commit
git add .
git commit -m "Initial playbook"

# Push to GitHub (create repo first at github.com)
git remote add origin https://github.com/YOUR_USERNAME/my-ansible-playbooks.git
git push -u origin main
```

### 2. Add Project in AWX

1. Navigate to **Projects** → **Add**
2. Configure:
   - **Name**: Web Server Playbooks
   - **SCM Type**: Git
   - **SCM URL**: `https://github.com/YOUR_USERNAME/my-ansible-playbooks.git`
   - Check **Update Revision on Launch**
3. Click **Save**

### 3. Create Job Template

1. Navigate to **Templates** → **Add → Add job template**
2. Configure:
   - **Name**: Deploy Web Server
   - **Inventory**: My Servers
   - **Project**: Web Server Playbooks
   - **Playbook**: webserver.yml
   - **Credentials**: My SSH Key
   - **Privilege Escalation**: Check "Enable Privilege Escalation"
3. Click **Save**

### 4. Run the Job

1. Click the **Rocket** icon next to your template
2. Watch Nginx get installed on your hosts!
3. Visit `http://YOUR_HOST_IP` to see the deployed page

---

## Common Use Cases

### 1. System Updates

```yaml
# update-servers.yml
---
- name: Update all servers
  hosts: all
  become: yes
  tasks:
    - name: Update apt packages
      apt:
        upgrade: dist
        update_cache: yes
      when: ansible_os_family == "Debian"
```

### 2. User Management

```yaml
# create-user.yml
---
- name: Create user account
  hosts: all
  become: yes
  vars:
    username: deploy
    user_ssh_key: "ssh-rsa AAAAB3N..."
  tasks:
    - name: Create user
      user:
        name: "{{ username }}"
        shell: /bin/bash
        groups: sudo
        append: yes

    - name: Add SSH key
      authorized_key:
        user: "{{ username }}"
        key: "{{ user_ssh_key }}"
```

### 3. Docker Installation

```yaml
# install-docker.yml
---
- name: Install Docker
  hosts: all
  become: yes
  tasks:
    - name: Install prerequisites
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - software-properties-common
        state: present

    - name: Add Docker GPG key
      apt_key:
        url: https://download.docker.com/linux/ubuntu/gpg
        state: present

    - name: Add Docker repository
      apt_repository:
        repo: deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable
        state: present

    - name: Install Docker
      apt:
        name: docker-ce
        state: present
        update_cache: yes

    - name: Start Docker service
      service:
        name: docker
        state: started
        enabled: yes
```

---

## Scheduling Jobs

Make jobs run automatically:

1. Open your Job Template
2. Click the **Schedules** tab
3. Click **Add**
4. Configure:
   - **Name**: Nightly Updates
   - **Start date**: Today
   - **Local time zone**: Your timezone
   - **Repeat frequency**: Day
   - **Run every**: 1 day
   - **Start time**: 02:00 AM
5. Click **Save**

Jobs will now run automatically on schedule!

---

## Survey Variables

Let users provide input when launching jobs:

1. Edit your Job Template
2. Click the **Survey** tab
3. Click **Add**
4. Create a question:
   - **Question**: Server Name
   - **Answer Variable Name**: server_name
   - **Answer Type**: Text
   - **Required**: Yes
5. Click **Save**
6. **Save** the template

When users launch the job, they'll be prompted for input!

Use in playbooks:
```yaml
- name: Use survey variable
  debug:
    msg: "Deploying to {{ server_name }}"
```

---

## Notifications

Get notified when jobs complete:

1. Navigate to **Notifications**
2. Click **Add**
3. Configure notification type:
   - **Email**: SMTP settings
   - **Slack**: Webhook URL
   - **Webhook**: Custom HTTP endpoint
4. Attach notification to Job Template:
   - Edit template
   - Click **Notifications** tab
   - Add notification for success/failure

---

## Best Practices

### 1. Use Variables

Store configuration in inventories or surveys:
```yaml
# Inventory variables
ansible_host: 192.168.1.100
app_port: 8080
domain_name: example.com
```

### 2. Create Workflows

Chain multiple job templates:
1. **Templates** → **Add → Add workflow template**
2. Add job templates as nodes
3. Define success/failure paths
4. Complex multi-step automations!

### 3. Use Credentials Properly

- **Never** hardcode passwords in playbooks
- Use AWX credentials for all secrets
- Create different credentials for different purposes
- Use Ansible Vault for repository secrets

### 4. Organize with Labels

Tag templates for easy filtering:
- Edit template → **Labels** tab
- Add: production, staging, web, database
- Filter templates by label

### 5. Monitor Activity

Check the **Activity Stream** for:
- Who ran what jobs
- Configuration changes
- Failed logins
- Audit trail

---

## Next Steps

Now that you've completed your first automation:

1. **Explore AWX Features**
   - Workflow Templates
   - Smart Inventories
   - Custom Credential Types
   - Instance Groups

2. **Learn Ansible**
   - [Ansible Documentation](https://docs.ansible.com/)
   - [Ansible Galaxy](https://galaxy.ansible.com/) for roles
   - [Ansible Examples](https://github.com/ansible/ansible-examples)

3. **Integrate with Tools**
   - Connect to LDAP/AD for authentication
   - Use with GitLab/GitHub CI/CD
   - Connect to cloud providers (AWS, Azure, GCP)
   - Export metrics to monitoring systems

4. **Scale Your Automation**
   - Add more hosts to inventories
   - Create dynamic inventories
   - Build workflow templates
   - Set up execution nodes for distributed automation

---

## Quick Reference Commands

### AWX CLI (optional)

Install AWX CLI for command-line management:

```bash
# Install
pip3 install awxkit

# Configure
awx --conf.host http://localhost:30080 \
    --conf.username admin \
    --conf.password YOUR_PASSWORD

# List resources
awx jobs list
awx job_templates list
awx inventories list

# Launch job
awx job_templates launch <template_id>
```

### Useful kubectl Commands

```bash
# View AWX status
kubectl get pods -n awx
kubectl get svc -n awx

# View logs
kubectl logs deployment/awx-web -n awx -f
kubectl logs deployment/awx-task -n awx -f

# Access AWX container
kubectl exec -it deployment/awx-task -n awx -- bash

# Inside container - AWX management commands
awx-manage list_instances
awx-manage check
awx-manage inventory_import --help
```

---

## Resources

- **Documentation**: https://ansible.readthedocs.io/projects/awx/
- **API Reference**: http://YOUR_SERVER:30080/api/v2/
- **Community**: https://forum.ansible.com/
- **GitHub**: https://github.com/ansible/awx

Happy Automating! 🚀
