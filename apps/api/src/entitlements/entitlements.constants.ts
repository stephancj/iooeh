export const FEATURE_CODES = {
  LIVE_TRACKING: 'live_tracking',
  FLEET_OVERVIEW: 'fleet_overview',
  VEHICLE_TELEMETRY: 'vehicle_telemetry',
  HISTORY: 'history',
  HISTORY_RETENTION_DAYS: 'history_retention_days',
  TRIP_ANALYSIS: 'trip_analysis',
  MAX_GEOFENCES: 'max_geofences',
  GEOFENCE_ALERTS: 'geofence_alerts',
  LOW_BATTERY_ALERTS: 'low_battery_alerts',
  SPEED_ALERTS: 'speed_alerts',
  SLEEP_MODE: 'sleep_mode',
  PUSH_NOTIFICATIONS: 'push_notifications',
  WHATSAPP_NOTIFICATIONS: 'whatsapp_notifications',
  ACTIVITY_REPORTS: 'activity_reports',
  TRIP_REPORTS: 'trip_reports',
  SPEED_REPORTS: 'speed_reports',
  IDLE_REPORTS: 'idle_reports',
  GEOFENCE_REPORTS: 'geofence_reports',
} as const;

export type FeatureCode = (typeof FEATURE_CODES)[keyof typeof FEATURE_CODES];
