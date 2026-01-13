/**
 * @description Service for managing AI prompts for Salesforce diagnostic assistance
 * Provides optimized prompts for different diagnostic scenarios
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0
 */
public with sharing class AIPromptService {
    
    // Prompt version for tracking
    private static final String PROMPT_VERSION = '1.0';
    
    /**
     * @description Get the main system prompt for diagnostic assistance
     * This is the core prompt used for all diagnostic interactions
     * @return String containing the system prompt
     */
        public static String getMainSystemPrompt() {
                return 'You are a Salesforce diagnostic assistant helping users troubleshoot permission and access issues.\n\n' +
                    
                    '=== YOUR ROLE ===\n' +
                    '- Analyze Salesforce permission problems\n' +
                    '- Explain issues in simple, non-technical terms\n' +
                    '- Provide clear, step-by-step solutions\n' +
                    '- Be empathetic and patient with frustrated users\n' +
                    '- Never blame the user for not understanding\n\n' +
                    
                    '=== CRITICAL INSTRUCTION ===\n' +
                    'You MUST use the diagnostic results provided below. DO NOT give generic advice.\n' +
                    'If the diagnostic results show specific permission failures, state them CLEARLY and DIRECTLY.\n' +
                    'Example: "I checked your permissions and found that your profile \'Custom Standard User\' does NOT have Read permission on the Diagnostic_Session__c object."\n\n' +
                    
                    '=== RESPONSE FORMAT ===\n' +
                    '1. DIAGNOSTIC FINDINGS: State EXACTLY what the diagnostic checks found (use specific field/object names, permission states)\n' +
                    '2. EXPLAIN THE ISSUE: In one sentence, explain what this means\n' +
                    '3. WHY IT\'S HAPPENING: Simple explanation of the root cause from diagnostics\n' +
                    '4. HOW TO FIX IT: Clear, numbered steps to resolve\n' +
                    '5. WHO CAN HELP: Identify who can make this change\n' +
                    '6. NEXT STEPS: Ask if they need additional help\n\n' +
                    
                    '=== TONE GUIDELINES ===\n' +
                    '- Friendly and professional (like a helpful colleague)\n' +
                    '- Clear and concise (no unnecessary jargon)\n' +
                    '- Empathetic (acknowledge their frustration)\n' +
                    '- Confident and SPECIFIC (use the actual diagnostic data)\n' +
                    '- Patient (they may not understand technical terms)\n\n' +
                    
                    '=== TECHNICAL TERMS ===\n' +
                    'When you must use technical terms, explain them:\n' +
                    '- Field-Level Security (FLS) → "permission to view/edit specific fields"\n' +
                    '- Object Permissions → "permission to access this type of record"\n' +
                    '- Sharing Rules → "rules that control who can see records"\n' +
                    '- Profile → "your user type that determines base permissions"\n' +
                    '- Permission Set → "additional permissions added to your profile"\n\n' +
                    
                    '=== CRITICAL RULES ===\n' +
                    '- Base ALL answers on the diagnostic results provided - DO NOT speculate\n' +
                    '- If diagnostic shows "Can Read: NO" - STATE THIS CLEARLY AND DIRECTLY\n' +
                    '- If diagnostic shows "Can Edit: NO" - STATE THIS CLEARLY AND DIRECTLY\n' +
                    '- NEVER say "might" or "could be" when diagnostics show definitive results\n' +
                    '- Quote exact profile names, permission set names from diagnostic results\n' +
                    '- If diagnostic data is insufficient, say so clearly\n' +
                    '- ALWAYS provide at least one actionable next step\n' +
                    '- Keep responses under 300 words unless complexity requires more\n\n' +
                    
                    '=== RESPONSE STRUCTURE EXAMPLE ===\n' +
                    '"DIAGNOSTIC FINDINGS: I checked your permissions and found:\n' +
                    '• Profile: Custom Standard User\n' +
                    '• Object: Diagnostic_Session__c\n' +
                    '• Can Read: NO ✗\n' +
                    '• Can Create: NO ✗\n' +
                    '• Can Edit: NO ✗\n\n' +
                    'ISSUE: You cannot access Diagnostic Session records because your profile lacks Read permission.\n\n' +
                    'WHY: Object-level permissions control access to record types. Your profile \'Custom Standard User\' does not have the \'Read\' permission enabled for Diagnostic_Session__c.\n\n' +
                    'HOW TO FIX:\n' +
                    '1. Contact your Salesforce administrator\n' +
                    '2. Ask them to grant Read permission for Diagnostic_Session__c to your profile\n' +
                    '3. Alternatively, they can assign you a Permission Set with this access\n\n' +
                    'WHO CAN HELP: Your Salesforce administrator can update profile permissions in Setup → Profiles → Custom Standard User → Object Settings → Diagnostic_Session__c\n\n' +
                    'Need help with anything else?"\n\n' +
                    
                    'Version: ' + PROMPT_VERSION;
        }
    
    /**
     * @description Get prompt for field visibility issues
     * @return String containing specialized field visibility prompt
     */
    public static String getFieldVisibilityPrompt() {
        return 'CONTEXT: User cannot see a specific field.\n\n' +
               'DIAGNOSTIC FOCUS:\n' +
               '- Check if field exists (confirm not deleted/renamed)\n' +
               '- Check Field-Level Security (FLS) permissions\n' +
               '- Check if field is on page layout\n' +
               '- Check if field has data (sometimes appears blank if no data)\n\n' +
               'COMMON CAUSES:\n' +
               '1. Field-Level Security not granted (most common)\n' +
               '2. Field not on page layout\n' +
               '3. Field is hidden by Dynamic Forms\n' +
               '4. Record type has different layout\n\n' +
               'RESPONSE TEMPLATE:\n' +
               '- Identify which of the above is the cause\n' +
               '- Explain in simple terms what FLS or page layout means\n' +
               '- Provide specific steps to request access\n' +
               '- Mention who can make the change (admin)';
    }
    
    /**
     * @description Get prompt for edit permission issues
     * @return String containing specialized edit permission prompt
     */
    public static String getEditPermissionPrompt() {
        return 'CONTEXT: User cannot edit a record or field.\n\n' +
               'DIAGNOSTIC FOCUS:\n' +
               '- Check object-level edit permissions\n' +
               '- Check Field-Level Security for specific field\n' +
               '- Check if record is locked (approval process)\n' +
               '- Check record ownership and sharing rules\n' +
               '- Check if field is read-only (formula, system field)\n\n' +
               'COMMON CAUSES:\n' +
               '1. User profile lacks Edit permission on object\n' +
               '2. Field-Level Security set to read-only\n' +
               '3. Record in approval process (locked)\n' +
               '4. User doesn\'t own record and no sharing rule grants edit\n' +
               '5. Field is a formula or system field (cannot be edited)\n\n' +
               'RESPONSE TEMPLATE:\n' +
               '- Clearly identify the specific blocker\n' +
               '- Explain why they can\'t edit (approval lock is temporary, etc.)\n' +
               '- If temporary, explain when they can edit again\n' +
               '- If permanent, explain how to request permission change';
    }
    
    /**
     * @description Get prompt for record access issues
     * @return String containing specialized record access prompt
     */
    public static String getRecordAccessPrompt() {
        return 'CONTEXT: User cannot view or access specific records.\n\n' +
            'DIAGNOSTIC FOCUS:\n' +
            '- Check object-level read permissions\n' +
            '- Check record ownership\n' +
            '- Check Organization-Wide Defaults (OWD)\n' +
            '- Check sharing rules\n' +
            '- Check role hierarchy\n\n' +
            'CRITICAL: USE THE ACTUAL DIAGNOSTIC RESULTS. Do not say "might" or "could be" - state what the diagnostics FOUND.\n\n' +
            'RESPONSE TEMPLATE:\n' +
            '- Start with "DIAGNOSTIC FINDINGS:" and list what you found\n' +
            '- State EXACT permission values: Can Read: YES/NO, Can Edit: YES/NO\n' +
            '- Quote the user\'s profile name from diagnostics\n' +
            '- If diagnostics show Read=NO, say "You do NOT have Read permission" (not "you might not have")\n' +
            '- Provide the specific Setup path to fix it\n' +
            '- Example: "Your profile \'Standard User\' does NOT have Read permission on Account object. To fix: Setup → Profiles → Standard User → Object Settings → Account → Enable Read"';
    }
    
    /**
     * @description Get prompt for save error issues
     * @return String containing specialized save error prompt
     */
    public static String getSaveErrorPrompt() {
        return 'CONTEXT: User gets an error when trying to save a record.\n\n' +
               'DIAGNOSTIC FOCUS:\n' +
               '- Check for validation rules\n' +
               '- Check for required fields\n' +
               '- Check for field-level permissions\n' +
               '- Check for workflow rules/process builder\n' +
               '- Check for triggers\n\n' +
               'COMMON CAUSES:\n' +
               '1. Validation rule blocking save (most common)\n' +
               '2. Required field is empty\n' +
               '3. Field value doesn\'t meet criteria (format, range)\n' +
               '4. Duplicate rule blocking\n' +
               '5. Automated process (workflow/trigger) preventing save\n\n' +
               'RESPONSE TEMPLATE:\n' +
               '- Quote the exact error message if provided\n' +
               '- Explain what the validation rule is checking\n' +
               '- Provide specific values or changes needed\n' +
               '- If rule seems incorrect, suggest admin review';
    }
    
    /**
     * @description Get prompt for new user onboarding
     * @return String containing new user guidance prompt
     */
    public static String getNewUserPrompt() {
        return 'CONTEXT: New user unfamiliar with Salesforce concepts.\n\n' +
               'TONE ADJUSTMENTS:\n' +
               '- Extra patient and educational\n' +
               '- Define all Salesforce terms clearly\n' +
               '- Use analogies and simple comparisons\n' +
               '- Encourage questions\n' +
               '- Build confidence\n\n' +
               'EDUCATIONAL APPROACH:\n' +
               '- Explain the "why" behind permissions\n' +
               '- Teach them about profiles and permission sets\n' +
               '- Help them understand they\'re not doing anything wrong\n' +
               '- Point to training resources when appropriate\n\n' +
               'RESPONSE STYLE:\n' +
               '- "Think of profiles like job titles - they define what you can do by default"\n' +
               '- "Permission sets are like special keys - they give you extra access"\n' +
               '- "It\'s not that you made a mistake - the system is designed this way for security"';
    }
    
    /**
     * @description Build complete prompt with context
     * @param basePrompt The base system prompt
     * @param scenarioPrompt Scenario-specific guidance
     * @param diagnosticResults The results from diagnostic checks
     * @param conversationContext Recent conversation history
     * @return Complete formatted prompt
     */
    public static String buildCompletePrompt(
        String basePrompt,
        String scenarioPrompt, 
        String diagnosticResults,
        String conversationContext
    ) {
        String completePrompt = basePrompt + '\n\n';
        
        if (String.isNotBlank(scenarioPrompt)) {
            completePrompt += '=== SCENARIO GUIDANCE ===\n' + scenarioPrompt + '\n\n';
        }
        
        if (String.isNotBlank(conversationContext)) {
            completePrompt += '=== CONVERSATION CONTEXT ===\n' + conversationContext + '\n\n';
        }
        
        if (String.isNotBlank(diagnosticResults)) {
            completePrompt += '=== DIAGNOSTIC RESULTS ===\n' + diagnosticResults + '\n\n';
        }
        
        completePrompt += 'Now, respond to the user\'s current message with the guidance above.';
        
        return completePrompt;
    }
    
    /**
     * @description Format diagnostic results for AI consumption
     * @param objectName Object being diagnosed
     * @param fieldName Field being diagnosed (optional)
     * @param userId User ID being diagnosed for
     * @param diagnosticData Map of diagnostic results
     * @return Formatted string for AI
     */
    public static String formatDiagnosticResults(
        String objectName,
        String fieldName,
        Id userId,
        Map<String, Object> diagnosticData
    ) {
        String formatted = 'DIAGNOSTIC RESULTS:\n\n';
        
        formatted += 'Target: ' + objectName;
        if (String.isNotBlank(fieldName)) {
            formatted += '.' + fieldName;
        }
        formatted += '\n';
        
        formatted += 'User: ' + userId + '\n\n';
        
        // Format object permissions
        if (diagnosticData.containsKey('objectPermissions')) {
            formatted += '--- OBJECT PERMISSIONS ---\n';
            Map<String, Object> objPerms = (Map<String, Object>) diagnosticData.get('objectPermissions');
            formatted += 'Can Read: ' + objPerms.get('isAccessible') + '\n';
            formatted += 'Can Create: ' + objPerms.get('isCreateable') + '\n';
            formatted += 'Can Edit: ' + objPerms.get('isUpdateable') + '\n';
            formatted += 'Can Delete: ' + objPerms.get('isDeletable') + '\n';
            formatted += 'Profile: ' + objPerms.get('profileName') + '\n\n';
        }
        
        // Format field permissions
        if (diagnosticData.containsKey('fieldPermissions')) {
            formatted += '--- FIELD-LEVEL SECURITY ---\n';
            Map<String, Object> fieldPerms = (Map<String, Object>) diagnosticData.get('fieldPermissions');
            formatted += 'Can View: ' + fieldPerms.get('isAccessible') + '\n';
            formatted += 'Can Edit: ' + fieldPerms.get('isUpdateable') + '\n\n';
        }
        
        // Format record access
        if (diagnosticData.containsKey('recordAccess')) {
            formatted += '--- RECORD ACCESS ---\n';
            Map<String, Object> recAccess = (Map<String, Object>) diagnosticData.get('recordAccess');
            formatted += 'Can View Record: ' + recAccess.get('hasReadAccess') + '\n';
            formatted += 'Can Edit Record: ' + recAccess.get('hasEditAccess') + '\n';
            formatted += 'Can Delete Record: ' + recAccess.get('hasDeleteAccess') + '\n\n';
        }
        
        // Add summary
        formatted += '--- ANALYSIS ---\n';
        formatted += 'Use the above information to explain the issue to the user.\n';
        formatted += 'Focus on what they CAN\'T do and why.\n';
        formatted += 'Provide specific steps to resolve.';
        
        return formatted;
    }
    
    /**
     * @description Get conversation summary for context
     * @param messages List of previous messages
     * @return Formatted conversation context
     */
    public static String formatConversationContext(List<Map<String, String>> messages) {
        if (messages == null || messages.isEmpty()) {
            return '';
        }
        
        String context = 'RECENT CONVERSATION:\n\n';
        
        // Include last 3-5 messages for context
        Integer startIndex = Math.max(0, messages.size() - 5);
        
        for (Integer i = startIndex; i < messages.size(); i++) {
            Map<String, String> msg = messages[i];
            String role = msg.get('role');
            String content = msg.get('content');
            
            if (role == 'user') {
                context += 'User: ' + content + '\n\n';
            } else if (role == 'assistant') {
                context += 'Assistant: ' + content + '\n\n';
            }
        }
        
        return context;
    }
    
    /**
     * @description Determine appropriate scenario prompt based on issue type
     * @param issueType Type of issue (field_visibility, edit_permission, etc.)
     * @return Scenario-specific prompt
     */
    public static String getScenarioPrompt(String issueType) {
        if (String.isBlank(issueType)) {
            return '';
        }
        
        switch on issueType.toLowerCase() {
            when 'field_visibility' {
                return getFieldVisibilityPrompt();
            }
            when 'edit_permission' {
                return getEditPermissionPrompt();
            }
            when 'record_access', 'access_issue' {
                return getRecordAccessPrompt();
            }
            when 'save_error', 'validation_error' {
                return getSaveErrorPrompt();
            }
            when 'new_user' {
                return getNewUserPrompt();
            }
            when else {
                return '';
            }
        }
    }
    
    /**
     * @description Validate prompt length to stay within token limits
     * @param prompt The prompt to validate
     * @return Boolean indicating if prompt is within limits
     */
    public static Boolean validatePromptLength(String prompt) {
        if (String.isBlank(prompt)) {
            return false;
        }
        
        // Rough estimate: 1 token ≈ 4 characters
        // Target: < 2000 tokens = < 8000 characters
        Integer maxCharacters = 8000;
        
        if (prompt.length() > maxCharacters) {
            System.debug(LoggingLevel.WARN, 'Prompt exceeds recommended length: ' + 
                        prompt.length() + ' characters (limit: ' + maxCharacters + ')');
            return false;
        }
        
        return true;
    }
    
    /**
     * @description Get prompt version for tracking and documentation
     * @return Current prompt version
     */
    public static String getPromptVersion() {
        return PROMPT_VERSION;
    }
    
    /**
     * @description Log prompt usage for analytics (future enhancement)
     * @param promptType Type of prompt used
     * @param issueType Type of issue
     * @param tokensUsed Number of tokens consumed
     */
    public static void logPromptUsage(String promptType, String issueType, Integer tokensUsed) {
        // Placeholder for future analytics implementation
        System.debug('Prompt Usage: Type=' + promptType + 
                    ', Issue=' + issueType + 
                    ', Tokens=' + tokensUsed);
    }
}