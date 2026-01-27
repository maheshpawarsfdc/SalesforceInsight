/**
 * @description Analyzes user messages to extract entities and determine diagnostic needs
 * Uses pattern matching, keyword detection, and schema validation
 * ENHANCED: Now detects ANY standard or custom FIELD and OBJECT in the org
 * ADMIN MODE: Now extracts target user from queries for admin diagnostics
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 2.1 - Complete Field Detection + User Detection
 */
public with sharing class MessageAnalyzer {
    
    // User identification patterns (for admin diagnostics)
    private static final Pattern USER_ID_PATTERN = Pattern.compile('\\b(005[a-zA-Z0-9]{12,15})\\b');
    private static final Pattern EMAIL_PATTERN = Pattern.compile('\\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})\\b');
    
    // Regex patterns for entity extraction
    private static final Pattern RECORD_ID_PATTERN = Pattern.compile('\\b([a-zA-Z0-9]{15}|[a-zA-Z0-9]{18})\\b');
    private static final Pattern FIELD_PATTERN = Pattern.compile('\\b([A-Z][a-zA-Z0-9_]*__c)\\b');
    private static final Pattern CUSTOM_OBJECT_PATTERN = Pattern.compile('\\b([A-Z][a-zA-Z0-9_]*__c)\\b');

    // Lazy-loaded caches - populated ONLY for objects/fields found in message
    private static Map<String, String> objectLabelToApiNameCache;
    private static Set<String> describedObjectsCache;
    private static Map<String, Map<String, String>> fieldsPerObjectCache;
    private static Map<String, Set<String>> fieldApiNamesPerObjectCache;

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
            'cant see', 'cannot see', 'dont see', 'missing field', 'field missing',
            'field not visible', 'hidden field', 'field disappeared', 'where is',
            'not showing', 'cant view', 'cannot view', 'invisible field'
        },
        'edit_permission' => new List<String>{
            'cant edit', 'cannot edit', 'cant update', 'cannot update', 'read only',
            'read-only', 'unable to edit', 'unable to update', 'cant modify',
            'cannot modify', 'locked field', 'disabled field', 'grayed out', 'greyed out',
            'cant create', 'cannot create', 'unable to create', 'not able to create'
        },
        'save_error' => new List<String>{
            'cant save', 'cannot save', 'save error', 'error saving', 'error when saving',
            'failed to save', 'wont save', 'will not save', 'save failed'
        },
        'access_issue' => new List<String>{
            'cant access', 'cannot access', 'no access', 'access denied', 'insufficient privileges',
            'insufficient permissions', 'dont have access', 'cant open', 'cannot open',
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
        
        // NEW: Target user detection for admin diagnostics
        @AuraEnabled public Id targetUserId;
        @AuraEnabled public String targetUserName;
        @AuraEnabled public String targetUserEmail;
        
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
            
            // Step 3.5: Extract target user (NEW)
            extractTargetUser(message, analysis);
            System.debug('Target User ID: ' + analysis.targetUserId);
            System.debug('Target User Name: ' + analysis.targetUserName);
            System.debug('Target User Email: ' + analysis.targetUserEmail);
            
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
     * @description Extract target user from message (for admin diagnostics)
     * IMPROVED: Better parsing to extract just the user identifier
     * HANDLES: "my permissions", "for me", and ignores non-user keywords
     */
    private static void extractTargetUser(String message, MessageAnalysis analysis) {
        if (String.isBlank(message)) {
            return;
        }
        
        System.debug('=== EXTRACTING TARGET USER ===');
        String lowerMessage = message.toLowerCase();
        
        // EARLY EXIT: Check for self-reference keywords
        // If user says "my", "me", "I", they're asking about themselves
        if (lowerMessage.contains(' my ') || 
            lowerMessage.contains('for me') || 
            lowerMessage.contains('check me') ||
            lowerMessage.startsWith('my ') ||
            lowerMessage.contains(' i ') ||
            lowerMessage.startsWith('i ')) {
            System.debug('Self-reference detected - no target user extraction');
            return; // No target user - use current user
        }
        
        // Method 1: Direct User ID (005...)
        Matcher userIdMatcher = USER_ID_PATTERN.matcher(message);
        if (userIdMatcher.find()) {
            String userId = userIdMatcher.group(1);
            analysis.targetUserId = userId;
            System.debug('Found User ID: ' + userId);
            return;
        }
        
        // Method 2: Email address (most reliable)
        Matcher emailMatcher = EMAIL_PATTERN.matcher(message);
        if (emailMatcher.find()) {
            String email = emailMatcher.group(1);
            analysis.targetUserEmail = email;
            System.debug('Found email: ' + email);
            return;
        }
        
        // Method 3: Username keyword pattern
        // Matches: "for username XXXXX" or "username: XXXXX"
        Pattern usernamePattern = Pattern.compile('(?i)(?:for\\s+)?username[:\\s]+([^\\s]+(?:@[^\\s]+)?)');
        Matcher usernameMatcher = usernamePattern.matcher(message);
        if (usernameMatcher.find()) {
            String username = usernameMatcher.group(1);
            // Could be email or username
            if (username.contains('@')) {
                analysis.targetUserEmail = username;
                System.debug('Found username (email): ' + username);
            } else {
                analysis.targetUserName = username;
                System.debug('Found username: ' + username);
            }
            return;
        }
        
        // Method 4: Name extraction with better validation
        // Matches: "for [FirstName] [LastName]" or "check [FirstName]"
        // But stops at common keywords like "on", "object", "field"
        Pattern namePattern = Pattern.compile('(?i)(?:for|check|diagnose)\\s+([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)?)(?=\\s+on|\\s+object|\\s+field|\\s*$)');
        Matcher nameMatcher = namePattern.matcher(message);
        if (nameMatcher.find()) {
            String name = nameMatcher.group(1).trim();
            
            // VALIDATION: Exclude common non-user keywords
            Set<String> excludeKeywords = new Set<String>{
                'permissions', 'permission', 'access', 'account', 'contact', 
                'opportunity', 'field', 'object', 'check', 'diagnose', 'session',
                'diagnostic', 'issue', 'problem', 'error', 'my', 'me', 'i'
            };
            
            if (!excludeKeywords.contains(name.toLowerCase())) {
                analysis.targetUserName = name;
                System.debug('Found user name: ' + name);
                return;
            } else {
                System.debug('Excluded keyword found in name: ' + name);
            }
        }
        
        // Method 5: Simple name after "for" with strict validation
        // Matches: "for Suraj" but not "for me" or "for permissions"
        Pattern simpleNamePattern = Pattern.compile('(?i)(?:for|user)\\s+([A-Z][a-z]{2,})(?=\\s+on|\\s+object|\\s+field|\\s*$)');
        Matcher simpleNameMatcher = simpleNamePattern.matcher(message);
        if (simpleNameMatcher.find()) {
            String name = simpleNameMatcher.group(1).trim();
            
            // Exclude common keywords (expanded list)
            Set<String> excludeKeywords = new Set<String>{
                'permissions', 'permission', 'access', 'account', 'accounts', 
                'contact', 'contacts', 'opportunity', 'opportunities',
                'field', 'fields', 'object', 'objects', 'check', 'diagnose',
                'session', 'sessions', 'diagnostic', 'issue', 'issues',
                'problem', 'problems', 'error', 'errors', 'my', 'me', 'myself'
            };
            
            if (!excludeKeywords.contains(name.toLowerCase())) {
                analysis.targetUserName = name;
                System.debug('Found user name (simple): ' + name);
                return;
            } else {
                System.debug('Excluded keyword in simple match: ' + name);
            }
        }
        
        // Method 6: Possessive names (John's, Sarah's)
        // But NOT "my permissions" or possessive object names
        Pattern possessivePattern = Pattern.compile('(?i)\\b([A-Z][a-z]{2,}(?:\\s+[A-Z][a-z]+)?)(?:\'s|s\')\\s+(?:permissions|access|issue|problem)');
        Matcher possessiveMatcher = possessivePattern.matcher(message);
        if (possessiveMatcher.find()) {
            String name = possessiveMatcher.group(1).trim();
            
            // Exclude self-references and common keywords
            Set<String> excludeKeywords = new Set<String>{
                'my', 'account', 'contact', 'opportunity', 'object', 'field'
            };
            
            if (!excludeKeywords.contains(name.toLowerCase())) {
                analysis.targetUserName = name;
                System.debug('Found user name (possessive): ' + name);
                return;
            }
        }
        
        System.debug('No target user detected - will use current user');
    }

    /**
     * @description Initialize lazy cache structures
     */
    private static void initializeLazyCache() {
        if (objectLabelToApiNameCache != null) {
            return;
        }
        
        System.debug('Initializing lazy cache structures');
        objectLabelToApiNameCache = new Map<String, String>();
        describedObjectsCache = new Set<String>();
        fieldsPerObjectCache = new Map<String, Map<String, String>>();
        fieldApiNamesPerObjectCache = new Map<String, Set<String>>();
    }

    /**
     * @description Extract candidate object names from message
     */
    private static Set<String> extractObjectCandidates(String message) {
        Set<String> candidates = new Set<String>();
        String messageLower = message.toLowerCase();
        
        System.debug('Extracting object candidates from message');
        
        // Method 1: Custom object pattern
        Matcher customObjectMatcher = CUSTOM_OBJECT_PATTERN.matcher(message);
        while (customObjectMatcher.find()) {
            String customObject = customObjectMatcher.group(1);
            candidates.add(customObject);
            System.debug('Candidate (custom pattern): ' + customObject);
        }
        
        // Method 2: Split message into words
        List<String> words = messageLower.split('[\\s,.!?:]');
        
        for (Integer i = 0; i < words.size(); i++) {
            String word = words[i].trim();
            if (String.isBlank(word) || word.length() < 3) continue;
            
            candidates.add(word);
            
            if (i < words.size() - 1) {
                String twoWords = word + ' ' + words[i + 1].trim();
                if (twoWords.length() < 50) {
                    candidates.add(twoWords);
                }
            }
            
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
     * @description Validate and cache object candidate
     */
    private static String validateAndCacheObjectCandidate(String candidate) {
        initializeLazyCache();
        
        if (String.isBlank(candidate)) return null;
        
        candidate = candidate.trim();
        
        if (describedObjectsCache.contains(candidate)) {
            return objectLabelToApiNameCache.get(candidate);
        }
        
        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            
            if (globalDescribe.containsKey(candidate)) {
                Schema.DescribeSObjectResult objDescribe = globalDescribe.get(candidate).getDescribe();
                String apiName = objDescribe.getName();
                objectLabelToApiNameCache.put(candidate, apiName);
                describedObjectsCache.add(candidate);
                System.debug('Validated object (API match): ' + candidate + ' -> ' + apiName);
                return apiName;
            }
            
            for (String objectApiName : globalDescribe.keySet()) {
                try {
                    Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objectApiName).getDescribe();
                    
                    String label = objDescribe.getLabel().toLowerCase();
                    String pluralLabel = objDescribe.getLabelPlural().toLowerCase();
                    
                    if (label.equalsIgnoreCase(candidate) || pluralLabel.equalsIgnoreCase(candidate)) {
                        String apiName = objDescribe.getName();
                        objectLabelToApiNameCache.put(candidate, apiName);
                        objectLabelToApiNameCache.put(label, apiName);
                        objectLabelToApiNameCache.put(pluralLabel, apiName);
                        describedObjectsCache.add(candidate);
                        System.debug('Validated object (label match): ' + candidate + ' -> ' + apiName);
                        return apiName;
                    }
                } catch (Exception e) {
                    // Skip
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error validating candidate: ' + candidate + ' - ' + e.getMessage());
        }
        
        describedObjectsCache.add(candidate);
        return null;
    }

    /**
     * @description Load fields for a specific object
     */
    private static void loadFieldsForObject(String objectName) {
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
                        // Skip
                    }
                }
            }
            
            System.debug('Loaded ' + fieldApiNames.size() + ' fields for ' + objectName);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error loading fields for ' + objectName + ': ' + e.getMessage());
        }
        
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
     * @description Extract objects from message
     */
    private static List<String> extractObjects(String message) {
        Set<String> objects = new Set<String>();
        initializeLazyCache();
        
        System.debug('=== EXTRACTING OBJECTS (LAZY) ===');
        
        Set<String> candidates = extractObjectCandidates(message);
        
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
     * @description Extract fields LAZILY
     */
    private static List<String> extractFieldsLazy(String message, List<String> objects) {
        Set<String> fields = new Set<String>();
        String messageLower = message.toLowerCase();
        
        System.debug('=== EXTRACTING FIELDS (LAZY) ===');
        initializeLazyCache();
        
        // Method 1: Custom field pattern
        Matcher customFieldMatcher = FIELD_PATTERN.matcher(message);
        while (customFieldMatcher.find()) {
            String customField = customFieldMatcher.group(1);
            
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
        
        // Method 2: Common standard fields
        for (String commonField : COMMON_STANDARD_FIELDS) {
            if (message.containsIgnoreCase(commonField) || 
                messageLower.contains(commonField.toLowerCase())) {
                fields.add(commonField);
                System.debug('Found common field: ' + commonField);
            }
        }
        
        // Method 3: Load fields for identified objects
        if (!objects.isEmpty()) {
            for (String objectName : objects) {
                loadFieldsForObject(objectName);
                
                Map<String, String> fieldLabelToApi = fieldsPerObjectCache.get(objectName);
                
                if (fieldLabelToApi != null) {
                    List<String> words = messageLower.split('[\\s,.!?:]');
                    
                    for (Integer i = 0; i < words.size(); i++) {
                        String word = words[i].trim();
                        if (String.isBlank(word)) continue;
                        
                        if (fieldLabelToApi.containsKey(word)) {
                            String fieldApiName = fieldLabelToApi.get(word);
                            fields.add(fieldApiName);
                            System.debug('Found field by label: ' + word + ' -> ' + fieldApiName);
                        }
                        
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
        // Method 5: Enhanced field label matching (case-insensitive, underscore-tolerant)
        if (!objects.isEmpty()) {
            for (String objectName : objects) {
                loadFieldsForObject(objectName);
                
                Map<String, String> fieldLabelToApi = fieldsPerObjectCache.get(objectName);
                
                if (fieldLabelToApi != null) {
                    // Check for "issue type" → "Issue_Type__c" style matches
                    for (String fieldLabel : fieldLabelToApi.keySet()) {
                        String normalizedLabel = fieldLabel.toLowerCase().replaceAll('\\s+', '');
                        String normalizedMessage = messageLower.replaceAll('\\s+', '');
                        
                        if (normalizedMessage.contains(normalizedLabel)) {
                            String fieldApiName = fieldLabelToApi.get(fieldLabel);
                            fields.add(fieldApiName);
                            System.debug('Found field by normalized label: ' + fieldLabel + ' -> ' + fieldApiName);
                        }
                    }
                }
            }
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
     * @description Check if message is a self-reference (user asking about themselves)
     * @param message User message
     * @return Boolean indicating if this is about current user
     */
    private static Boolean isSelfReference(String message) {
        if (String.isBlank(message)) {
            return false;
        }
        
        String lowerMessage = message.toLowerCase();
        
        // Self-reference patterns
        List<String> selfPatterns = new List<String>{
            ' my ', 'my ', ' me', 'for me', 'check me',
            ' i ', 'i ', 'myself', 'current user'
        };
        
        for (String pattern : selfPatterns) {
            if (lowerMessage.contains(pattern)) {
                return true;
            }
        }
        
        // Check if no "for [name]" pattern exists
        Pattern forUserPattern = Pattern.compile('(?i)(?:for|user)\\s+([a-z]+)');
        Matcher matcher = forUserPattern.matcher(message);
        
        if (!matcher.find()) {
            // No "for someone" found - likely self-reference
            return true;
        }
        
        return false;
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