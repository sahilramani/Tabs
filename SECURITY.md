# Security policy

## Supported versions

Tabs is pre-1.0 alpha software. Only the latest release (and `main`) receives
fixes.

## Reporting a vulnerability

Tabs runs entirely on-device: it has no networking layer, no server component,
and no accounts. The realistic attack surface is what the app parses — OCR text
from screenshots and text extracted from PDF statements — and what it stores
locally via SwiftData.

If you find a vulnerability (e.g. a crafted PDF or image that crashes the
parser or corrupts the store, or any way the app could leak statement data off
the device), please report it privately via
[GitHub's private vulnerability reporting](https://github.com/sahilramani/Tabs/security/advisories/new)
rather than a public issue.

You should get an acknowledgement within a week. Please include reproduction
steps and, if the report involves a statement file, a synthetic file — never a
real bank statement.
