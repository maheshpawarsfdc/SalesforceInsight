/**
 * @description Main Apex controller for the Diagnostic Assistant Lightning Web Component.
 *              Orchestrates the entire diagnostic flow using all integrated services.
 *              Now properly integrated with all backend services for maximum capability.
 * @author Salesforce Diagnostic Assistant Team
 * @date 2025-01-09
 * @version 2.0 (Fully Integrated)
 * @group AI Integration
 */
public with sharing class DiagnosticAssistantController {
    
    /**
     * @description Main entry point for processing user messages from the LWC
     * FIXED: Reordered to avoid DML before callout error
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
            
            // Layer 1: Input Validation
            if (!validateInput(message, response)) {
                return response;
            }
            
            // Layer 2: Message Analysis (Using MessageAnalyzer)
            MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
            System.debug('Message Analysis: Category=' + analysis.issueCategory + 
                        ', Confidence=' + analysis.confidence);
            
            // Layer 3: Run Diagnostics FIRST (before any DML)
            // This doesn't involve DML, just queries
            DiagnosticReportBuilder.DiagnosticReport diagnosticReport = 
                runComprehensiveDiagnostics(analysis, UserInfo.getUserId());
            
            // Convert to diagnostic steps for UI
            response.steps = buildDiagnosticSteps(diagnosticReport);
            
            // Layer 4: Build AI Context (no DML here)
            // Need to handle session context WITHOUT creating/updating session yet
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
                // Layer 6: Parse AI Response (Using AIResponseParser)
                AIResponseParser.ParsedResponse parsedResponse = 
                    AIResponseParser.parseResponse(apiResponse.content);
                
                aiResponseContent = parsedResponse.formattedContent;
                response.message = parsedResponse.formattedContent;
                response.success = true;
                response.fallback = false;
                
                // Log response quality
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
            // Update conversation and session
            ConversationManager.ConversationContext context;
            if (String.isNotBlank(sessionId)) {
                context = ConversationManager.addMessage(sessionId, 'user', message);
                context = ConversationManager.addMessage(sessionId, 'assistant', aiResponseContent);
            } else {
                // Create new session
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
            response.message = 'I\'m having trouble connecting right now. Please try again in a moment.';
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
     * @description Validates user input
     * @param message User's message
     * @param response Response object to populate with errors
     * @return Boolean indicating if validation passed
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
     * @description Initialize a new conversation session
     * @param firstMessage First user message
     * @return ConversationContext with new session
     */
    private static ConversationManager.ConversationContext initializeNewSession(String firstMessage) {
        // ConversationManager will create session internally
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', firstMessage);
        
        System.debug('New session created: ' + context.sessionId);
        return context;
    }
    
    /**
     * @description Run comprehensive diagnostics using all diagnostic services
     * @param analysis Message analysis result
     * @param userId User to diagnose for
     * @return Complete diagnostic report
     */
    private static DiagnosticReportBuilder.DiagnosticReport runComprehensiveDiagnostics(
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId
    ) {
        // Create new diagnostic report
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(userId);
        System.debug('=== RUNNING DIAGNOSTICS ===');
        System.debug('Objects involved: ' + analysis.objectsInvolved);
        System.debug('Diagnostics needed: ' + String.join(analysis.diagnosticsNeeded, ', '));
        //System.debug('Running diagnostics: ' + String.join(analysis.diagnosticsNeeded, ', '));
        
        try {
            // Run diagnostics based on what MessageAnalyzer determined we need
            for (String diagnostic : analysis.diagnosticsNeeded) {
                
                // Object existence and permissions
                if (diagnostic == 'checkObjectPermissions' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        System.debug('>>> Checking object permissions for: ' + objectName);
                        runObjectPermissionCheck(objectName, userId, report);
                    }
                }
                
                // Field existence and security
                if (diagnostic == 'checkFieldSecurity' && !analysis.fieldsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        for (String fieldName : analysis.fieldsInvolved) {
                            runFieldSecurityCheck(objectName, fieldName, userId, report);
                        }
                    }
                }
                
                // Record access
                if (diagnostic == 'checkRecordAccess' && !analysis.recordIds.isEmpty()) {
                    for (String recordId : analysis.recordIds) {
                        runRecordAccessCheck(recordId, userId, report);
                    }
                }
                
                // Page layout check (simplified)
                if (diagnostic == 'checkPageLayout' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        runPageLayoutCheck(objectName, report);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error during diagnostics: ' + e.getMessage());
        }
        
        // Finalize the report (generates summary and formatted output)
        DiagnosticReportBuilder.finalizeReport(report);
        
        System.debug('Diagnostic report completed with ' + report.findings.size() + ' findings');
        System.debug('=== DIAGNOSTIC REPORT ===');
        System.debug(report.plainTextReport);
        return report;
    }
    
    /**
     * @description Run object permission check using SalesforceDiagnosticService
     */
    private static void runObjectPermissionCheck(
        String objectName, 
        Id userId, 
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        // First check if object exists
        if (!MetadataQueryService.checkObjectExists(objectName)) {
            DiagnosticReportBuilder.addObjectExistenceFinding(report, objectName, false);
            return;
        }
        
        DiagnosticReportBuilder.addObjectExistenceFinding(report, objectName, true);
        
        // Check permissions using SalesforceDiagnosticService
        SalesforceDiagnosticService.ObjectPermissionResult permResult = 
            SalesforceDiagnosticService.checkObjectPermissions(objectName, userId);
        
        DiagnosticReportBuilder.addObjectPermissionFinding(report, objectName, permResult);
    }
    
    /**
     * @description Run field security check using SalesforceDiagnosticService
     */
    private static void runFieldSecurityCheck(
        String objectName,
        String fieldName,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        // First check if field exists
        if (!MetadataQueryService.checkFieldExists(objectName, fieldName)) {
            DiagnosticReportBuilder.addFieldExistenceFinding(report, objectName, fieldName, false);
            return;
        }
        
        DiagnosticReportBuilder.addFieldExistenceFinding(report, objectName, fieldName, true);
        
        // Check field-level security using SalesforceDiagnosticService
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            SalesforceDiagnosticService.checkFieldLevelSecurity(objectName, fieldName, userId);
        
        DiagnosticReportBuilder.addFieldSecurityFinding(report, objectName, fieldName, fieldResult);
    }
    
    /**
     * @description Run record access check using SalesforceDiagnosticService
     */
    private static void runRecordAccessCheck(
        String recordId,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        SalesforceDiagnosticService.RecordAccess recordAccess = 
            SalesforceDiagnosticService.checkRecordAccess(recordId, userId);
        
        DiagnosticReportBuilder.addRecordAccessFinding(report, recordId, recordAccess);
    }
    
    /**
     * @description Run page layout check (simplified - checks which fields are accessible)
     */
    private static void runPageLayoutCheck(
        String objectName,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        // Get accessible fields on the layout
        List<String> layoutFields = MetadataQueryService.getPageLayoutFields(objectName, null);
        
        // Add informational finding
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
            // Show first few fields as examples
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
    
    /**
     * @description Build AI context without creating/updating session
     * Used to avoid DML before callout
     */
    private static String buildAIContextWithoutSession(
        MessageAnalyzer.MessageAnalysis analysis,
        String conversationContext,
        DiagnosticReportBuilder.DiagnosticReport diagnosticReport
    ) {
        // Get base system prompt
        String systemPrompt = AIPromptService.getMainSystemPrompt();
        
        // Get scenario-specific prompt based on issue type
        String scenarioPrompt = AIPromptService.getScenarioPrompt(analysis.issueCategory);
        
        // Format diagnostic results
        String diagnosticResults = diagnosticReport.plainTextReport;
        
        // Build complete prompt using AIPromptService
        String completeContext = AIPromptService.buildCompletePrompt(
            systemPrompt,
            scenarioPrompt,
            diagnosticResults,
            conversationContext
        );
        
        // Validate prompt length
        if (!AIPromptService.validatePromptLength(completeContext)) {
            System.debug(LoggingLevel.WARN, 'Prompt exceeds recommended length, truncating...');
            // Truncate conversation context if needed
            completeContext = AIPromptService.buildCompletePrompt(
                systemPrompt,
                scenarioPrompt,
                diagnosticResults,
                '' // Remove conversation context to save tokens
            );
        }
        
            System.debug('=== AI CONTEXT BEING SENT ===');
            System.debug(completeContext);        
        return completeContext;
    }
    
    /**
     * @description Call Groq AI with proper error handling
     * Note: Must be called BEFORE any DML operations to avoid callout-after-DML error
     */
    private static GroqAPIService.APIResponse callGroqAI(
        String userMessage,
        MessageAnalyzer.MessageAnalysis analysis,
        String context
    ) {
        // Build system prompt specific to the issue
        String systemPrompt = AIPromptService.getMainSystemPrompt();
        
        // Add scenario-specific guidance
        if (String.isNotBlank(analysis.issueCategory)) {
            systemPrompt += '\n\n' + AIPromptService.getScenarioPrompt(analysis.issueCategory);
        }
        
        // Call Groq API using GroqAPIService
        GroqAPIService.APIResponse response = GroqAPIService.sendMessageWithContext(
            userMessage,
            systemPrompt,
            context
        );
        
        // Log token usage if available
        if (response.success && response.tokensUsed != null) {
            System.debug('AI Response Success - Tokens used: ' + response.tokensUsed);
            
            // Log for analytics (using AIPromptService)
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
    
    /**
     * @description Generate intelligent fallback response when AI is unavailable
     * Uses diagnostic report to provide meaningful response
     */
    private static String generateIntelligentFallback(
        DiagnosticReportBuilder.DiagnosticReport diagnosticReport
    ) {
        StringBuilder fallback = new StringBuilder();
        
        fallback.append('I\'m having trouble connecting to my AI service, but I\'ve completed ');
        fallback.append('diagnostic checks for you.\n\n');
        
        // Add summary from diagnostic report
        if (diagnosticReport != null && diagnosticReport.summary != null) {
            fallback.append('**What I Found:**\n');
            fallback.append(diagnosticReport.summary.rootCause + '\n\n');
            
            // Add suggested actions
            if (!diagnosticReport.summary.suggestedActions.isEmpty()) {
                fallback.append('**What to Do:**\n');
                Integer actionNum = 1;
                for (String action : diagnosticReport.summary.suggestedActions) {
                    fallback.append(actionNum + '. ' + action + '\n');
                    actionNum++;
                    if (actionNum > 3) break; // Limit to top 3 actions
                }
                fallback.append('\n');
            }
            
            // Add who can help
            if (!diagnosticReport.summary.whoCanHelp.isEmpty()) {
                fallback.append('**Who Can Help:**\n');
                for (String contact : diagnosticReport.summary.whoCanHelp) {
                    fallback.append('• ' + contact + '\n');
                }
                fallback.append('\n');
            }
            
            fallback.append(diagnosticReport.summary.nextSteps);
        } else {
            // Generic fallback if no diagnostic report
            fallback.append('**Common Solutions:**\n');
            fallback.append('• Check Field-Level Security settings\n');
            fallback.append('• Verify Object permissions in your profile\n');
            fallback.append('• Contact your Salesforce administrator\n\n');
            fallback.append('Please try again in a moment for AI-powered assistance.');
        }
        
        return fallback.toString();
    }
    
    /**
     * @description Convert diagnostic report to UI-friendly steps
     */
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
            step.status = finding.status.toLowerCase(); // PASS -> pass, FAIL -> fail
            step.details = String.join(finding.details, '\n');
            steps.add(step);
        }
        
        return steps;
    }
    
    /**
     * @description Log errors for monitoring
     */
    private static void logError(String context, Exception e) {
        System.debug(LoggingLevel.ERROR, context + ' Error: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
        
        // In production, you might want to create error records or send to monitoring service
    }
    
    // ==================== INNER CLASSES ====================
    
    /**
     * @description Response wrapper for LWC
     */
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
    
    /**
     * @description Diagnostic step for UI progress display
     */
    public class DiagnosticStep {
        @AuraEnabled public String name;
        @AuraEnabled public String status; // pass, fail, warning, pending
        @AuraEnabled public String details;
    }
    
    /**
     * @description Simple StringBuilder helper
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
    
    // ==================== UTILITY METHODS ====================
    
    /**
     * @description Get conversation statistics for a session
     * @param sessionId Session ID
     * @return Map with statistics
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSessionStats(String sessionId) {
        try {
            return ConversationManager.getConversationStats(sessionId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting session stats: ' + e.getMessage());
            return new Map<String, Object>{ 'error' => e.getMessage() };
        }
    }
    
    /**
     * @description Clear conversation history (for testing or user request)
     * @param sessionId Session ID
     */
    @AuraEnabled
    public static void clearSession(String sessionId) {
        try {
            ConversationManager.clearHistory(sessionId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error clearing session: ' + e.getMessage());
        }
    }
    
    /**
     * @description Test API connectivity
     * @return Boolean indicating if API is accessible
     */
    @AuraEnabled(cacheable=false)
    public static Boolean testAPIConnection() {
        return GroqAPIService.testConnection();
    }
}