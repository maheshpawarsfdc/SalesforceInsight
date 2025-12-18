/**
 * @description Reusable service class for retrieving metadata from Tooling API and Metadata API
 * @author System
 * @date 2025
 */
public with sharing class MetadataRetriever {
    
    // Transaction-level cache to avoid duplicate API calls
    private static Map<String, Object> responseCache = new Map<String, Object>();
    
    // Constants
    private static final String TOOLING_API_ENDPOINT = '/services/data/v60.0/tooling/query/';
    private static final Integer MAX_RETRIES = 3;
    private static final Integer RETRY_DELAY_MS = 1000;
    
    /**
     * @description Wrapper class for API responses
     */
    public class MetadataResponse {
        public Boolean success;
        public String errorMessage;
        public Object data;
        
        public MetadataResponse(Boolean success, Object data, String errorMessage) {
            this.success = success;
            this.data = data;
            this.errorMessage = errorMessage;
        }
    }
    
    /**
     * @description Custom exception for metadata retrieval errors
     */
    public class MetadataRetrieverException extends Exception {}
    
    /**
     * @description Queries the Tooling API with retry logic and caching
     * @param query SOQL query to execute against Tooling API
     * @return MetadataResponse containing query results or error details
     */
    public static MetadataResponse queryToolingAPI(String query) {
        if (String.isBlank(query)) {
            return new MetadataResponse(false, null, 'Query cannot be empty');
        }
        
        // Check cache first
        String cacheKey = 'tooling_' + query;
        if (responseCache.containsKey(cacheKey)) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Returning cached Tooling API response for: ' + query);
            }
            return (MetadataResponse) responseCache.get(cacheKey);
        }
        
        try {
            // Check if we're in a context that allows callouts
            if (System.isBatch() || System.isFuture() || System.isQueueable()) {
                return executeToolingQuery(query, cacheKey);
            } else {
                // Queue for async execution
                return queueToolingQuery(query);
            }
        } catch (Exception e) {
            String errorMsg = 'Tooling API query failed: ' + e.getMessage();
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] ' + errorMsg);
            }
            return new MetadataResponse(false, null, errorMsg);
        }
    }
    
    /**
     * @description Executes Tooling API query with retry logic
     * @param query SOQL query string
     * @param cacheKey Cache key for storing response
     * @return MetadataResponse with query results
     */
    private static MetadataResponse executeToolingQuery(String query, String cacheKey) {
        Integer attemptCount = 0;
        Exception lastException;
        
        while (attemptCount < MAX_RETRIES) {
            try {
                HttpRequest req = buildToolingAPIRequest(query);
                HttpResponse res = new Http().send(req);
                
                if (res.getStatusCode() == 200) {
                    Object parsedResponse = JSON.deserializeUntyped(res.getBody());
                    MetadataResponse response = new MetadataResponse(true, parsedResponse, null);
                    responseCache.put(cacheKey, response);
                    if (ConfigService.isDebugLoggingEnabled()) {
                        System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Tooling API query successful: ' + query);
                    }
                    return response;
                } else if (res.getStatusCode() == 401 || res.getStatusCode() == 403) {
                    return new MetadataResponse(false, null, 'Insufficient permissions to access Tooling API');
                } else if (res.getStatusCode() >= 500 && attemptCount < MAX_RETRIES - 1) {
                    // Retry on server errors
                    attemptCount++;
                    if (ConfigService.isDebugLoggingEnabled()) {
                        System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Tooling API server error, retrying... Attempt: ' + attemptCount);
                    }
                    continue;
                } else {
                    return new MetadataResponse(false, null, 'API Error: ' + res.getStatus() + ' - ' + res.getBody());
                }
            } catch (System.CalloutException e) {
                lastException = e;
                if (e.getMessage().contains('timeout') && attemptCount < MAX_RETRIES - 1) {
                    attemptCount++;
                    if (ConfigService.isDebugLoggingEnabled()) {
                        System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Callout timeout, retrying... Attempt: ' + attemptCount);
                    }
                } else {
                    break;
                }
            } catch (Exception e) {
                return new MetadataResponse(false, null, 'Unexpected error: ' + e.getMessage());
            }
        }
        
        return new MetadataResponse(false, null, 'Max retries exceeded: ' + lastException?.getMessage());
    }
    
    /**
     * @description Builds HTTP request for Tooling API
     * @param query SOQL query string
     * @return HttpRequest configured for Tooling API
     */
    private static HttpRequest buildToolingAPIRequest(String query) {
        HttpRequest req = new HttpRequest();
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + TOOLING_API_ENDPOINT;
        req.setEndpoint(endpoint + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        
        Integer timeout = ConfigService.getApiTimeoutSeconds() * 1000;
        req.setTimeout(timeout);
        
        return req;
    }
    
    /**
     * @description Queues Tooling API query for async execution
     * @param query SOQL query string
     * @return MetadataResponse indicating async execution
     */
    private static MetadataResponse queueToolingQuery(String query) {
        // In a real implementation, you'd enqueue this with Queueable
        return new MetadataResponse(false, null, 'Callouts not allowed in this context. Use @future or Queueable.');
    }
    
    /**
     * @description Queries Metadata API for specific metadata type and full name
     * @param metadataType Type of metadata (e.g., 'CustomObject', 'ApexClass')
     * @param fullName Full name of the metadata component
     * @return MetadataResponse containing metadata details
     */
    public static MetadataResponse queryMetadataAPI(String metadataType, String fullName) {
        if (String.isBlank(metadataType) || String.isBlank(fullName)) {
            return new MetadataResponse(false, null, 'MetadataType and FullName cannot be empty');
        }
        
        // Check cache
        String cacheKey = 'metadata_' + metadataType + '_' + fullName;
        if (responseCache.containsKey(cacheKey)) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Returning cached Metadata API response for: ' + metadataType + '.' + fullName);
            }
            return (MetadataResponse) responseCache.get(cacheKey);
        }
        
        try {
            // Use Tooling API to query metadata
            String query = buildMetadataQuery(metadataType, fullName);
            return queryToolingAPI(query);
        } catch (Exception e) {
            String errorMsg = 'Metadata API query failed: ' + e.getMessage();
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] ' + errorMsg);
            }
            return new MetadataResponse(false, null, errorMsg);
        }
    }
    
    /**
     * @description Builds SOQL query for metadata retrieval
     * @param metadataType Type of metadata
     * @param fullName Full name of component
     * @return SOQL query string
     */
    private static String buildMetadataQuery(String metadataType, String fullName) {
        // Map common metadata types to Tooling API objects
        Map<String, String> typeMapping = new Map<String, String>{
            'CustomObject' => 'CustomObject',
            'ApexClass' => 'ApexClass',
            'ApexTrigger' => 'ApexTrigger',
            'FlowDefinition' => 'FlowDefinition',
            'ValidationRule' => 'ValidationRule'
        };
        
        String toolingObject = typeMapping.get(metadataType);
        if (toolingObject == null) {
            throw new MetadataRetrieverException('Unsupported metadata type: ' + metadataType);
        }
        
        return 'SELECT Id, Name, NamespacePrefix FROM ' + toolingObject + ' WHERE DeveloperName = \'' + fullName + '\'';
    }
    
    /**
     * @description Describes a Salesforce object using Schema methods
     * @param objectName API name of the object
     * @return MetadataResponse containing object describe information
     */
    public static MetadataResponse describeObject(String objectName) {
        if (String.isBlank(objectName)) {
            return new MetadataResponse(false, null, 'Object name cannot be empty');
        }
        
        // Check cache
        String cacheKey = 'describe_' + objectName;
        if (responseCache.containsKey(cacheKey)) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Returning cached describe for: ' + objectName);
            }
            return (MetadataResponse) responseCache.get(cacheKey);
        }
        
        try {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            
            if (objectType == null) {
                return new MetadataResponse(false, null, 'Object not found: ' + objectName);
            }
            
            Schema.DescribeSObjectResult describeResult = objectType.getDescribe();
            
            // Build response with essential information
            Map<String, Object> objectInfo = new Map<String, Object>{
                'name' => describeResult.getName(),
                'label' => describeResult.getLabel(),
                'isCustom' => describeResult.isCustom(),
                'isCustomSetting' => describeResult.isCustomSetting(),
                'fieldCount' => describeResult.fields.getMap().size(),
                'recordTypeCount' => describeResult.getRecordTypeInfos().size()
            };
            
            MetadataResponse response = new MetadataResponse(true, objectInfo, null);
            responseCache.put(cacheKey, response);
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Object describe successful: ' + objectName);
            }
            return response;
            
        } catch (Exception e) {
            String errorMsg = 'Object describe failed: ' + e.getMessage();
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] ' + errorMsg);
            }
            return new MetadataResponse(false, null, errorMsg);
        }
    }
    
    /**
     * @description Gets metadata for a specific field
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @return MetadataResponse containing field metadata
     */
    public static MetadataResponse getFieldMetadata(String objectName, String fieldName) {
        if (String.isBlank(objectName) || String.isBlank(fieldName)) {
            return new MetadataResponse(false, null, 'Object name and field name cannot be empty');
        }
        
        // Check cache
        String cacheKey = 'field_' + objectName + '_' + fieldName;
        if (responseCache.containsKey(cacheKey)) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Returning cached field metadata for: ' + objectName + '.' + fieldName);
            }
            return (MetadataResponse) responseCache.get(cacheKey);
        }
        
        try {
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            
            if (objectType == null) {
                return new MetadataResponse(false, null, 'Object not found: ' + objectName);
            }
            
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            Schema.SObjectField field = fieldMap.get(fieldName);
            
            if (field == null) {
                return new MetadataResponse(false, null, 'Field not found: ' + fieldName + ' on ' + objectName);
            }
            
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            
            // Build response with field information
            Map<String, Object> fieldInfo = new Map<String, Object>{
                'name' => fieldDescribe.getName(),
                'label' => fieldDescribe.getLabel(),
                'type' => fieldDescribe.getType().name(),
                'length' => fieldDescribe.getLength(),
                'isCustom' => fieldDescribe.isCustom(),
                'isRequired' => !fieldDescribe.isNillable(),
                'isUnique' => fieldDescribe.isUnique(),
                'referenceTo' => getReferenceTo(fieldDescribe)
            };
            
            MetadataResponse response = new MetadataResponse(true, fieldInfo, null);
            responseCache.put(cacheKey, response);
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Field metadata retrieval successful: ' + objectName + '.' + fieldName);
            }
            return response;
            
        } catch (Exception e) {
            String errorMsg = 'Field metadata retrieval failed: ' + e.getMessage();
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] ' + errorMsg);
            }
            return new MetadataResponse(false, null, errorMsg);
        }
    }
    
    /**
     * @description Gets referenced object names for lookup/master-detail fields
     * @param fieldDescribe Field describe result
     * @return List of referenced object names
     */
    private static List<String> getReferenceTo(Schema.DescribeFieldResult fieldDescribe) {
        List<String> references = new List<String>();
        for (Schema.SObjectType ref : fieldDescribe.getReferenceTo()) {
            references.add(ref.getDescribe().getName());
        }
        return references;
    }
    
    /**
     * @description Clears the transaction cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        responseCache.clear();
    }
    
    /**
     * @description Future method for async Tooling API queries
     * @param query SOQL query to execute
     */
    @future(callout=true)
    public static void queryToolingAPIAsync(String query) {
        if (String.isBlank(query)) {
            return;
        }
        
        try {
            MetadataResponse response = executeToolingQuery(query, 'async_' + query);
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Async Tooling API query completed: ' + response.success);
            }
        } catch (Exception e) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[MetadataRetriever] Async Tooling API query failed: ' + e.getMessage());
            }
        }
    }
}