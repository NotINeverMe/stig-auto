# Windows Hardening Ansible Role

This role implements Windows server hardening controls mapped to NIST 800-171 rev2 requirements.

## Requirements

- Windows Server 2019 or 2022
- PowerShell 5.1 or later
- Administrative privileges
- ansible.windows collection

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Hardening mode: Full, Essential, or Custom
windows_hardening_mode: Essential

# Enable dry run mode
windows_hardening_dry_run: false

# Security baseline settings
windows_hardening_enable_firewall: true
windows_hardening_enable_defender: true
windows_hardening_enable_fips: true
```

## Dependencies

None.

## Example Playbook

```yaml
- hosts: windows_servers
  roles:
    - role: windows-hardening
      vars:
        windows_hardening_mode: Full
        windows_hardening_enable_bitlocker: true
```

## NIST 800-171 Control Mapping

This role implements the following NIST 800-171 rev2 control families:

- **3.1.x** - Access Control
- **3.3.x** - Audit and Accountability  
- **3.4.x** - Configuration Management
- **3.5.x** - Identification and Authentication
- **3.13.x** - System and Communications Protection
- **3.14.x** - System and Information Integrity

## License

See project LICENSE file.

## Author Information

Part of the STIG Pipe automation project.