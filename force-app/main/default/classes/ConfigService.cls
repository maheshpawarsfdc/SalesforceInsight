public with sharing class ConfigService {

    // Static cache
    private static Diagnostic_Config__mdt cachedConfig;

    /**
     * Load configuration once per transaction
     */
    private static Diagnostic_Config__mdt getConfig() {
        if (cachedConfig == null) {
            cachedConfig = Diagnostic_Config__mdt.getInstance('Default');

            // Fallback safety
            if (cachedConfig == null) {
                throw new AuraHandledException(
                    'Diagnostic configuration record not found'
                );
            }
        }
        return cachedConfig;
    }

    // --------- Public Getters ---------

    public static Integer getCacheRefreshHours() {
        return Integer.valueOf(getConfig().Cache_Refresh_Hours__c);
    }

    public static Integer getMaxAuditTrailDays() {
        return Integer.valueOf(getConfig().Max_Audit_Trail_Days__c);
    }

    public static Boolean isTriggerAnalysisEnabled() {
        return getConfig().Enable_Trigger_Analysis__c;
    }

    public static Boolean isFlowAnalysisEnabled() {
        return getConfig().Enable_Flow_Analysis__c;
    }

    public static Integer getMaxResultsDisplay() {
        return Integer.valueOf(getConfig().Max_Results_Display__c);
    }

    public static Integer getApiTimeoutSeconds() {
        return Integer.valueOf(getConfig().API_Timeout_Seconds__c);
    }

    public static Boolean isDebugLoggingEnabled() {
        return getConfig().Enable_Debug_Logging__c;
    }
}