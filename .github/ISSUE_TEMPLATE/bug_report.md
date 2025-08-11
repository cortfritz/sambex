---
name: Bug Report
about: Create a report to help us improve Sambex
title: '[BUG] '
labels: bug
assignees: ''

---

## Bug Description
A clear and concise description of what the bug is.

## To Reproduce
Steps to reproduce the behavior:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior
A clear and concise description of what actually happened.

## Environment
- **OS**: [e.g. Ubuntu 22.04, macOS 13.0, Windows 11]
- **Elixir version**: [e.g. 1.18.0]
- **OTP version**: [e.g. 27.0]
- **Sambex version**: [e.g. 0.1.0]
- **SMB server**: [e.g. Samba 4.15, Windows Server 2019]

## SMB Configuration
- **SMB server version**: [e.g. SMB 3.0]
- **Authentication method**: [e.g. username/password, domain]
- **Share type**: [e.g. public, private, domain-joined]

## Error Messages
```
Paste any error messages, stack traces, or logs here
```

## Code Sample
```elixir
# Minimal code sample that reproduces the issue
Sambex.init()
Sambex.list_dir("smb://server/share", "user", "pass")
```

## Additional Context
Add any other context about the problem here:
- Does it happen consistently or intermittently?
- Did it work in a previous version?
- Any workarounds you've found?

## Possible Solution
If you have an idea of what might be causing the issue or how to fix it, please describe it here.

## Checklist
- [ ] I have searched existing issues to ensure this is not a duplicate
- [ ] I have provided a minimal code sample that reproduces the issue
- [ ] I have included relevant error messages and logs
- [ ] I have tested with the latest version of Sambex
- [ ] I have verified the SMB server is accessible from other clients