class DrivingLicenseData {
  final String fullName;
  final String dateOfBirth;
  final String address;
  final String nationality;
  final String issuingAuthority;
  final List<String> licenseClasses;
  final List<String> restrictions;
  final String issueDate;
  final String expiryDate;

  const DrivingLicenseData({
    required this.fullName,
    required this.dateOfBirth,
    required this.address,
    required this.nationality,
    required this.issuingAuthority,
    required this.licenseClasses,
    required this.restrictions,
    required this.issueDate,
    required this.expiryDate,
  });

  factory DrivingLicenseData.fromJson(Map<String, dynamic> json) {
    return DrivingLicenseData(
      fullName: json['fullName'] as String? ?? '',
      dateOfBirth: json['dateOfBirth'] as String? ?? '',
      address: json['address'] as String? ?? '',
      nationality: json['nationality'] as String? ?? '',
      issuingAuthority: json['issuingAuthority'] as String? ?? '',
      licenseClasses:
          (json['licenseClasses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      restrictions:
          (json['restrictions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      issueDate: json['issueDate'] as String? ?? '',
      expiryDate: json['expiryDate'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'fullName': fullName,
    'dateOfBirth': dateOfBirth,
    'address': address,
    'nationality': nationality,
    'issuingAuthority': issuingAuthority,
    'licenseClasses': licenseClasses,
    'restrictions': restrictions,
    'issueDate': issueDate,
    'expiryDate': expiryDate,
  };
}

class DocumentSummary {
  final String id;
  final String type;
  final String documentNumber;
  final String status;
  final String? issuedAt;
  final String? expiresAt;
  final bool isStoredOffline;

  const DocumentSummary({
    required this.id,
    required this.type,
    required this.documentNumber,
    required this.status,
    this.issuedAt,
    this.expiresAt,
    this.isStoredOffline = false,
  });

  factory DocumentSummary.fromJson(
    Map<String, dynamic> json, {
    bool isStoredOffline = false,
  }) {
    return DocumentSummary(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'driving_license',
      documentNumber: json['documentNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'issued',
      issuedAt: json['issuedAt'] as String?,
      expiresAt: json['expiresAt'] as String?,
      isStoredOffline: isStoredOffline,
    );
  }

  DocumentSummary copyWith({bool? isStoredOffline, String? status}) {
    return DocumentSummary(
      id: id,
      type: type,
      documentNumber: documentNumber,
      status: status ?? this.status,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      isStoredOffline: isStoredOffline ?? this.isStoredOffline,
    );
  }
}

class DrivingLicenseDocument {
  final String id;
  final String type;
  final String documentNumber;
  final String? issuedAt;
  final String? expiresAt;
  final DrivingLicenseData data;

  const DrivingLicenseDocument({
    required this.id,
    required this.type,
    required this.documentNumber,
    this.issuedAt,
    this.expiresAt,
    required this.data,
  });

  factory DrivingLicenseDocument.fromJson(Map<String, dynamic> json) {
    return DrivingLicenseDocument(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'driving_license',
      documentNumber: json['documentNumber'] as String? ?? '',
      issuedAt: json['issuedAt'] as String?,
      expiresAt: json['expiresAt'] as String?,
      data: DrivingLicenseData.fromJson(
        (json['data'] as Map<String, dynamic>?) ?? {},
      ),
    );
  }
}
