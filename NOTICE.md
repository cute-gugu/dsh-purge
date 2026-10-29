# Attribution

dsh-purge is an independently maintained fork of **dsh-purge**, original author **小杨 / YuJunZhiXue**:
https://github.com/YuJunZhiXue/dsh-purge

Version 2.0.0 additionally merges **dsh-unrestricted 0.2.4**, upstream
https://github.com/yexi-by/dsh-unrestricted (MIT). From that project this fork keeps only
the runtime assembly-fingerprint idea (`lib/attest.js`) and the status/preview endpoint shape.
Its prompt-fusion chain was not carried over: it anchors on verbatim upstream prompt strings that
this plugin's host patches #4 / #25 / #26 intentionally remove, so the two are mutually exclusive
by design. Original MIT terms apply to the retained material.

Original copyright and MIT license remain in LICENSE. The repository preserves upstream history and source attribution. Upstream README text is retained under docs/upstream. This fork is free and not offered for paid resale; it is not endorsed by or an official release of the upstream authors.

The native settings UI was derived from the original 1.1.71 client and subsequently separated and integrated into this community distribution. Existing third-party notices under docs/redteam-upstream-LICENSE and docs/redteam-upstream-DISCLOSURE remain applicable to their respective material.

Community contributors and their contributions are recorded in [CONTRIBUTORS.md](CONTRIBUTORS.md).
