# Security Policy

## Scope

MockCore is the foundation of a family of **test-time tools**: it runs local mock servers on
your development machine or CI runner to support UI-test automation. It is not designed to be
exposed to untrusted networks or shipped inside production apps, and hardening it for those
uses is out of scope. That said, vulnerabilities that could affect developers using MockCore as
intended (for example, unsafe parsing of seed files, or `MockHost` binding to non-loopback
interfaces unexpectedly) are taken seriously.

## Supported versions

While MockCore is pre-1.0, only the latest released version receives security fixes.

## Reporting a vulnerability

Please **do not** report security issues through public GitHub issues.

Instead, either:

- Use GitHub's private vulnerability reporting on the
  [Security tab](https://github.com/AlexNachbaur/mockcore-swift/security) of the repository, or
- Email <alex@nachbaur.com> with a description of the issue, steps to reproduce, and the
  affected version.

You can expect an acknowledgment within a few days. Please allow a reasonable window for a fix
to be released before disclosing publicly.
