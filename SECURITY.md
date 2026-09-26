# Security

zr is a compiler: it writes binaries that other people run. A defect
that makes a binary do something its program does not say is a
security problem, and so is a defect in the runtime that a program's
input can reach.

## Report a problem

Do not open a public issue. Use GitHub's private vulnerability
reporting for this repository (Security, then "Report a
vulnerability"), or write to ryan@ryanseys.com.

Include the output of `zr doctor` (the zr and ruby versions, the host
and what it builds), the target, the smallest program that shows the
problem, and what the binary does.

You will get a reply within a week. A fix goes into the next release,
and the CHANGELOG names the problem once the release is out.

## Supported versions

Only the latest release gets fixes.
