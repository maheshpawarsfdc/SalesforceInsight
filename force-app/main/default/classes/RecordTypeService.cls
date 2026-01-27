/**
 * @description Service for handling Record Type detection and layout mapping
 * Determines which page layout a user sees based on their record type assignments
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class RecordTypeService {
    
    // Cache for record type assignments
    private static Map<String, List<RecordTypeInfo>> recordTypeCache = 
        new Map<String, List<RecordTypeInfo>>();
    
    /**
     * @description Record Type information wrapper
     */
    public class RecordTypeInfo {
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String developerName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean isDefault;
        @AuraEnabled public Boolean isAvailable;
        @AuraEnabled public String pageLayoutName;
    }
    
    /**
     * @description Layout assignment result
     */
    public class LayoutAssignment {
        @AuraEnabled public String objectName;
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String layoutName;
        @AuraEnabled public Boolean hasMultipleLayouts;
        @AuraEnabled public List<String> availableRecordTypes;
        
        public LayoutAssignment() {
            this.availableRecordTypes = new List<String>();
        }
    }
    
    /**
     * @description Get user's default record type for an object
     * @param objectName Object API name
     * @param userId User ID
     * @return Record Type ID or null if no record types
     */
    public static Id getUserDefaultRecordType(String objectName, Id userId) {
        try {
            // Check if object has record types
            Schema.DescribeSObjectResult objectDescribe = 
                Schema.getGlobalDescribe().get(objectName).getDescribe();
            
            // Get record type map - if empty, no record types exist
            Map<String, Schema.RecordTypeInfo> recordTypeMap = 
                objectDescribe.getRecordTypeInfosByDeveloperName();
            
            if (recordTypeMap.isEmpty()) {
                System.debug('Object ' + objectName + ' does not have record types');
                return null;
            }
            
            // Find default record type for user
            for (Schema.RecordTypeInfo rti : recordTypeMap.values()) {
                if (rti.isDefaultRecordTypeMapping()) {
                    System.debug('Default record type for ' + objectName + ': ' + rti.getName());
                    return rti.getRecordTypeId();
                }
            }
            
            // If no default, return first available
            for (Schema.RecordTypeInfo rti : recordTypeMap.values()) {
                if (rti.isAvailable()) {
                    System.debug('First available record type for ' + objectName + ': ' + rti.getName());
                    return rti.getRecordTypeId();
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting default record type: ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * @description Get all available record types for user on an object
     * @param objectName Object API name
     * @param userId User ID
     * @return List of available record types
     */
    public static List<RecordTypeInfo> getAvailableRecordTypes(String objectName, Id userId) {
        try {
            // Check cache
            String cacheKey = objectName + '_' + userId;
            if (recordTypeCache.containsKey(cacheKey)) {
                return recordTypeCache.get(cacheKey);
            }
            
            List<RecordTypeInfo> recordTypes = new List<RecordTypeInfo>();
            
            // Get object describe
            Schema.DescribeSObjectResult objectDescribe = 
                Schema.getGlobalDescribe().get(objectName).getDescribe();
            
            // Get record type map - if empty, no record types
            Map<String, Schema.RecordTypeInfo> recordTypeMap = 
                objectDescribe.getRecordTypeInfosByDeveloperName();
            
            if (recordTypeMap.isEmpty()) {
                return recordTypes;
            }
            
            for (Schema.RecordTypeInfo rti : recordTypeMap.values()) {
                // Skip Master record type
                if (rti.isMaster()) {
                    continue;
                }
                
                RecordTypeInfo info = new RecordTypeInfo();
                info.recordTypeId = rti.getRecordTypeId();
                info.recordTypeName = rti.getName();
                info.developerName = rti.getDeveloperName();
                info.isActive = rti.isActive();
                info.isDefault = rti.isDefaultRecordTypeMapping();
                info.isAvailable = rti.isAvailable();
                
                // Get layout name for this record type
                info.pageLayoutName = getLayoutNameForRecordType(objectName, info.recordTypeId);
                
                recordTypes.add(info);
            }
            
            // Cache the results
            recordTypeCache.put(cacheKey, recordTypes);
            
            System.debug('Found ' + recordTypes.size() + ' record types for ' + objectName);
            
            return recordTypes;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting available record types: ' + e.getMessage());
            return new List<RecordTypeInfo>();
        }
    }
    
    /**
     * @description Determine which layout a user will see
     * @param objectName Object API name
     * @param recordId Specific record ID (optional - for existing records)
     * @param userId User ID
     * @return LayoutAssignment with layout details
     */
    public static LayoutAssignment determineUserLayout(String objectName, Id recordId, Id userId) {
        LayoutAssignment assignment = new LayoutAssignment();
        assignment.objectName = objectName;
        
        try {
            Id recordTypeId = null;
            
            // If specific record provided, get its record type
            if (recordId != null) {
                recordTypeId = getRecordRecordType(recordId);
                assignment.recordTypeId = recordTypeId;
            }
            
            // If no record type yet, get user's default
            if (recordTypeId == null) {
                recordTypeId = getUserDefaultRecordType(objectName, userId);
                assignment.recordTypeId = recordTypeId;
            }
            
            // Get all available record types
            List<RecordTypeInfo> availableRTs = getAvailableRecordTypes(objectName, userId);
            assignment.hasMultipleLayouts = availableRTs.size() > 1;
            
            for (RecordTypeInfo rt : availableRTs) {
                assignment.availableRecordTypes.add(rt.recordTypeName);
                
                if (rt.recordTypeId == recordTypeId) {
                    assignment.recordTypeName = rt.recordTypeName;
                    assignment.layoutName = rt.pageLayoutName;
                }
            }
            
            // If no record type, use default layout
            if (String.isBlank(assignment.layoutName)) {
                assignment.layoutName = objectName + '-' + objectName + ' Layout';
            }
            
            System.debug('User layout: ' + assignment.layoutName + 
                        ' (Record Type: ' + assignment.recordTypeName + ')');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error determining user layout: ' + e.getMessage());
            assignment.layoutName = objectName + '-' + objectName + ' Layout'; // Fallback
        }
        
        return assignment;
    }
    
    /**
     * @description Get record type of a specific record
     * @param recordId Record ID
     * @return Record Type ID or null
     */
    private static Id getRecordRecordType(Id recordId) {
        try {
            String objectName = recordId.getSObjectType().getDescribe().getName();
            
            // Dynamic SOQL to get RecordTypeId
            String query = 'SELECT RecordTypeId FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.query(query);
            
            if (!records.isEmpty()) {
                Id rtId = (Id) records[0].get('RecordTypeId');
                System.debug('Record ' + recordId + ' has RecordTypeId: ' + rtId);
                return rtId;
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting record type: ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * @description Get layout name for a record type
     * @param objectName Object API name
     * @param recordTypeId Record Type ID
     * @return Layout name
     */
    private static String getLayoutNameForRecordType(String objectName, Id recordTypeId) {
        try {
            if (recordTypeId == null) {
                return objectName + '-' + objectName + ' Layout';
            }
            
            // Query RecordType to get DeveloperName
            List<RecordType> recordTypes = [
                SELECT DeveloperName 
                FROM RecordType 
                WHERE Id = :recordTypeId 
                LIMIT 1
            ];
            
            if (!recordTypes.isEmpty()) {
                String layoutName = objectName + '-' + recordTypes[0].DeveloperName + ' Layout';
                System.debug('Layout for Record Type: ' + layoutName);
                return layoutName;
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting layout name: ' + e.getMessage());
        }
        
        // Default layout
        return objectName + '-' + objectName + ' Layout';
    }
    
    /**
     * @description Check if field is on the layout for user's record type
     * @param objectName Object API name
     * @param fieldName Field API name
     * @param recordId Specific record (optional)
     * @param userId User ID
     * @return Boolean indicating if field is on user's layout
     */
    public static Boolean isFieldOnUserLayout(
        String objectName, 
        String fieldName, 
        Id recordId, 
        Id userId
    ) {
        try {
            // Determine which layout the user sees
            LayoutAssignment assignment = determineUserLayout(objectName, recordId, userId);
            
            // Get fields on that specific layout
            List<String> layoutFields = MetadataQueryService.getPageLayoutFields(
                objectName, 
                assignment.recordTypeId
            );
            
            // Case-insensitive search
            for (String layoutField : layoutFields) {
                if (layoutField.equalsIgnoreCase(fieldName)) {
                    return true;
                }
            }
            
            return false;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking field on user layout: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get diagnostic info about record type assignment
     * @param objectName Object API name
     * @param userId User ID
     * @return Human-readable diagnostic message
     */
    public static String getDiagnosticInfo(String objectName, Id userId) {
        try {
            List<RecordTypeInfo> recordTypes = getAvailableRecordTypes(objectName, userId);
            
            if (recordTypes.isEmpty()) {
                return objectName + ' does not use record types - all users see the same layout';
            }
            
            StringBuilder info = new StringBuilder();
            info.append(objectName + ' has ' + recordTypes.size() + ' record type(s) available:\n');
            
            for (RecordTypeInfo rt : recordTypes) {
                info.append('  • ' + rt.recordTypeName);
                if (rt.isDefault) {
                    info.append(' (Default)');
                }
                info.append(' → Layout: ' + rt.pageLayoutName + '\n');
            }
            
            return info.toString();
            
        } catch (Exception e) {
            return 'Error getting record type info: ' + e.getMessage();
        }
    }
    
    /**
     * @description Helper class for StringBuilder
     */
    private class StringBuilder {
        private List<String> parts = new List<String>();
        
        public void append(String text) {
            parts.add(text);
        }
        
        public override String toString() {
            return String.join(parts, '');
        }
    }
    
    /**
     * @description Clear cache
     */
    @TestVisible
    private static void clearCache() {
        recordTypeCache.clear();
    }
}