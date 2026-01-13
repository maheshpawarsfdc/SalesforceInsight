/**
 * @description Service class for querying Salesforce metadata efficiently
 * Includes caching to optimize performance and avoid governor limits
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class MetadataQueryService {
    
    // Cache maps to store describe results
    private static Map<String, Schema.SObjectType> globalDescribeCache;
    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache = 
        new Map<String, Map<String, Schema.SObjectField>>();
    private static Map<String, Schema.DescribeSObjectResult> objectDescribeCache = 
        new Map<String, Schema.DescribeSObjectResult>();
    private static Map<String, List<ValidationRuleInfo>> validationRulesCache = 
        new Map<String, List<ValidationRuleInfo>>();
    
    /**
     * @description Wrapper class for validation rule information
     */
    public class ValidationRuleInfo {
        public String validationName;
        public String errorMessage;
        public String errorDisplayField;
        public Boolean active;
        public String description;
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
     * @description Get all fields on a page layout
     * Note: This is a simplified version - full page layout metadata requires Metadata API
     * Returns all fields accessible on the object as a proxy
     * @param objectName API name of the object
     * @param layoutName Name of the page layout (currently not used - returns all fields)
     * @return List of field API names
     */
    public static List<String> getPageLayoutFields(String objectName, String layoutName) {
        List<String> fieldNames = new List<String>();
        
        try {
            if (String.isBlank(objectName)) {
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return fieldNames;
            }
            
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap == null) {
                System.debug(LoggingLevel.WARN, 'Object does not exist: ' + objectName);
                return fieldNames;
            }
            
            // Get all field names
            // Note: In a full implementation, you would use Metadata API to get actual layout fields
            // This returns all fields as a simplified version
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Only include accessible fields (user can view)
                if (fieldDescribe.isAccessible()) {
                    fieldNames.add(fieldDescribe.getName());
                }
            }
            
            System.debug('Found ' + fieldNames.size() + ' accessible fields on ' + objectName);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting page layout fields: ' + e.getMessage());
        }
        
        return fieldNames;
    }
    
    /**
     * @description Get validation rules for an object
     * Note: This requires querying ValidationRule metadata - simplified version returns empty list
     * Full implementation would use Tooling API or Metadata API
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
            // Note: This requires a callout to Tooling API which has its own limits
            // For now, returning empty list as this is an advanced feature
            // In production, implement using:
            // HttpRequest req = new HttpRequest();
            // req.setEndpoint('callout:Tooling_API/sobjects/ValidationRule?q=SELECT+Id,ValidationName,ErrorMessage,Active+FROM+ValidationRule+WHERE+EntityDefinition.QualifiedApiName=\'' + objectName + '\'');
            
            System.debug('Validation rules query for ' + objectName + ' (simplified implementation)');
            
            // Cache the result
            validationRulesCache.put(objectName, rules);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting validation rules: ' + e.getMessage());
        }
        
        return rules;
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
                System.debug('Returning cached field map for ' + objectName);
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
            
            System.debug('Retrieved and cached field map for ' + objectName + 
                        ' (' + fieldMap.size() + ' fields)');
            
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
                System.debug(LoggingLevel.WARN, 'Object name is blank');
                return null;
            }
            
            String objectKey = objectName.toLowerCase();
            
            // Check cache first
            if (objectDescribeCache.containsKey(objectKey)) {
                System.debug('Returning cached object describe for ' + objectName);
                return objectDescribeCache.get(objectKey);
            }
            
            // Get from global describe
            Map<String, Schema.SObjectType> gd = getGlobalDescribe();
            Schema.SObjectType objectType = gd.get(objectKey);
            
            if (objectType == null) {
                System.debug(LoggingLevel.WARN, 'Object type not found: ' + objectName);
                return null;
            }
            
            // Get describe result
            Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
            
            // Cache the result
            objectDescribeCache.put(objectKey, objectDescribe);
            
            System.debug('Retrieved and cached object describe for ' + objectName);
            
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
            System.debug('Performing global describe (not cached)');
            globalDescribeCache = Schema.getGlobalDescribe();
            System.debug('Global describe completed: ' + globalDescribeCache.size() + ' objects');
        } else {
            System.debug('Returning cached global describe');
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
                System.debug(LoggingLevel.WARN, 'Object name or field name is blank');
                return null;
            }
            
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectName);
            
            if (fieldMap == null) {
                System.debug(LoggingLevel.WARN, 'Object does not exist: ' + objectName);
                return null;
            }
            
            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            
            if (field == null) {
                System.debug(LoggingLevel.WARN, 'Field does not exist: ' + objectName + '.' + fieldName);
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
            
            // Field is required if it's not nillable and has no default value
            Boolean isRequired = !fieldDescribe.isNillable() && 
                                !fieldDescribe.isDefaultedOnCreate();
            
            System.debug('Field required check: ' + objectName + '.' + fieldName + ' = ' + isRequired);
            
            return isRequired;
            
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
            
            if (fieldMap == null) {
                return requiredFields;
            }
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Check if field is required
                if (!fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate()) {
                    requiredFields.add(fieldDescribe.getName());
                }
            }
            
            System.debug('Found ' + requiredFields.size() + ' required fields on ' + objectName);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting required fields: ' + e.getMessage());
        }
        
        return requiredFields;
    }
    
    /**
     * @description Clear all caches (useful for testing or after metadata changes)
     */
    @TestVisible
    private static void clearCache() {
        globalDescribeCache = null;
        fieldMapCache.clear();
        objectDescribeCache.clear();
        validationRulesCache.clear();
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
        
        return stats;
    }
}