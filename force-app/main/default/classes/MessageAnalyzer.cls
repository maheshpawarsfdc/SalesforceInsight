/**
 * @description Analyzes user messages to extract entities and determine diagnostic needs
 * Uses pattern matching, keyword detection, and schema validation
 * ENHANCED: Now detects ANY standard or custom FIELD and OBJECT in the org
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 2.0 - Complete Field Detection
 */
public with sharing class MessageAnalyzer {
    
   // Regex patterns for entity extraction
private static final Pattern RECORD_ID_PATTERN = Pattern.compile('\\b([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})\\b');
private static final Pattern FIELD_PATTERN = Pattern.compile('\\b([A-Z][a-zA-Z0-9_]*__c)\\b');
private static final Pattern CUSTOM_OBJECT_PATTERN = Pattern.compile('\\b([A-Z][a-zA-Z0-9_]*__c)\\b');

// Lazy-loaded caches - populated ONLY for objects/fields found in message
private static Map<String, String> objectLabelToApiNameCache; // label -> apiName (lazy)
private static Set<String> describedObjectsCache; // Set of objects we've already described

// Lazy-loaded field caches - populated on-demand per object
private static Map<String, Map<String, String>> fieldsPerObjectCache; // objectName -> (fieldLabel -> fieldApiName)
private static Map<String, Set<String>> fieldApiNamesPerObjectCache; // objectName -> Set<fieldApiNames>

// Common standard fields cache (pre-loaded, small set)
private static final Set<String> COMMON_STANDARD_FIELDS = new Set<String>{
    'Name', 'Phone', 'Email', 'Address', 'Owner', 'OwnerId', 'Status', 'Type',
    'Amount', 'CloseDate', 'StageName', 'Description', 'CreatedDate', 'CreatedById',
    'LastModifiedDate', 'LastModifiedById', 'AccountId', 'ContactId', 'IsDeleted',
    'Id', 'RecordTypeId', 'LastActivityDate', 'Website', 'Industry', 'AnnualRevenue'
};

// Keyword mappings for issue categories
private static final Map<String, List<String>> CATEGORY_KEYWORDS = new Map<String, List<String>>{
    'field_visibility' => new List<String>{
        'can\'t see', 'cannot see', 'don\'t see', 'missing field', 'field missing',
        'field not visible', 'hidden field', 'field disappeared', 'where is',
        'not showing', 'can\'t view', 'cannot view', 'invisible field'
    },
    'edit_permission' => new List<String>{
        'can\'t edit', 'cannot edit', 'can\'t update', 'cannot update', 'read only',
        'read-only', 'unable to edit', 'unable to update', 'can\'t modify',
        'cannot modify', 'locked field', 'disabled field', 'grayed out', 'greyed out',
        'can\'t create', 'cannot create', 'unable to create', 'not able to create'
    },
    'save_error' => new List<String>{
        'can\'t save', 'cannot save', 'save error', 'error saving', 'error when saving',
        'failed to save', 'won\'t save', 'will not save', 'save failed'
    },
    'access_issue' => new List<String>{
        'can\'t access', 'cannot access', 'no access', 'access denied', 'insufficient privileges',
        'insufficient permissions', 'don\'t have access', 'can\'t open', 'cannot open',
        'unable to access', 'permission denied', 'not authorized'
    },
    'validation_error' => new List<String>{
        'validation', 'validation rule', 'validation error', 'required field',
        'field is required', 'must be filled', 'cannot be blank', 'invalid value'
    },
    'general' => new List<String>{
        'help', 'how do i', 'how to', 'what is', 'explain', 'why', 'question'
    }
};

public class MessageAnalysis {
    @AuraEnabled public String issueCategory;
    @AuraEnabled public List<String> objectsInvolved;
    @AuraEnabled public List<String> fieldsInvolved;
    @AuraEnabled public List<String> recordIds;
    @AuraEnabled public List<String> diagnosticsNeeded;
    @AuraEnabled public String confidence;
    @AuraEnabled public String reasoning;
    
    public MessageAnalysis() {
        this.objectsInvolved = new List<String>();
        this.fieldsInvolved = new List<String>();
        this.recordIds = new List<String>();
        this.diagnosticsNeeded = new List<String>();
        this.confidence = 'low';
        this.issueCategory = 'general';
    }
}

/**
 * @description Analyze a user message
 */
public static MessageAnalysis analyzeMessage(String message) {
    Long startTime = System.currentTimeMillis();
    
    MessageAnalysis analysis = new MessageAnalysis();
    
    try {
        if (String.isBlank(message)) {
            analysis.reasoning = 'Empty message provided';
            return analysis;
        }
        
        String normalizedMessage = message.toLowerCase().trim();
        
        System.debug('=== MESSAGE ANALYZER START ===');
        System.debug('Message: ' + message);
        
        // Step 1: Extract record IDs
        analysis.recordIds = extractRecordIds(message);
        System.debug('Record IDs: ' + analysis.recordIds);
        
        // Step 2: Extract objects
        analysis.objectsInvolved = extractObjects(message);
        System.debug('Objects: ' + analysis.objectsInvolved);
        
        // Step 3: Extract fields (LAZY - only for identified objects)
        analysis.fieldsInvolved = extractFieldsLazy(message, analysis.objectsInvolved);
        System.debug('Fields: ' + analysis.fieldsInvolved);
        
        // Step 4: Determine issue category
        analysis.issueCategory = determineIssueCategory(normalizedMessage);
        System.debug('Category: ' + analysis.issueCategory);
        
        // Step 5: Determine diagnostics
        analysis.diagnosticsNeeded = determineDiagnostics(analysis);
        System.debug('Diagnostics: ' + analysis.diagnosticsNeeded);
        
        // Step 6: Calculate confidence
        analysis.confidence = calculateConfidence(analysis, normalizedMessage);
        System.debug('Confidence: ' + analysis.confidence);
        
        // Step 7: Generate reasoning
        analysis.reasoning = generateReasoning(analysis);
        System.debug('Reasoning: ' + analysis.reasoning);
        
        Long endTime = System.currentTimeMillis();
        System.debug('Analysis completed in ' + (endTime - startTime) + 'ms');
        System.debug('=== MESSAGE ANALYZER END ===');
        
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Error analyzing message: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        analysis.reasoning = 'Error during analysis: ' + e.getMessage();
    }
    
    return analysis;
}

/**
 * @description Initialize lazy cache structures (no schema queries)
 */
private static void initializeLazyCache() {
    if (objectLabelToApiNameCache != null) {
        return; // Already initialized
    }
    
    System.debug('Initializing lazy cache structures');
    objectLabelToApiNameCache = new Map<String, String>();
    describedObjectsCache = new Set<String>();
    fieldsPerObjectCache = new Map<String, Map<String, String>>();
    fieldApiNamesPerObjectCache = new Map<String, Set<String>>();
}

/**
 * @description Extract candidate object names from message using simple pattern matching
 * Returns potential object API names and labels that might exist in the org
 */
private static Set<String> extractObjectCandidates(String message) {
    Set<String> candidates = new Set<String>();
    String messageLower = message.toLowerCase();
    
    System.debug('Extracting object candidates from message');
    
    // Method 1: Custom object pattern (Something__c)
    Matcher customObjectMatcher = CUSTOM_OBJECT_PATTERN.matcher(message);
    while (customObjectMatcher.find()) {
        String customObject = customObjectMatcher.group(1);
        candidates.add(customObject);
        System.debug('Candidate (custom pattern): ' + customObject);
    }
    
    // Method 2: Split message into words and create combinations
    List<String> words = messageLower.split('[\\s,\\.\\!\\?\\:]');
    
    for (Integer i = 0; i < words.size(); i++) {
        String word = words[i].trim();
        if (String.isBlank(word) || word.length() < 3) continue;
        
        // Single word - will check if it's a valid object label
        candidates.add(word);
        
        // Two-word combinations
        if (i < words.size() - 1) {
            String twoWords = word + ' ' + words[i + 1].trim();
            if (twoWords.length() < 50) {
                candidates.add(twoWords);
            }
        }
        
        // Three-word combinations
        if (i < words.size() - 2) {
            String threeWords = word + ' ' + words[i + 1].trim() + ' ' + words[i + 2].trim();
            if (threeWords.length() < 50) {
                candidates.add(threeWords);
            }
        }
    }
    
    System.debug('Total candidates extracted: ' + candidates.size());
    return candidates;
}

/**
 * @description Check if a candidate is a valid object by attempting to describe it
 * Only describes objects that match candidate, lazy-loads and caches
 */
private static String validateAndCacheObjectCandidate(String candidate) {
    initializeLazyCache();
    
    if (String.isBlank(candidate)) return null;
    
    candidate = candidate.trim();
    
    // Check if already cached (both successful and failed attempts)
    if (describedObjectsCache.contains(candidate)) {
        return objectLabelToApiNameCache.get(candidate);
    }
    
    try {
        // Try to get the object by label or API name
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        // Check if it's a direct API name match
        if (globalDescribe.containsKey(candidate)) {
            Schema.DescribeSObjectResult objDescribe = globalDescribe.get(candidate).getDescribe();
            String apiName = objDescribe.getName();
            objectLabelToApiNameCache.put(candidate, apiName);
            describedObjectsCache.add(candidate);
            System.debug('Validated object (API match): ' + candidate + ' -> ' + apiName);
            return apiName;
        }
        
        // Check if it matches a label (iterate only through candidate attempts, not all objects)
        for (String objectApiName : globalDescribe.keySet()) {
            try {
                Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objectApiName).getDescribe();
                
                String label = objDescribe.getLabel().toLowerCase();
                String pluralLabel = objDescribe.getLabelPlural().toLowerCase();
                
                if (label.equalsIgnoreCase(candidate) || pluralLabel.equalsIgnoreCase(candidate)) {
                    String apiName = objDescribe.getName();
                    objectLabelToApiNameCache.put(candidate, apiName);
                    objectLabelToApiNameCache.put(label, apiName); // Cache label too
                    objectLabelToApiNameCache.put(pluralLabel, apiName); // Cache plural too
                    describedObjectsCache.add(candidate);
                    System.debug('Validated object (label match): ' + candidate + ' -> ' + apiName);
                    return apiName;
                }
            } catch (Exception e) {
                // Skip objects that can't be described
            }
        }
        
    } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Error validating candidate: ' + candidate + ' - ' + e.getMessage());
    }
    
    // Mark as checked even if not found (to avoid re-checking)
    describedObjectsCache.add(candidate);
    return null;
}

