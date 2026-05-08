class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://utypxmgyfqfwlkpkqrff.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV0eXB4bWd5ZnFmd2xrcGtxcmZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTAyNDAxMTAsImV4cCI6MjA2NTgxNjExMH0.tkNF11cJ06ZNt0dykFgu1smGEDWuT0Q4LtAmRL6wNZU';

  static String fn(String name) => '$url/functions/v1/$name';

  static String get sendTripToDriverFn => fn('send_trip_to_driver');
  static String get assignQuickTripFn => fn('assign_quick_trip');
  static String get getDriversFn => fn('get-drivers');
  static String get getPassedServicesFn => fn('get-passed-services');
  static String get addDriverFn => fn('add-driver');
  static String get modifierFareFn => fn('modifier-fare');

  // TODO(security): move Directions calls behind an Edge Function so this key
  // is not embedded in the client. Restrict the key to your bundle id in GCP.
  static const String googleMapsApiKey =
      'AIzaSyA98tXlKLb3JRZWUv8tFZMeNCQ55VBINaI';
}
