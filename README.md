# KubeVirt Windows Server

## Requirements

- Python 3.11
- Ansible
- Helm
- KubeVirt
- Kubernetes

## Install the Helm Chart

```bash
ansible-playbook playbooks/windows-vm.yml
virtctl vnc -n vm windows-server-2022
```

## Uninstall the Helm Chart

```bash
helm uninstall -n vm windows-server-2022
```

## Getting disk image

First turn off the install VM, then run the following to get a disk image from it.

```bash
virtctl vmexport -n vm download server-export --output disk.img --port-forward --pvc os-pvc
```

This can then be used as the disk for a runtime VM
