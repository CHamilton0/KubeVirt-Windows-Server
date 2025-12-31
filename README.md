# KubeVirt Windows Server

## Requirements

- Python 3.11
- Ansible
- Helm
- KubeVirt
- Kubernetes

## Install the Helm Chart

```bash
ansible-playbook playbooks/deploy.yml --ask-vault-pass
virtctl vnc -n vm windows-server-2022-vm
```

## Uninstall the Helm Chart

```bash
helm uninstall -n vm windows-server-2022
```
