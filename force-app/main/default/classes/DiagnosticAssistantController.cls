/**
 * @description Main Apex controller for the Diagnostic Assistant Lightning Web Component.
 *              Orchestrates the entire diagnostic flow using all integrated services.
 *              Now supports ADMIN MODE - System Admins can diagnose for any user
 * @author Salesforce Diagnostic Assistant Team
 * @date 2026-01-21
 * @version 2.1 - Admin Mode Support
 */
public with sharing class DiagnosticAssistantController {
    
    /**
     * @description Main entry point for processing user messages from the LWC
     * SUPPORTS ADMIN MODE: Detects target user from query
     * @param message The user's message/question
     * @param sessionId Existing session ID or null for new session
     * @return ResponseWrapper containing AI response and session info
     */
    @AuraEnabled
    public static ResponseWrapper processUserMessage(String message, String sessionId) {
        ResponseWrapper response = new ResponseWrapper();
        Long startTime = System.currentTimeMillis();
        
        try {
            System.debug('=== Processing User Message ===');
            System.debug('Message: ' + message);
            System.debug('Session ID: ' + sessionId);
            System.debug('Current User ID: ' + UserInfo.getUserId());
            
            // Layer 1: Input Validation
            if (!validateInput(message, response)) {
                return response;
            }
            
            // Layer 2: Message Analysis (Using MessageAnalyzer)
            MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
            System.debug('Message Analysis: Category=' + analysis.issueCategory + 
                        ', Confidence=' + analysis.confidence);
            
            // Layer 2.5: Determine target user (ADMIN MODE SUPPORT)
            Id targetUserId = determineTargetUser(analysis);
            Id currentUserId = UserInfo.getUserId();
            System.debug('Target User ID: ' + targetUserId);
            System.debug('Is Admin Diagnostic: ' + (targetUserId != currentUserId));
            
            // Layer 3: Run Diagnostics FIRST (before any DML)
            DiagnosticReportBuilder.DiagnosticReport diagnosticReport = 
                runComprehensiveDiagnostics(analysis, targetUserId);
            
            // Convert to diagnostic steps for UI
            response.steps = buildDiagnosticSteps(diagnosticReport);
            
            // Layer 4: Build AI Context (no DML here)
            String conversationContext = '';
            if (String.isNotBlank(sessionId)) {
                try {
                    ConversationManager.ConversationContext existingContext = 
                        ConversationManager.getContext(sessionId);
                    conversationContext = existingContext.formattedContext;
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Could not retrieve context: ' + e.getMessage());
                }
            }
            
            String aiContext = buildAIContextWithoutSession(analysis, conversationContext, diagnosticReport);
            
            // Layer 5: Call Groq AI (BEFORE any DML operations)
            GroqAPIService.APIResponse apiResponse = callGroqAI(message, analysis, aiContext);
            
            String aiResponseContent = '';
            
            if (apiResponse.success) {
                // Layer 6: Parse AI Response
                AIResponseParser.ParsedResponse parsedResponse = 
                    AIResponseParser.parseResponse(apiResponse.content);
                
                aiResponseContent = parsedResponse.formattedContent;
                response.message = parsedResponse.formattedContent;
                response.success = true;
                response.fallback = false;
                
                System.debug('Response Quality: ' + parsedResponse.quality.qualityScore);
                
            } else {
                // API failed - use fallback with diagnostic report
                System.debug(LoggingLevel.WARN, 'AI API failed: ' + apiResponse.errorMessage);
                aiResponseContent = generateIntelligentFallback(diagnosticReport);
                response.message = aiResponseContent;
                response.success = true;
                response.fallback = true;
            }
            
            // Layer 7: NOW do all DML operations (after callout is complete)
            ConversationManager.ConversationContext context;
            if (String.isNotBlank(sessionId)) {
                context = ConversationManager.addMessage(sessionId, 'user', message);
                context = ConversationManager.addMessage(sessionId, 'assistant', aiResponseContent);
            } else {
                context = ConversationManager.addMessage(null, 'user', message);
                context = ConversationManager.addMessage(context.sessionId, 'assistant', aiResponseContent);
                sessionId = context.sessionId;
            }
            response.sessionId = sessionId;
            
            // Update diagnostic results in session
            ConversationManager.updateDiagnosticResult(
                sessionId, 
                diagnosticReport.plainTextReport
            );
            
            Long endTime = System.currentTimeMillis();
            System.debug('Total processing time: ' + (endTime - startTime) + 'ms');
            
        } catch (CalloutException e) {
            System.debug(LoggingLevel.ERROR, 'API Callout failed: ' + e.getMessage());
            response.message = 'I am having trouble connecting right now. Please try again in a moment.';
            response.success = true;
            response.fallback = true;
            logError('API Callout', e);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Unexpected error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            response.success = false;
            response.error = 'An unexpected error occurred. Please try again or contact your administrator.';
            logError('Unexpected', e);
        }
        
        return response;
    }
    
    /**
     * @description Determine which user to diagnose (ADMIN MODE SUPPORT)
     * @param analysis Message analysis with potential target user info
     * @return User ID to diagnose for
     */
    private static Id determineTargetUser(MessageAnalyzer.MessageAnalysis analysis) {
        Id currentUserId = UserInfo.getUserId();
        
        // If no target user mentioned, use current user
        if (analysis.targetUserId == null && 
            String.isBlank(analysis.targetUserName) && 
            String.isBlank(analysis.targetUserEmail)) {
            System.debug('No target user detected - using current user');
            return currentUserId;
        }
        
        // Check if current user is System Admin
        if (!isSystemAdmin()) {
            System.debug('Non-admin user - ignoring target user, using current user');
            return currentUserId;
        }
        
        // Admin is diagnosing for another user - resolve the user ID
        return resolveTargetUserId(analysis);
    }
    
    /**
     * @description Check if current user is System Administrator
     * @return Boolean indicating if user is System Admin
     */
    private static Boolean isSystemAdmin() {
        try {
            User currentUser = [
                SELECT Profile.Name 
                FROM User 
                WHERE Id = :UserInfo.getUserId() 
                LIMIT 1
            ];
            
            Boolean isAdmin = currentUser.Profile.Name == 'System Administrator';
            System.debug('Current user is System Admin: ' + isAdmin);
            return isAdmin;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking admin status: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Resolve target user ID from analysis (name, email, or direct ID)
     * @param analysis Message analysis containing target user hints
     * @return Resolved user ID (or current user if resolution fails)
     */
    private static Id resolveTargetUserId(MessageAnalyzer.MessageAnalysis analysis) {
        Id currentUserId = UserInfo.getUserId();
        
        try {
            // Priority 1: Direct User ID provided
            if (analysis.targetUserId != null) {
                List<User> users = [
                    SELECT Id, Name, Email 
                    FROM User 
                    WHERE Id = :analysis.targetUserId 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    System.debug('Resolved target user by ID: ' + users[0].Name);
                    return users[0].Id;
                }
            }
            
            // Priority 2: Email address
            if (String.isNotBlank(analysis.targetUserEmail)) {
                List<User> users = [
                    SELECT Id, Name, Email 
                    FROM User 
                    WHERE Email = :analysis.targetUserEmail 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    System.debug('Resolved target user by email: ' + users[0].Name + ' (' + users[0].Email + ')');
                    return users[0].Id;
                } else {
                    System.debug('No active user found with email: ' + analysis.targetUserEmail);
                }
            }
            
            // Priority 3: User name (exact or partial match)
            if (String.isNotBlank(analysis.targetUserName)) {
                // Try exact match first
                List<User> users = [
                    SELECT Id, Name, Email 
                    FROM User 
                    WHERE Name = :analysis.targetUserName 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    System.debug('Resolved target user by exact name: ' + users[0].Name);
                    return users[0].Id;
                }
                
                // Try partial match (LIKE)
                String likePattern = '%' + analysis.targetUserName + '%';
                users = [
                    SELECT Id, Name, Email 
                    FROM User 
                    WHERE Name LIKE :likePattern 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    System.debug('Resolved target user by partial name: ' + users[0].Name);
                    return users[0].Id;
                } else {
                    System.debug('No active user found with name: ' + analysis.targetUserName);
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error resolving target user: ' + e.getMessage());
        }
        
        // Fallback: Current user
        System.debug('Could not resolve target user - using current user');
        return currentUserId;
    }
    
    /**
     * @description Validates user input
     */
    private static Boolean validateInput(String message, ResponseWrapper response) {
        if (String.isBlank(message)) {
            response.success = false;
            response.error = 'Message cannot be empty. Please describe your issue.';
            return false;
        }
        
        if (message.length() > 5000) {
            response.success = false;
            response.error = 'Message is too long (max 5000 characters). Please shorten your message.';
            return false;
        }
        
        return true;
    }
    
    /**
     * @description Run comprehensive diagnostics
     * NOW ACCEPTS targetUserId instead of always using current user
     */
    private static DiagnosticReportBuilder.DiagnosticReport runComprehensiveDiagnostics(
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId
    ) {
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(userId);
        
        System.debug('=== RUNNING DIAGNOSTICS FOR USER: ' + userId + ' ===');
        System.debug('Objects involved: ' + analysis.objectsInvolved);
        System.debug('Diagnostics needed: ' + String.join(analysis.diagnosticsNeeded, ', '));
        
        try {
            for (String diagnostic : analysis.diagnosticsNeeded) {
                
                if (diagnostic == 'checkObjectPermissions' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        System.debug('>>> Checking object permissions for: ' + objectName);
                        runObjectPermissionCheck(objectName, userId, report);
                    }
                }
                
                if (diagnostic == 'checkFieldSecurity' && !analysis.fieldsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        for (String fieldName : analysis.fieldsInvolved) {
                            runFieldSecurityCheck(objectName, fieldName, userId, report);
                        }
                    }
                }
                
                if (diagnostic == 'checkRecordAccess' && !analysis.recordIds.isEmpty()) {
                    for (String recordId : analysis.recordIds) {
                        runRecordAccessCheck(recordId, userId, report);
                    }
                }
                
                if (diagnostic == 'checkPageLayout' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        runPageLayoutCheck(objectName, report);
                    }
                }
                
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error during diagnostics: ' + e.getMessage());
        }
        
        DiagnosticReportBuilder.finalizeReport(report);
        
        System.debug('Diagnostic report completed with ' + report.findings.size() + ' findings');
        System.debug('=== DIAGNOSTIC REPORT ===');
        System.debug(report.plainTextReport);
        return report;
    }
    
    // NOTE: The rest of the methods remain UNCHANGED from your original file
    // I'm including them here for completeness
    
    private static void runObjectPermissionCheck(
        String objectName, 
        Id userId, 
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        if (!MetadataQueryService.checkObjectExists(objectName)) {
            DiagnosticReportBuilder.addObjectExistenceFinding(report, objectName, false);
            return;
        }
        
        DiagnosticReportBuilder.addObjectExistenceFinding(report, objectName, true);
        
        SalesforceDiagnosticService.ObjectPermissionResult permResult = 
            SalesforceDiagnosticService.checkObjectPermissions(objectName, userId);
        
        DiagnosticReportBuilder.addObjectPermissionFinding(report, objectName, permResult);
    }
    
    private static void runFieldSecurityCheck(
        String objectName,
        String fieldName,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        if (!MetadataQueryService.checkFieldExists(objectName, fieldName)) {
            DiagnosticReportBuilder.addFieldExistenceFinding(report, objectName, fieldName, false);
            return;
        }
        
        DiagnosticReportBuilder.addFieldExistenceFinding(report, objectName, fieldName, true);
        
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            SalesforceDiagnosticService.checkFieldLevelSecurity(objectName, fieldName, userId);
        
        DiagnosticReportBuilder.addFieldSecurityFinding(report, objectName, fieldName, fieldResult);
    }
    
    private static void runRecordAccessCheck(
        String recordId,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        SalesforceDiagnosticService.RecordAccess recordAccess = 
            SalesforceDiagnosticService.checkRecordAccess(recordId, userId);
        
        DiagnosticReportBuilder.addRecordAccessFinding(report, recordId, recordAccess);
    }
    
    private static void runPageLayoutCheck(
        String objectName,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        List<String> layoutFields = MetadataQueryService.getPageLayoutFields(objectName, null);
        
        DiagnosticReportBuilder.DiagnosticFinding finding = 
            new DiagnosticReportBuilder.DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Page Layout';
        finding.title = 'Accessible Fields on ' + objectName;
        finding.status = 'PASS';
        finding.statusIcon = '✓';
        finding.severity = DiagnosticReportBuilder.Severity.INFO;
        finding.details.add('Found ' + layoutFields.size() + ' accessible fields');
        
        if (!layoutFields.isEmpty()) {
            Integer count = Math.min(5, layoutFields.size());
            List<String> sampleFields = new List<String>();
            for (Integer i = 0; i < count; i++) {
                sampleFields.add(layoutFields[i]);
            }
            finding.details.add('Sample fields: ' + String.join(sampleFields, ', '));
            if (layoutFields.size() > 5) {
                finding.details.add('... and ' + (layoutFields.size() - 5) + ' more');
            }
        }
        
        report.findings.add(finding);
    }
    
    private static String buildAIContextWithoutSession(
        MessageAnalyzer.MessageAnalysis analysis,
        String conversationContext,
        DiagnosticReportBuilder.DiagnosticReport diagnosticReport
    ) {
        String systemPrompt = AIPromptService.getMainSystemPrompt();
        String scenarioPrompt = AIPromptService.getScenarioPrompt(analysis.issueCategory);
        String diagnosticResults = diagnosticReport.plainTextReport;
        
        String completeContext = AIPromptService.buildCompletePrompt(
            systemPrompt,
            scenarioPrompt,
            diagnosticResults,
            conversationContext
        );
        
        if (!AIPromptService.validatePromptLength(completeContext)) {
            System.debug(LoggingLevel.WARN, 'Prompt exceeds recommended length, truncating...');
            completeContext = AIPromptService.buildCompletePrompt(
                systemPrompt,
                scenarioPrompt,
                diagnosticResults,
                ''
            );
        }
        
        System.debug('=== AI CONTEXT BEING SENT ===');
        System.debug(completeContext);        
        return completeContext;
    }
    
    private static GroqAPIService.APIResponse callGroqAI(
        String userMessage,
        MessageAnalyzer.MessageAnalysis analysis,
        String context
    ) {
        String systemPrompt = AIPromptService.getMainSystemPrompt();
        
        if (String.isNotBlank(analysis.issueCategory)) {
            systemPrompt += '\n\n' + AIPromptService.getScenarioPrompt(analysis.issueCategory);
        }
        
        GroqAPIService.APIResponse response = GroqAPIService.sendMessageWithContext(
            userMessage,
            systemPrompt,
            context
        );
        
        if (response.success && response.tokensUsed != null) {
            System.debug('AI Response Success - Tokens used: ' + response.tokensUsed);
            
            AIPromptService.logPromptUsage(
                'diagnostic_assistant',
                analysis.issueCategory,
                response.tokensUsed
            );
        } else if (!response.success) {
            System.debug(LoggingLevel.ERROR, 'AI Response Failed: ' + response.errorMessage);
        }
        
        return response;
    }
    
    private static String generateIntelligentFallback(
        DiagnosticReportBuilder.DiagnosticReport diagnosticReport
    ) {
        StringBuilder fallback = new StringBuilder();
        
        fallback.append('I am having trouble connecting to my AI service, but I have completed ');
        fallback.append('diagnostic checks for you.\n\n');
        
        if (diagnosticReport != null && diagnosticReport.summary != null) {
            fallback.append('**What I Found:**\n');
            fallback.append(diagnosticReport.summary.rootCause + '\n\n');
            
            if (!diagnosticReport.summary.suggestedActions.isEmpty()) {
                fallback.append('**What to Do:**\n');
                Integer actionNum = 1;
                for (String action : diagnosticReport.summary.suggestedActions) {
                    fallback.append(actionNum + '. ' + action + '\n');
                    actionNum++;
                    if (actionNum > 3) break;
                }
                fallback.append('\n');
            }
            
            if (!diagnosticReport.summary.whoCanHelp.isEmpty()) {
                fallback.append('**Who Can Help:**\n');
                for (String contact : diagnosticReport.summary.whoCanHelp) {
                    fallback.append('• ' + contact + '\n');
                }
                fallback.append('\n');
            }
            
            fallback.append(diagnosticReport.summary.nextSteps);
        } else {
            fallback.append('**Common Solutions:**\n');
            fallback.append('• Check Field-Level Security settings\n');
            fallback.append('• Verify Object permissions in your profile\n');
            fallback.append('• Contact your Salesforce administrator\n\n');
            fallback.append('Please try again in a moment for AI-powered assistance.');
        }
        
        return fallback.toString();
    }
    
    private static List<DiagnosticStep> buildDiagnosticSteps(
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        List<DiagnosticStep> steps = new List<DiagnosticStep>();
        
        if (report == null || report.findings == null) {
            return steps;
        }
        
        for (DiagnosticReportBuilder.DiagnosticFinding finding : report.findings) {
            DiagnosticStep step = new DiagnosticStep();
            step.name = finding.title;
            step.status = finding.status.toLowerCase();
            step.details = String.join(finding.details, '\n');
            steps.add(step);
        }
        
        return steps;
    }
    
    private static void logError(String context, Exception e) {
        System.debug(LoggingLevel.ERROR, context + ' Error: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
    }
    
    // Inner classes
    public class ResponseWrapper {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String sessionId;
        @AuraEnabled public String error;
        @AuraEnabled public Boolean fallback;
        @AuraEnabled public List<DiagnosticStep> steps;
        
        public ResponseWrapper() {
            this.success = false;
            this.fallback = false;
            this.steps = new List<DiagnosticStep>();
        }
    }
    
    public class DiagnosticStep {
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String details;
    }
    
    private class StringBuilder {
        private List<String> parts = new List<String>();
        
        public void append(String text) {
            parts.add(text);
        }
        
        public override String toString() {
            return String.join(parts, '');
        }
    }
    
    // Utility methods
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSessionStats(String sessionId) {
        try {
            return ConversationManager.getConversationStats(sessionId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting session stats: ' + e.getMessage());
            return new Map<String, Object>{ 'error' => e.getMessage() };
        }
    }
    
    @AuraEnabled
    public static void clearSession(String sessionId) {
        try {
            ConversationManager.clearHistory(sessionId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error clearing session: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static Boolean testAPIConnection() {
        return GroqAPIService.testConnection();
    }
}