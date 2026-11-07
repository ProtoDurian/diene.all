/// Identity of the shared contract release a package checks itself against.
final class C0ConfigProvenance {
  const C0ConfigProvenance({
    required this.releaseId,
    required this.contractVersion,
    required this.releaseDigest,
    required this.sourceCase,
    required this.c0Sections,
  });

  final String releaseId;

  final int contractVersion;

  final String releaseDigest;

  /// Repository-relative path of the case file.
  final String sourceCase;

  final List<String> c0Sections;
}

/// The shared config contract `diene_config` checks itself against.
final class C0ConfigContract {
  const C0ConfigContract({
    required this.provenance,
    required this.projectedCases,
  });

  final C0ConfigProvenance provenance;

  /// The case names this package checks.
  final List<String> projectedCases;
}

const C0ConfigContract c0ConfigContract = C0ConfigContract(
  provenance: C0ConfigProvenance(
    releaseId: 'c0-fixtures-r2',
    contractVersion: 2,
    releaseDigest:
        '0e64439c681a22fb4f02285c082ed8ffb7b465e732fde4e49757e9e3c9a5783e',
    sourceCase: 'contracts/c0/cases/config.json',
    c0Sections: <String>['Config precedence'],
  ),
  projectedCases: <String>[
    'blankIsUnset',
    'caseInsensitiveKeyMatching',
    'finalLayerValidation',
    'layeringAndIndexedList',
    'noJsonNoComma',
  ],
);
