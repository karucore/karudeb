# karudeb lab SSH keys

These keys are intentionally committed for reproducible local lab images. Git
stores private-key files as normal non-executable files; image builds install
the sensitive target-side files with restrictive permissions.

- `karudeb_lab_ed25519`: client key kept in the repo for lab access.
- `karudeb_lab_ed25519.pub`: installed as `authorized_keys` with mode `0600`.
- `karudeb_host_ed25519_key`: installed as `/etc/ssh/ssh_host_ed25519_key` with mode `0600`.

Fingerprints:

```text
SHA256:iKgWaITwl//S4spRG8cyrWTly/l4F80OCD4VZ/kEZBo  karudeb_lab_ed25519.pub
SHA256:5OJQmZxbt5/ina0fbSTS/Ocfy6QJ7RNa9NQPhjTPohQ  karudeb_host_ed25519_key.pub
```

Do not use these keys for exposed or production systems. Override
`KARUDEB_SSH_AUTHORIZED_KEYS` and `KARUDEB_SSH_HOST_ED25519_KEY` when building
images that need private credentials. Set either variable to an empty value to
skip installing the corresponding lab key.
