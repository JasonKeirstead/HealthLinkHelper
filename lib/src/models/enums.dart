/// `BookingType` — the modality filter used by list/availability queries.
enum BookingType {
  physical('PHYSICAL'),
  virtual('VIRTUAL'),
  nonGroup('NON_GROUP'),
  group('GROUP');

  const BookingType(this.wire);
  final String wire;
}

/// `VisitType` — the modality on the createAppointment input (distinct enum).
enum VisitType {
  inPerson('IN_PERSON'),
  virtual('VIRTUAL'),
  phone('PHONE');

  const VisitType(this.wire);
  final String wire;
}

/// User-facing modality choice, mapped to the two backend enums.
///
/// Listing/availability queries take a [BookingType]; the create mutation
/// takes a [VisitType]. Locations & presenting issues are always listed with
/// [BookingType.nonGroup]; services/days/slots use [bookingType].
enum Modality {
  inPerson('In-person', BookingType.physical, VisitType.inPerson),
  virtual('Virtual', BookingType.virtual, VisitType.virtual);

  const Modality(this.label, this.bookingType, this.visitType);
  final String label;
  final BookingType bookingType;

  /// Default visit type for the create mutation. For a "TELEPHONE-" service
  /// under the virtual modality, callers should override to [VisitType.phone].
  final VisitType visitType;
}