/**
 * @description Load fields for a specific object (lazy loading)
 * Only called when we actually need fields for an object
 */
private static void loadFieldsForObject(String objectName) {
    // Check if already loaded
    if (fieldsPerObjectCache.containsKey(objectName)) {
        return;
    }
    
    System.debug('Lazy loading fields for object: ' + objectName);
    
    Map<String, String> fieldLabelToApi = new Map<String, String>();
    Set<String> fieldApiNames = new Set<String>();
    
    try {
        Map<String, Schema.SObjectField> fieldMap = MetadataQueryService.getFieldMap(objectName);
        
        if (fieldMap != null) {
            for (String fieldApiName : fieldMap.keySet()) {
                try {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
                    
                    String fieldName = fieldDescribe.getName();
                    String fieldLabel = fieldDescribe.getLabel().toLowerCase();
                    
                    fieldApiNames.add(fieldName);
                    fieldLabelToApi.put(fieldLabel, fieldName);
                    
                } catch (Exception e) {
                    // Skip problematic fields
                }
            }
        }
        
        System.debug('Loaded ' + fieldApiNames.size() + ' fields for ' + objectName);
        
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, 'Error loading fields for ' + objectName + ': ' + e.getMessage());
    }
    
    // Cache the results
    fieldsPerObjectCache.put(objectName, fieldLabelToApi);
    fieldApiNamesPerObjectCache.put(objectName, fieldApiNames);
}

