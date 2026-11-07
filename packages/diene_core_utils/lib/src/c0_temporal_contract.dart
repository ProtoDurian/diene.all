final class C0TemporalProvenance {
  const C0TemporalProvenance({
    required this.contractVersion,
    required this.c0Section,
    required this.c0Source,
    required this.ianaRelease,
    required this.ianaArchiveUrl,
    required this.ianaArchiveSha256,
    required this.contentSha256,
  });

  final String contractVersion;
  final String c0Section;
  final String c0Source;
  final String ianaRelease;
  final String ianaArchiveUrl;
  final String ianaArchiveSha256;

  /// SHA-256 of [C0TemporalContract.digestPayload]; update it with the vectors.
  final String contentSha256;
}

/// [input] in any RFC 3339 form formats to the UTC `Z` form [canonicalUtc].
final class C0InstantVector {
  const C0InstantVector({required this.input, required this.canonicalUtc});

  final String input;
  final String canonicalUtc;
}

final class C0Cases {
  const C0Cases({required this.valid, required this.invalid});

  final List<String> valid;
  final List<String> invalid;
}

final class C0TemporalContract {
  const C0TemporalContract({
    required this.provenance,
    required this.dates,
    required this.times,
    required this.durations,
    required this.timezones,
    required this.instants,
    required this.invalidInstants,
  });

  final C0TemporalProvenance provenance;
  final C0Cases dates;
  final C0Cases times;
  final C0Cases durations;
  final C0Cases timezones;
  final List<C0InstantVector> instants;

  /// Instants the strict UTC parser must reject.
  final List<String> invalidInstants;

  /// Fixed-order text of every vector, hashed into `contentSha256`.
  String digestPayload() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('contract=${provenance.contractVersion}')
      ..writeln('c0=${provenance.c0Section}|${provenance.c0Source}')
      ..writeln(
        'iana=${provenance.ianaRelease}|${provenance.ianaArchiveSha256}',
      )
      ..writeln('dates.valid=${dates.valid.join(",")}')
      ..writeln('dates.invalid=${dates.invalid.join(",")}')
      ..writeln('times.valid=${times.valid.join(",")}')
      ..writeln('times.invalid=${times.invalid.join(",")}')
      ..writeln('durations.valid=${durations.valid.join(",")}')
      ..writeln('durations.invalid=${durations.invalid.join(",")}')
      ..writeln('timezones.valid=${timezones.valid.join(",")}')
      ..writeln('timezones.invalid=${timezones.invalid.join(",")}')
      ..writeln(
        'instants=${instants.map((C0InstantVector v) => "${v.input}>${v.canonicalUtc}").join(",")}',
      )
      ..writeln('invalidInstants=${invalidInstants.join(",")}');
    return buffer.toString();
  }
}

/// The temporal vectors every Diene Dart package checks its own surface with.
const C0TemporalContract c0TemporalContract = C0TemporalContract(
  provenance: C0TemporalProvenance(
    contractVersion: '1',
    c0Section: 'Serialization',
    c0Source: 'C0 contracts',
    ianaRelease: '2026b',
    ianaArchiveUrl:
        'https://data.iana.org/time-zones/releases/tzdata2026b.tar.gz',
    ianaArchiveSha256:
        '114543d9f19a6bfeb5bca43686aea173d38755a3db1f2eec112647ae92c6f544',
    contentSha256:
        'b067fe7f7783ddd63bd0f460292b3b5be87a606a08b95b4bae5519bda3cb4608',
  ),
  dates: C0Cases(
    valid: <String>['2026-07-21', '2000-02-29', '0001-01-01', '9999-12-31'],
    invalid: <String>[
      '21-07-2026',
      '2026-02-30',
      '2026-13-01',
      '2026-7-1',
      '2026/07/21',
    ],
  ),
  times: C0Cases(
    valid: <String>['00:00:00', '01:02:03', '23:59:59'],
    invalid: <String>['24:00:00', '01:60:00', '01:02:60', '1:02:03', '01:02'],
  ),
  durations: C0Cases(
    valid: <String>['P1DT2H3M4.5S', 'PT0.5S', 'P1Y2M3DT4H5M6S', 'P1W'],
    invalid: <String>['10 minutes', 'P', 'PT', '1DT2H', 'P1H'],
  ),
  timezones: C0Cases(
    valid: <String>[
      'Asia/Singapore',
      'America/Argentina/Buenos_Aires',
      'Etc/UTC',
      'UTC',
      'US/Eastern',
      'EST',
      'GMT',
    ],
    invalid: <String>[
      'Area/NotAnIanaZone',
      '+08:00',
      'asia/singapore',
      'Area/../Location',
      'PST',
      '',
    ],
  ),
  instants: <C0InstantVector>[
    C0InstantVector(
      input: '2026-07-21T09:02:03+08:00',
      canonicalUtc: '2026-07-21T01:02:03.000Z',
    ),
    C0InstantVector(
      input: '2026-07-21T01:02:03Z',
      canonicalUtc: '2026-07-21T01:02:03.000Z',
    ),
    C0InstantVector(
      input: '2026-07-21T01:02:03.456Z',
      canonicalUtc: '2026-07-21T01:02:03.456Z',
    ),
  ],
  invalidInstants: <String>[
    '2026-07-21T01:02:03+00:00',
    '2026-07-21T01:02:03+08:00',
    '2026-07-21T01:02:03',
    '2026-02-30T01:02:03Z',
    '2026-07-21 01:02:03Z',
  ],
);
