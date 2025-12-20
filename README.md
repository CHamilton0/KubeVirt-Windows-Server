# KubeVirt Windows Server

## Install the Helm Chart

```bash
ansible-playbook playbooks/windows-vm.yml
virtctl vnc -n vm windows-server-2022
```

## Uninstall the Helm Chart

```bash
helm uninstall -n vm windows-server-2022
```
