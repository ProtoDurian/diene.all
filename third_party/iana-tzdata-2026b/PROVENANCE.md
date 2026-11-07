# IANA time zone database, release 2026b

`tzdata2026b.tar.gz` is the official IANA data archive, stored unmodified.

- URL: <https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz>
- SHA-256: `114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544`

`packages/diene_core_utils/tool/gen_iana_zones.dart` builds
`lib/src/iana_zones.dart` from it: every `Zone` and `Link` name in `africa`,
`antarctica`, `asia`, `australasia`, `europe`, `northamerica`, `southamerica`,
`etcetera`, `factory` and `backward` (598 names). `backzone` is left out: it
only adds pre-1970 history to zones that already exist. The conformance test
checks the archive digest and that the committed list matches it.

The data is public domain (see `LICENSE` inside the archive). The archive is
outside the package, so it never ships to pub.dev.