/**
 * @description Extract record IDs
 */
private static List<String> extractRecordIds(String message) {
    List<String> recordIds = new List<String>();
    
    Matcher matcher = RECORD_ID_PATTERN.matcher(message);
    while (matcher.find()) {
        String potentialId = matcher.group(1);
        if (isValidSalesforceId(potentialId)) {
            recordIds.add(potentialId);
        }
    }
    
    return recordIds;
}

/**
 * @description Extract objects from message using lazy validation
 * Only validates candidates that appear in the message
 */
private static List<String> extractObjects(String message) {
    Set<String> objects = new Set<String>();
    initializeLazyCache();
    
    System.debug('=== EXTRACTING OBJECTS (LAZY) ===');
    
    // Step 1: Extract candidates from message
    Set<String> candidates = extractObjectCandidates(message);
    
    // Step 2: Validate only candidates (lazy loading by object)
    for (String candidate : candidates) {
        String validatedObject = validateAndCacheObjectCandidate(candidate);
        if (validatedObject != null) {
            objects.add(validatedObject);
        }
    }
    
    System.debug('Objects found: ' + objects.size());
    return new List<String>(objects);
}

/**
 * @description Extract fields LAZILY - only load fields for identified objects
 */
private static List<String> extractFieldsLazy(String message, List<String> objects) {
    Set<String> fields = new Set<String>();
    String messageLower = message.toLowerCase();
    
    System.debug('=== EXTRACTING FIELDS (LAZY) ===');
    initializeLazyCache();
    
    // Method 1: Custom field pattern (Something__c)
    Matcher customFieldMatcher = FIELD_PATTERN.matcher(message);
    while (customFieldMatcher.find()) {
        String customField = customFieldMatcher.group(1);
        
        // Verify on identified objects
        if (!objects.isEmpty()) {
            for (String obj : objects) {
                if (MetadataQueryService.checkFieldExists(obj, customField)) {
                    fields.add(customField);
                    System.debug('Found custom field: ' + customField + ' on ' + obj);
                    break;
                }
            }
        }
    }
    
    // Method 2: Common standard fields (no describe needed)
    for (String commonField : COMMON_STANDARD_FIELDS) {
        if (message.containsIgnoreCase(commonField) || 
            messageLower.contains(commonField.toLowerCase())) {
            fields.add(commonField);
            System.debug('Found common field: ' + commonField);
        }
    }
    
    // Method 3: Load fields ONLY for identified objects
    if (!objects.isEmpty()) {
        for (String objectName : objects) {
            // Lazy load fields for this object
            loadFieldsForObject(objectName);
            
            // Now check if any field labels match
            Map<String, String> fieldLabelToApi = fieldsPerObjectCache.get(objectName);
            
            if (fieldLabelToApi != null) {
                List<String> words = messageLower.split('[\\s,\\.\\!\\?\\:]');
                
                for (Integer i = 0; i < words.size(); i++) {
                    String word = words[i].trim();
                    if (String.isBlank(word)) continue;
                    
                    // Single word
                    if (fieldLabelToApi.containsKey(word)) {
                        String fieldApiName = fieldLabelToApi.get(word);
                        fields.add(fieldApiName);
                        System.debug('Found field by label: ' + word + ' -> ' + fieldApiName);
                    }
                    
                    // Two words
                    if (i < words.size() - 1) {
                        String twoWords = word + ' ' + words[i + 1].trim();
                        if (fieldLabelToApi.containsKey(twoWords)) {
                            String fieldApiName = fieldLabelToApi.get(twoWords);
                            fields.add(fieldApiName);
                            System.debug('Found field: ' + twoWords + ' -> ' + fieldApiName);
                        }
                    }
                }
            }
        }
    }
    
    // Method 4: Special phrase handling
    if (messageLower.contains('phone field') || messageLower.contains('phone number')) {
        fields.add('Phone');
    }
    if (messageLower.contains('email field') || messageLower.contains('email address')) {
        fields.add('Email');
    }
    if (messageLower.contains('close date')) {
        fields.add('CloseDate');
    }
    
    return new List<String>(fields);
}

