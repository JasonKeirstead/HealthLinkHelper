/// GraphQL operation documents, captured verbatim from the EBB web app / bundle.
///
/// Read queries were observed on the wire; mutations were extracted from
/// `main.dart.js`. Bootstrap queries (`getAccountsIds`, `getProfile`) select a
/// trimmed subset of the app's fields — only what the scanner needs.
class Ops {
  Ops._();

  // ---- Bootstrap: patient chart discovery ----

  /// The user's own charts, each with its account. This is how the app resolves
  /// (accountId, chartId) — via `currentUser.charts.nodes`, NOT family.dependents
  /// (a solo account with no dependents still has its own chart here).
  static const String connectedCharts = r'''
query connectedCharts {
  currentUser {
    charts {
      nodes {
        id
        patientArchived
        account { id name }
        profile { firstName lastName fullName }
      }
    }
  }
}''';

  // ---- Booking flow (read) ----

  static const String getLocations = r'''
query getLocations($chartId: ID!, $bookingType: BookingType!, $name: SearchString, $groupLabel: BookingLocationGroupLabel, $pagination: Pagination, $dependentChartId: ID) {
  currentUser {
    chart(id: $chartId) {
      booking(filters: {bookingType: $bookingType, dependentChartId: $dependentChartId}) {
        locations(filters: {name: $name, groupLabel: $groupLabel}, pagination: $pagination) {
          edges {
            node {
              id name city latitude longitude country postalCode
              streetAddress1 streetAddress2 province timezone
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
}''';

  static const String getPresentingIssues = r'''
query getPresentingIssues($chartId: ID!, $bookingType: BookingType!, $locationId: ID!, $name: SearchString, $dependentChartId: ID) {
  currentUser {
    chart(id: $chartId) {
      booking(filters: {bookingType: $bookingType, dependentChartId: $dependentChartId}) {
        presentingIssues(filters: {locationId: $locationId, name: $name}) {
          edges { node { id name } }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
}''';

  static const String getTypes = r'''
query getTypes($chartId: ID!, $locationId: ID!, $presentingIssueId: ID, $bookingType: BookingType!, $dependentChartId: ID) {
  currentUser {
    chart(id: $chartId) {
      booking(filters: {bookingType: $bookingType, dependentChartId: $dependentChartId}) {
        services(filters: {locationId: $locationId, presentingIssueId: $presentingIssueId}) {
          edges { node { id name } }
        }
      }
    }
  }
}''';

  static const String getAvailableDays = r'''
query getAvailableDays($chartId: ID!, $bookingType: BookingType!, $locationId: ID!, $providerId: ID, $serviceId: ID!, $from: DateTimeWithTimezone!, $until: DateTimeWithTimezone!, $dependentChartId: ID) {
  currentUser {
    chart(id: $chartId) {
      booking(filters: {bookingType: $bookingType, dependentChartId: $dependentChartId}) {
        availableDays(filters: {locationId: $locationId, providerUserId: $providerId, serviceId: $serviceId, from: $from, until: $until})
      }
    }
  }
}''';

  static const String getTimeSlots = r'''
query getTimeSlots($chartId: ID!, $bookingType: BookingType!, $locationId: ID!, $providerId: ID, $serviceId: ID!, $date: DateTimeWithTimezone!, $dependentChartId: ID) {
  currentUser {
    chart(id: $chartId) {
      booking(filters: {bookingType: $bookingType, dependentChartId: $dependentChartId}) {
        timeSlots(filters: {locationId: $locationId, providerUserId: $providerId, serviceId: $serviceId, date: $date}) {
          from
          until
          providerUser { id }
        }
      }
    }
  }
}''';

  // ---- Booking flow (write) — call ONLY on explicit user confirmation ----

  static const String createAppointment = r'''
mutation createAppointment($chartId: ID!, $groupVisitId: ID, $locationId: ID!, $presentingIssueCustom: String, $presentingIssueId: ID, $practitionerId: ID, $serviceId: ID, $from: DateTimeWithTimezone!, $until: DateTimeWithTimezone!, $visitType: VisitType!, $paymentId: ID) {
  appointment {
    createAppointment(input: {chartId: $chartId, groupVisitId: $groupVisitId, locationId: $locationId, presentingIssueCustom: $presentingIssueCustom, presentingIssueId: $presentingIssueId, providerUserId: $practitionerId, serviceId: $serviceId, startAt: $from, untilAt: $until, visitType: $visitType, paymentId: $paymentId}) {
      appointment { id allowToSkipQnaire questionnaires { id } }
    }
  }
}''';

  static const String cancelAppointment = r'''
mutation cancelAppointment($appointmentId: ID!, $clientMutationId: String, $dependentChartId: ID) {
  appointment {
    cancelAppointment(input: {appointmentId: $appointmentId, clientMutationId: $clientMutationId, dependentChartId: $dependentChartId}) {
      appointment { id }
      clientMutationId
    }
  }
}''';
}
