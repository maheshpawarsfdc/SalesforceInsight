/**
 * @description Service class for querying Salesforce metadata efficiently
 * ENHANCED: Now includes Tooling API integration for real page layout detection
 * Includes caching to optimize performance and avoid governor limits
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 2.0 - Production Grade
 */
public with sharing class MetadataQueryService {
    
    // Cache maps to store describe results
    private static Map<String, Schema.SObjectType> globalDescribeCache;
    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache = 
        new Map<String, Map<String, Schema.SObjectField>>();
    private static Map<String, Schema.DescribeSObjectResult> objectDescribeCache = 
        new Map<String, Schema.DescribeSObjectResult>();
    
    // NEW: Layout and validation rule caches
    private static Map<String, LayoutMetadata> layoutCache = new Map<String, LayoutMetadata>();
    private static Map<String, List<ValidationRuleInfo>> validationRulesCache = 
        new Map<String, List<ValidationRuleInfo>>();
    
    // Cache expiration tracking
    private static Map<String, DateTime> cacheTimestamps = new Map<String, DateTime>();
    private static final Integer CACHE_DURATION_MINUTES = 60;
    
    /**
     * @description Wrapper class for layout metadata
     */
    public class LayoutMetadata {
        @AuraEnabled public String layoutName;
        @AuraEnabled public String objectName;
        @AuraEnabled public List<String> fields;
        @AuraEnabled public Map<String, LayoutSection> sections;
        @AuraEnabled public DateTime cachedAt;
        @AuraEnabled public String source; // 'tooling_api' or 'describe_fallback'
        
        public LayoutMetadata() {
            this.fields = new List<String>();
            this.sections = new Map<String, LayoutSection>();
            this.cachedAt = DateTime.now();
        }
    }
    
    public class LayoutSection {
        @AuraEnabled public String heading;
        @AuraEnabled public List<String> fields;
        
        public LayoutSection(String heading) {
            this.heading = heading;
            this.fields = new List<String>();
        }
    }
    
    /**
     * @description Wrapper class for validation rule information
     */
    public class ValidationRuleInfo {
        @AuraEnabled public String validationName;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public String errorDisplayField;
        @AuraEnabled public Boolean active;
        @AuraEnabled public String description;
        @AuraEnabled public String formula;
    }
    
    /**
     * @description Check if a field exists on a given object
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return Boolean indicating if field exists
     */
    public static Boolean checkFieldExists(String objectName, String fieldName) {
        try {
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                System.debug(LoggingLevel.WARN, 'Object name or field name is blank');
                return false;
            }
            
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap == null) {
                System.debug(LoggingLevel.WARN, 'Object does not exist: ' + objectName);
                return false;
            }
            
            Boolean exists = fieldMap.containsKey(fieldName.toLowerCase());
            System.debug('Field exists check: ' + objectName + '.' + fieldName + ' = ' + exists);
            
            return exists;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking field existence: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Check if an object exists in the org
     * @param objectName API name of the object
     * @return Boolean indicating if object exists
     */
    public static Boolean checkObjectExists(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return false;
            }
            
            Map<String, Schema.SObjectType> gd = getGlobalDescribe();
            Boolean exists = gd.containsKey(objectName.toLowerCase());
            
            System.debug('Object exists check: ' + objectName + ' = ' + exists);
            return exists;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking object existence: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get all fields on a page layout (REAL IMPLEMENTATION)
     * Uses Tooling API if available, falls back to describe-based guess
     * @param objectName API name of the object
     * @param recordTypeId Record Type ID (null for default layout)
     * @return List of field API names on the layout
     */
    public static List<String> getPageLayoutFields(String objectName, Id recordTypeId) {
        try {
            if (String.isBlank(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return new List<String>();
            }
            
            // Get layout name
            String layoutName = getLayoutNameForRecordType(objectName, recordTypeId);
            String cacheKey = objectName + '_' + (recordTypeId != null ? recordTypeId : 'default');
            
            // Check cache first
            if (isCacheValid(cacheKey) && layoutCache.containsKey(cacheKey)) {
                System.debug('Returning cached layout fields for: ' + cacheKey);
                return layoutCache.get(cacheKey).fields;
            }
            
            // Try Tooling API first (real layout data)
            LayoutMetadata layout = fetchLayoutViaToolingAPI(layoutName, objectName);
            
            if (layout != null && !layout.fields.isEmpty()) {
                layout.source = 'tooling_api';
                layoutCache.put(cacheKey, layout);
                cacheTimestamps.put(cacheKey, DateTime.now());
                System.debug('Fetched ' + layout.fields.size() + ' fields via Tooling API');
                return layout.fields;
            }
            
            // Fallback: Use describe-based guess
            System.debug('Tooling API failed, using describe fallback');
            layout = getLayoutFieldsViaDescribe(objectName);
            layout.source = 'describe_fallback';
            layoutCache.put(cacheKey, layout);
            cacheTimestamps.put(cacheKey, DateTime.now());
            
            return layout.fields;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting page layout fields: ' + e.getMessage());
            return new List<String>();
        }
    }
    
    /**
     * @description Check if a specific field is on a page layout
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @param recordTypeId Record Type ID (null for default)
     * @return Boolean indicating if field is on layout
     */
    public static Boolean isFieldOnPageLayout(String objectName, String fieldName, Id recordTypeId) {
        try {
            List<String> layoutFields = getPageLayoutFields(objectName, recordTypeId);
            
            // Case-insensitive search
            for (String layoutField : layoutFields) {
                if (layoutField.equalsIgnoreCase(fieldName)) {
                    System.debug('Field ' + fieldName + ' found on layout: YES');
                    return true;
                }
            }
            
            System.debug('Field ' + fieldName + ' found on layout: NO');
            return false;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking field on layout: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Fetch layout metadata via Tooling API
     * @param layoutName Name of the layout
     * @param objectName Object API name
     * @return LayoutMetadata or null if failed
     */
    @TestVisible
    private static LayoutMetadata fetchLayoutViaToolingAPI(String layoutName, String objectName) {
        try {
            // Build Tooling API query
            String query = 'SELECT Metadata FROM Layout WHERE Name = \'' + 
                          String.escapeSingleQuotes(layoutName) + '\'';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Salesforce_Tooling_API/query?q=' + 
                           EncodingUtil.urlEncode(query, 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) result.get('records');
                
                if (records != null && !records.isEmpty()) {
                    Map<String, Object> layout = (Map<String, Object>) records[0];
                    Map<String, Object> metadata = (Map<String, Object>) layout.get('Metadata');
                    
                    return parseLayoutMetadata(metadata, layoutName, objectName);
                }
            } else if (res.getStatusCode() == 401) {
                System.debug(LoggingLevel.ERROR, 'Tooling API authentication failed - check Named Credential');
            } else {
                System.debug(LoggingLevel.WARN, 'Tooling API returned: ' + res.getStatusCode());
            }
            
        } catch (CalloutException e) {
            System.debug(LoggingLevel.WARN, 'Tooling API callout failed: ' + e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error fetching layout via Tooling API: ' + e.getMessage());
        }
        
        return null;
    }
    
    /**
     * @description Parse layout metadata from Tooling API response
     * @param metadata Layout metadata JSON
     * @param layoutName Layout name
     * @param objectName Object name
     * @return LayoutMetadata wrapper
     */
    private static LayoutMetadata parseLayoutMetadata(
        Map<String, Object> metadata, 
        String layoutName, 
        String objectName
    ) {
        LayoutMetadata layout = new LayoutMetadata();
        layout.layoutName = layoutName;
        layout.objectName = objectName;
        
        try {
            Set<String> uniqueFields = new Set<String>();
            
            // Parse layout sections
            List<Object> layoutSections = (List<Object>) metadata.get('layoutSections');
            
            if (layoutSections != null) {
                for (Object sectionObj : layoutSections) {
                    Map<String, Object> section = (Map<String, Object>) sectionObj;
                    String sectionLabel = (String) section.get('label');
                    
                    LayoutSection layoutSection = new LayoutSection(sectionLabel);
                    
                    // Parse columns
                    List<Object> layoutColumns = (List<Object>) section.get('layoutColumns');
                    if (layoutColumns != null) {
                        for (Object columnObj : layoutColumns) {
                            Map<String, Object> column = (Map<String, Object>) columnObj;
                            List<Object> layoutItems = (List<Object>) column.get('layoutItems');
                            
                            if (layoutItems != null) {
                                for (Object itemObj : layoutItems) {
                                    Map<String, Object> item = (Map<String, Object>) itemObj;
                                    String field = (String) item.get('field');
                                    
                                    if (String.isNotBlank(field)) {
                                        uniqueFields.add(field);
                                        layoutSection.fields.add(field);
                                    }
                                }
                            }
                        }
                    }
                    
                    if (!layoutSection.fields.isEmpty()) {
                        layout.sections.put(sectionLabel, layoutSection);
                    }
                }
            }
            
            layout.fields = new List<String>(uniqueFields);
            System.debug('Parsed ' + layout.fields.size() + ' unique fields from layout');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error parsing layout metadata: ' + e.getMessage());
        }
        
        return layout;
    }
    
    /**
     * @description Fallback: Get layout fields via describe (educated guess)
     * @param objectName Object API name
     * @return LayoutMetadata with accessible fields
     */
    private static LayoutMetadata getLayoutFieldsViaDescribe(String objectName) {
        LayoutMetadata layout = new LayoutMetadata();
        layout.objectName = objectName;
        layout.layoutName = objectName + ' Layout (Describe Fallback)';
        
        try {
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap != null) {
                for (String fieldName : fieldMap.keySet()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    // Include fields that are:
                    // 1. Accessible (user can view)
                    // 2. Not calculated (formula fields often not on layouts)
                    // 3. Either updateable OR required (readonly required fields are on layouts)
                    if (fieldDescribe.isAccessible() && 
                        !fieldDescribe.isCalculated() &&
                        (fieldDescribe.isUpdateable() || !fieldDescribe.isNillable())) {
                        layout.fields.add(fieldDescribe.getName());
                    }
                }
            }
            
            System.debug('Describe fallback returned ' + layout.fields.size() + ' likely fields');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in describe fallback: ' + e.getMessage());
        }
        
        return layout;
    }
    
    /**
     * @description Get validation rules for an object via Tooling API
     * @param objectName API name of the object
     * @return List of ValidationRuleInfo wrappers
     */
    public static List<ValidationRuleInfo> getValidationRules(String objectName) {
        List<ValidationRuleInfo> rules = new List<ValidationRuleInfo>();
        
        try {
            if (String.isBlank(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return rules;
            }
            
            // Check cache first
            if (validationRulesCache.containsKey(objectName)) {
                System.debug('Returning cached validation rules for ' + objectName);
                return validationRulesCache.get(objectName);
            }
            
            // Check if object exists
            if (!checkObjectExists(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object does not exist: ' + objectName);
                return rules;
            }
            
            // Query validation rules using Tooling API
            String query = 'SELECT Id, ValidationName, ErrorMessage, ErrorDisplayField, Active, Description ' +
                          'FROM ValidationRule ' +
                          'WHERE EntityDefinition.QualifiedApiName = \'' + 
                          String.escapeSingleQuotes(objectName) + '\' ' +
                          'AND Active = true';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Salesforce_Tooling_API/query?q=' + 
                           EncodingUtil.urlEncode(query, 'UTF-8'));
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) result.get('records');
                
                if (records != null) {
                    for (Object recordObj : records) {
                        Map<String, Object> record = (Map<String, Object>) recordObj;
                        
                        ValidationRuleInfo rule = new ValidationRuleInfo();
                        rule.validationName = (String) record.get('ValidationName');
                        rule.errorMessage = (String) record.get('ErrorMessage');
                        rule.errorDisplayField = (String) record.get('ErrorDisplayField');
                        rule.active = (Boolean) record.get('Active');
                        rule.description = (String) record.get('Description');
                        
                        rules.add(rule);
                    }
                }
                
                System.debug('Found ' + rules.size() + ' active validation rules for ' + objectName);
                
                // Cache the results
                validationRulesCache.put(objectName, rules);
            } else {
                System.debug(LoggingLevel.WARN, 'Tooling API returned: ' + res.getStatusCode());
            }
            
        } catch (CalloutException e) {
            System.debug(LoggingLevel.WARN, 'Validation rules callout failed: ' + e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting validation rules: ' + e.getMessage());
        }
        
        return rules;
    }
    
    /**
     * @description Get layout name for a record type
     * @param objectName API name of the object
     * @param recordTypeId Record Type ID (null for default)
     * @return Layout name
     */
    private static String getLayoutNameForRecordType(String objectName, Id recordTypeId) {
        try {
            if (recordTypeId != null) {
                List<RecordType> rts = [
                    SELECT DeveloperName 
                    FROM RecordType 
                    WHERE Id = :recordTypeId 
                    LIMIT 1
                ];
                
                if (!rts.isEmpty()) {
                    return objectName + '-' + rts[0].DeveloperName + ' Layout';
                }
            }
            
            // Return default layout name
            return objectName + '-' + objectName + ' Layout';
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting layout name: ' + e.getMessage());
            return objectName + '-' + objectName + ' Layout';
        }
    }
    
    /**
     * @description Check if cache is still valid
     * @param cacheKey Cache key
     * @return Boolean indicating if cache is valid
     */
    private static Boolean isCacheValid(String cacheKey) {
        if (!cacheTimestamps.containsKey(cacheKey)) {
            return false;
        }
        
        DateTime cachedAt = cacheTimestamps.get(cacheKey);
        DateTime expiresAt = cachedAt.addMinutes(CACHE_DURATION_MINUTES);
        
        return DateTime.now() < expiresAt;
    }
    
    /**
     * @description Get field map for an object with caching
     * @param objectName API name of the object
     * @return Map of field API names to SObjectField tokens
     */
    public static Map<String, Schema.SObjectField> getFieldMap(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return null;
            }
            
            String objectKey = objectName.toLowerCase();
            
            // Check cache first
            if (fieldMapCache.containsKey(objectKey)) {
                return fieldMapCache.get(objectKey);
            }
            
            // Get from global describe
            Map<String, Schema.SObjectType> gd = getGlobalDescribe();
            Schema.SObjectType objectType = gd.get(objectKey);
            
            if (objectType == null) {
                System.debug(LoggingLevel.WARN, 'Object type not found: ' + objectName);
                return null;
            }
            
            // Get field map
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            
            // Cache the result
            fieldMapCache.put(objectKey, fieldMap);
            
            return fieldMap;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting field map: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Get object describe result with caching
     * @param objectName API name of the object
     * @return Schema.DescribeSObjectResult for the object
     */
    public static Schema.DescribeSObjectResult getObjectDescribe(String objectName) {
        try {
            if (String.isBlank(objectName)) {
                return null;
            }
            
            String objectKey = objectName.toLowerCase();
            
            if (objectDescribeCache.containsKey(objectKey)) {
                return objectDescribeCache.get(objectKey);
            }
            
            Map<String, Schema.SObjectType> gd = getGlobalDescribe();
            Schema.SObjectType objectType = gd.get(objectKey);
            
            if (objectType == null) {
                return null;
            }
            
            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            objectDescribeCache.put(objectKey, objectDescribe);
            
            return objectDescribe;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting object describe: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Get global describe with caching
     * @return Map of all SObject types in the org
     */
    private static Map<String, Schema.SObjectType> getGlobalDescribe() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }
    
    /**
     * @description Get field describe with caching
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return Schema.DescribeFieldResult for the field
     */
    public static Schema.DescribeFieldResult getFieldDescribe(String objectName, String fieldName) {
        try {
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                return null;
            }
            
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap == null) {
                return null;
            }
            
            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            
            if (field == null) {
                return null;
            }
            
            return field.getDescribe();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting field describe: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Check if a field is required (not nullable)
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return Boolean indicating if field is required
     */
    public static Boolean isFieldRequired(String objectName, String fieldName) {
        try {
            Schema.DescribeFieldResult fieldDescribe = getFieldDescribe(objectName, fieldName);
            
            if (fieldDescribe == null) {
                return false;
            }
            
            return !fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking if field is required: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get all required fields for an object
     * @param objectName API name of the object
     * @return List of required field API names
     */
    public static List<String> getRequiredFields(String objectName) {
        List<String> requiredFields = new List<String>();
        
        try {
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap != null) {
                for (String fieldName : fieldMap.keySet()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    if (!fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate()) {
                        requiredFields.add(fieldDescribe.getName());
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting required fields: ' + e.getMessage());
        }
        
        return requiredFields;
    }
    
    /**
     * @description Clear all caches
     */
    @TestVisible
    public static void clearCache() {
        globalDescribeCache = null;
        fieldMapCache.clear();
        objectDescribeCache.clear();
        validationRulesCache.clear();
        layoutCache.clear();
        cacheTimestamps.clear();
        System.debug('All metadata caches cleared');
    }
    
    /**
     * @description Get cache statistics for monitoring
     * @return Map with cache size information
     */
    public static Map<String, Integer> getCacheStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        
        stats.put('globalDescribeLoaded', globalDescribeCache != null ? 1 : 0);
        stats.put('fieldMapsCached', fieldMapCache.size());
        stats.put('objectDescribesCached', objectDescribeCache.size());
        stats.put('validationRulesCached', validationRulesCache.size());
        stats.put('layoutsCached', layoutCache.size());
        
        return stats;
    }
}