/**
 * @description Determine issue category
 */
private static String determineIssueCategory(String normalizedMessage) {
    Map<String, Integer> categoryScores = new Map<String, Integer>();
    
    for (String category : CATEGORY_KEYWORDS.keySet()) {
        Integer score = 0;
        for (String keyword : CATEGORY_KEYWORDS.get(category)) {
            if (normalizedMessage.contains(keyword)) {
                score += 10;
            }
        }
        categoryScores.put(category, score);
    }
    
    String topCategory = 'general';
    Integer highestScore = 0;
    
    for (String category : categoryScores.keySet()) {
        if (categoryScores.get(category) > highestScore) {
            highestScore = categoryScores.get(category);
            topCategory = category;
        }
    }
    
    return topCategory;
}

/**
 * @description Determine diagnostics
 */
private static List<String> determineDiagnostics(MessageAnalysis analysis) {
    Set<String> diagnostics = new Set<String>();
    
    diagnostics.add('checkUserProfile');
    
    if (!analysis.objectsInvolved.isEmpty()) {
        diagnostics.add('checkObjectPermissions');
    }
    
    if (!analysis.fieldsInvolved.isEmpty()) {
        diagnostics.add('checkFieldSecurity');
        diagnostics.add('checkPageLayout');
    }
    
    if (!analysis.recordIds.isEmpty()) {
        diagnostics.add('checkRecordAccess');
    }
    
    switch on analysis.issueCategory {
        when 'field_visibility' {
            diagnostics.add('checkFieldSecurity');
            diagnostics.add('checkPageLayout');
        }
        when 'edit_permission', 'access_issue' {
            diagnostics.add('checkObjectPermissions');
            diagnostics.add('checkFieldSecurity');
            if (!analysis.recordIds.isEmpty()) {
                diagnostics.add('checkRecordAccess');
            }
        }
        when 'save_error' {
            diagnostics.add('checkValidationRules');
            diagnostics.add('checkRequiredFields');
            diagnostics.add('checkFieldSecurity');
        }
        when 'validation_error' {
            diagnostics.add('checkValidationRules');
            diagnostics.add('checkRequiredFields');
        }
    }
    
    return new List<String>(diagnostics);
}

