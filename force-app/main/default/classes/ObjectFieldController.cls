/**
 * @description Controller for object and field selection in diagnostic tool
 * @author System
 * @date 2025
 */
public with sharing class ObjectFieldController {
    
    // Cache for object list (transaction-level)
    private static List<ObjectInfo> cachedObjects;
    
    /**
     * @description Wrapper class for object information
     */
    public class ObjectInfo {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Boolean isCustom;
        @AuraEnabled public String category;
        
        public ObjectInfo(String label, String value, Boolean isCustom) {
            this.label = label;
            this.value = value;
            this.isCustom = isCustom;
            this.category = isCustom ? 'Custom Objects' : 'Standard Objects';
        }
    }
    
    /**
     * @description Wrapper class for field information
     */
    public class FieldInfo {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String apiName;
        @AuraEnabled public String dataType;
        @AuraEnabled public Boolean isCustom;
        
        public FieldInfo(String label, String apiName, String dataType, Boolean isCustom) {
            this.label = label;
            this.value = apiName;
            this.apiName = apiName;
            this.dataType = dataType;
            this.isCustom = isCustom;
        }
    }
    
    /**
     * @description Gets all standard and custom objects accessible to the user
     * @return List<ObjectInfo> List of all accessible objects
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectInfo> getAllObjects() {
        if (cachedObjects != null) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[ObjectFieldController] Returning cached object list');
            }
            return cachedObjects;
        }
        
        List<ObjectInfo> objectList = new List<ObjectInfo>();
        
        try {
            // Get all objects from global describe
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            
            for (String objectName : globalDescribe.keySet()) {
                Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objectName).getDescribe();
                
                // Filter criteria: accessible, createable or queryable
                if (objDescribe.isAccessible() && 
                    (objDescribe.isCreateable() || objDescribe.isQueryable())) {
                    
                    // Skip system/internal objects
                    if (shouldIncludeObject(objDescribe)) {
                        objectList.add(new ObjectInfo(
                            objDescribe.getLabel(),
                            objDescribe.getName(),
                            objDescribe.isCustom()
                        ));
                    }
                }
            }
            
            // Sort: Standard objects first, then custom, both alphabetically
            objectList = sortObjects(objectList);
            
            // Cache the result
            cachedObjects = objectList;
            
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[ObjectFieldController] Retrieved ' + objectList.size() + ' objects');
            }
            
            return objectList;
            
        } catch (Exception e) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[ObjectFieldController] Error getting objects: ' + e.getMessage());
            }
            throw new AuraHandledException('Error retrieving objects: ' + e.getMessage());
        }
    }
    
    /**
     * @description Gets all fields for a specific object
     * @param objectName API name of the object
     * @return List<FieldInfo> List of all fields for the object
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getObjectFields(String objectName) {
        if (String.isBlank(objectName)) {
            throw new AuraHandledException('Object name cannot be empty');
        }
        
        List<FieldInfo> fieldList = new List<FieldInfo>();
        
        try {
            // Get object type
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            
            if (objectType == null) {
                throw new AuraHandledException('Object not found: ' + objectName);
            }
            
            // Get all fields
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                // Only include accessible fields
                if (fieldDescribe.isAccessible()) {
                    fieldList.add(new FieldInfo(
                        fieldDescribe.getLabel(),
                        fieldDescribe.getName(),
                        fieldDescribe.getType().name(),
                        fieldDescribe.isCustom()
                    ));
                }
            }
            
            // Sort alphabetically by label
            fieldList = sortFields(fieldList);
            
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[ObjectFieldController] Retrieved ' + fieldList.size() + ' fields for ' + objectName);
            }
            
            return fieldList;
            
        } catch (Exception e) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[ObjectFieldController] Error getting fields: ' + e.getMessage());
            }
            throw new AuraHandledException('Error retrieving fields for ' + objectName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Determines if an object should be included in the list
     * @param objDescribe Object describe result
     * @return Boolean True if object should be included
     */
    private static Boolean shouldIncludeObject(Schema.DescribeSObjectResult objDescribe) {
        String objName = objDescribe.getName();
        
        // Exclude system objects
        if (objName.endsWith('__History') || 
            objName.endsWith('__Tag') || 
            objName.endsWith('__Share') ||
            objName.endsWith('__Feed') ||
            objName.endsWith('__e') ||  // Platform Events
            objName.endsWith('__b') ||  // Big Objects
            objName.endsWith('__mdt') || // Metadata Types
            objName.endsWith('__x')) {  // External Objects
            return false;
        }
        
        // Exclude certain system objects
        Set<String> excludedObjects = new Set<String>{
            'ContentDocumentLink',
            'ContentVersion',
            'FeedComment',
            'FeedItem',
            'NetworkMember',
            'ProcessInstance',
            'ProcessInstanceHistory',
            'Vote'
        };
        
        if (excludedObjects.contains(objName)) {
            return false;
        }
        
        return true;
    }
    
    /**
     * @description Sorts objects: Standard first, then Custom, both alphabetically
     * @param objectList Unsorted list of objects
     * @return List<ObjectInfo> Sorted list
     */
    private static List<ObjectInfo> sortObjects(List<ObjectInfo> objectList) {
        List<ObjectInfo> standardObjects = new List<ObjectInfo>();
        List<ObjectInfo> customObjects = new List<ObjectInfo>();
        
        // Separate standard and custom
        for (ObjectInfo obj : objectList) {
            if (obj.isCustom) {
                customObjects.add(obj);
            } else {
                standardObjects.add(obj);
            }
        }
        
        // Sort each list alphabetically
        standardObjects = sortObjectsByLabel(standardObjects);
        customObjects = sortObjectsByLabel(customObjects);
        
        // Combine: standard first, then custom
        List<ObjectInfo> sortedList = new List<ObjectInfo>();
        sortedList.addAll(standardObjects);
        sortedList.addAll(customObjects);
        
        return sortedList;
    }
    
    /**
     * @description Sorts fields alphabetically by label
     * @param fieldList Unsorted list of fields
     * @return List<FieldInfo> Sorted list
     */
    private static List<FieldInfo> sortFields(List<FieldInfo> fieldList) {
        // Create a map for sorting
        Map<String, FieldInfo> fieldMap = new Map<String, FieldInfo>();
        List<String> labels = new List<String>();
        
        for (FieldInfo field : fieldList) {
            fieldMap.put(field.label.toLowerCase() + '_' + field.apiName, field);
            labels.add(field.label.toLowerCase() + '_' + field.apiName);
        }
        
        // Sort labels
        labels.sort();
        
        // Build sorted list
        List<FieldInfo> sortedList = new List<FieldInfo>();
        for (String label : labels) {
            sortedList.add(fieldMap.get(label));
        }
        
        return sortedList;
    }
    
    /**
     * @description Sorts objects alphabetically by label
     * @param objectList List to sort
     * @return List<ObjectInfo> Sorted list
     */
    private static List<ObjectInfo> sortObjectsByLabel(List<ObjectInfo> objectList) {
        Map<String, ObjectInfo> objectMap = new Map<String, ObjectInfo>();
        List<String> labels = new List<String>();
        
        for (ObjectInfo obj : objectList) {
            objectMap.put(obj.label.toLowerCase() + '_' + obj.value, obj);
            labels.add(obj.label.toLowerCase() + '_' + obj.value);
        }
        
        labels.sort();
        
        List<ObjectInfo> sortedList = new List<ObjectInfo>();
        for (String label : labels) {
            sortedList.add(objectMap.get(label));
        }
        
        return sortedList;
    }
    
    /**
     * @description Clears the cached object list (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        cachedObjects = null;
    }
}