/**
 * @description Calculate confidence
 */
private static String calculateConfidence(MessageAnalysis analysis, String normalizedMessage) {
    Integer confidenceScore = 0;
    
    if (!analysis.objectsInvolved.isEmpty()) confidenceScore += 30;
    if (!analysis.fieldsInvolved.isEmpty()) confidenceScore += 30;
    if (!analysis.recordIds.isEmpty()) confidenceScore += 20;
    if (analysis.issueCategory != 'general') confidenceScore += 20;
    
    Integer wordCount = normalizedMessage.split('\\s+').size();
    if (wordCount >= 5 && wordCount <= 30) {
        confidenceScore += 10;
    } else if (wordCount < 5) {
        confidenceScore -= 10;
    }
    
    if (confidenceScore >= 70) return 'high';
    else if (confidenceScore >= 40) return 'medium';
    else return 'low';
}

/**
 * @description Generate reasoning
 */
private static String generateReasoning(MessageAnalysis analysis) {
    List<String> reasons = new List<String>();
    
    if (!analysis.objectsInvolved.isEmpty()) {
        reasons.add('Objects: ' + String.join(analysis.objectsInvolved, ', '));
    }
    if (!analysis.fieldsInvolved.isEmpty()) {
        reasons.add('Fields: ' + String.join(analysis.fieldsInvolved, ', '));
    }
    if (!analysis.recordIds.isEmpty()) {
        reasons.add(analysis.recordIds.size() + ' record ID(s)');
    }
    
    reasons.add('Category: ' + analysis.issueCategory);
    reasons.add('Confidence: ' + analysis.confidence);
    
    return String.join(reasons, '; ');
}

private static Boolean isValidSalesforceId(String potentialId) {
    if (String.isBlank(potentialId)) return false;
    Integer len = potentialId.length();
    if (len != 15 && len != 18) return false;
    return potentialId.substring(0, 1).isAlphanumeric();
}

public static List<MessageAnalysis> analyzeMessages(List<String> messages) {
    List<MessageAnalysis> results = new List<MessageAnalysis>();
    for (String message : messages) {
        results.add(analyzeMessage(message));
    }
    return results;
}

public static Map<String, Integer> getAnalysisStats() {
    Map<String, Integer> stats = new Map<String, Integer>();
    stats.put('cachedObjectLabels', objectLabelToApiNameCache != null ? objectLabelToApiNameCache.size() : 0);
    stats.put('describedObjects', describedObjectsCache != null ? describedObjectsCache.size() : 0);
    stats.put('lazyLoadedObjectFields', fieldsPerObjectCache != null ? fieldsPerObjectCache.size() : 0);
    return stats;
}

@TestVisible
private static void clearCache() {
    objectLabelToApiNameCache = null;
    describedObjectsCache = null;
    fieldsPerObjectCache = null;
    fieldApiNamesPerObjectCache = null;
}
}