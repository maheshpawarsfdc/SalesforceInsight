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
            Id targetUserId = determineTargetUser(analysis, response);

            // If validation failed, response.error is already set
            if (targetUserId == null) {
                System.debug('❌ Target user validation failed - returning error');
                return response; // Return error response
            }
        
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
     * NOW VALIDATES USER EXISTS BEFORE PROCEEDING
     * @param analysis Message analysis with potential target user info
     * @param response Response wrapper to populate with errors if needed
     * @return User ID to diagnose for, or null if validation failed
     */
    private static Id determineTargetUser(
        MessageAnalyzer.MessageAnalysis analysis, 
        ResponseWrapper response
    ) {
        Id currentUserId = UserInfo.getUserId();
        
        // Check if current user is System Admin
        Boolean isAdmin = isSystemAdmin();
        
        System.debug('=== DETERMINING TARGET USER ===');
        System.debug('Current User: ' + currentUserId);
        System.debug('Is Admin: ' + isAdmin);
        System.debug('Target User ID: ' + analysis.targetUserId);
        System.debug('Target User Name: ' + analysis.targetUserName);
        System.debug('Target User Email: ' + analysis.targetUserEmail);
        
        // Validate the target user
        UserValidationResult validation = validateTargetUser(analysis);
        
        if (!validation.isValid) {
            // Validation failed - return error to user
            response.success = false;
            response.error = validation.errorMessage;
            
            if (!validation.ambiguousUsers.isEmpty()) {
                response.error += '\n\nMatching users:\n';
                for (String user : validation.ambiguousUsers) {
                    response.error += '• ' + user + '\n';
                }
            }
            
            System.debug('❌ User validation failed: ' + validation.errorMessage);
            return null;
        }
        
        // Validation passed
        if (validation.isCurrentUser) {
            System.debug('✅ Diagnosing current user: ' + validation.userName);
            return validation.userId;
        }
        
        // User is trying to diagnose someone else
        if (!isAdmin) {
            response.success = false;
            response.error = 'Only System Administrators can diagnose permissions for other users. ' +
                            'You tried to diagnose: ' + validation.userName + ' (' + validation.userEmail + ')';
            System.debug('❌ Non-admin tried to diagnose another user');
            return null;
        }
        
        // Admin diagnosing another user - all validated
        System.debug('✅ Admin diagnosing another user: ' + validation.userName);
        return validation.userId;
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

                        runSharingAnalysisCheck(recordId, userId, report);
                    }
                }
                
                if (diagnostic == 'checkPageLayout' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        // Check SPECIFIC field if mentioned
                        if (!analysis.fieldsInvolved.isEmpty()) {
                            for (String fieldName : analysis.fieldsInvolved) {
                                runPageLayoutCheck(objectName, fieldName, report);
                            }
                        } else {
                            // No specific field - general layout info
                            runPageLayoutCheck(objectName, null, report);
                        }
                    }
                }
                // NEW: Check validation rules if save error
                if (diagnostic == 'checkValidationRules' && !analysis.objectsInvolved.isEmpty()) {
                    for (String objectName : analysis.objectsInvolved) {
                        runValidationRuleCheck(objectName, report);
                    }
                }
        }
        if (analysis.issueCategory == 'field_visibility' && 
            !analysis.objectsInvolved.isEmpty() && 
            !analysis.fieldsInvolved.isEmpty()) {
            
            performRootCauseAnalysis(
                analysis.objectsInvolved[0],
                analysis.fieldsInvolved[0],
                userId,
                report
            );
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

    
    /**
     * @description Run sharing analysis for record access
     */
    private static void runSharingAnalysisCheck(
        String recordId,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        DiagnosticReportBuilder.DiagnosticFinding finding = 
            new DiagnosticReportBuilder.DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Sharing Analysis';
        finding.title = 'Sharing & Access Analysis';
        
        try {
            SharingDiagnosticService.SharingAnalysis analysis = 
                SharingDiagnosticService.analyzeRecordSharing(recordId, userId);
            
            if (analysis.hasAccess) {
                finding.status = 'PASS';
                finding.statusIcon = '✓';
                finding.severity = DiagnosticReportBuilder.Severity.INFO;
                finding.details.add('✓ User has access to this record');
                finding.details.add('Access via: ' + String.join(analysis.accessSources, ', '));
                finding.details.add('OWD Setting: ' + analysis.owdSetting);
            } else {
                finding.status = 'FAIL';
                finding.statusIcon = '✗';
                finding.severity = DiagnosticReportBuilder.Severity.HIGH;
                finding.details.add('✗ User does NOT have access to this record');
                finding.details.add('OWD Setting: ' + analysis.owdSetting);
                finding.details.add('Is Owner: ' + (analysis.isOwner ? 'Yes' : 'No'));
                finding.details.add('Has Role Access: ' + (analysis.hasRoleAccess ? 'Yes' : 'No'));
                finding.impact = 'User cannot view this record due to sharing restrictions';
            }
            
            if (String.isNotBlank(analysis.recommendation)) {
                finding.details.add('Recommendation: ' + analysis.recommendation);
            }
            
        } catch (Exception e) {
            finding.status = 'WARN';
            finding.statusIcon = '⚠';
            finding.severity = DiagnosticReportBuilder.Severity.MEDIUM;
            finding.details.add('Could not complete sharing analysis: ' + e.getMessage());
        }
        
        report.findings.add(finding);
    }

    /**
    * @description Check validation rules on object
    */
    private static void runValidationRuleCheck(
        String objectName,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        DiagnosticReportBuilder.DiagnosticFinding finding = 
            new DiagnosticReportBuilder.DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Validation Rules';
        finding.title = 'Active Validation Rules on ' + objectName;
        
        try {
            List<MetadataQueryService.ValidationRuleInfo> rules = 
                MetadataQueryService.getValidationRules(objectName);
            
            if (rules.isEmpty()) {
                finding.status = 'INFO';
                finding.statusIcon = 'ℹ';
                finding.severity = DiagnosticReportBuilder.Severity.INFO;
                finding.details.add('No active validation rules found on ' + objectName);
            } else {
                finding.status = 'WARN';
                finding.statusIcon = '⚠';
                finding.severity = DiagnosticReportBuilder.Severity.MEDIUM;
                finding.details.add('Found ' + rules.size() + ' active validation rule(s)');
                
                Integer count = 0;
                for (MetadataQueryService.ValidationRuleInfo rule : rules) {
                    if (count < 5) { // Show first 5
                        finding.details.add('Rule: ' + rule.validationName);
                        if (String.isNotBlank(rule.errorMessage)) {
                            finding.details.add('  Error: ' + rule.errorMessage);
                        }
                    }
                    count++;
                }
                
                if (rules.size() > 5) {
                    finding.details.add('... and ' + (rules.size() - 5) + ' more rules');
                }
                
                finding.impact = 'Validation rules may block saving if criteria are not met';
            }
            
        } catch (Exception e) {
            finding.status = 'WARN';
            finding.statusIcon = '⚠';
            finding.severity = DiagnosticReportBuilder.Severity.LOW;
            finding.details.add('Could not retrieve validation rules: ' + e.getMessage());
        }
        
        report.findings.add(finding);
    }
    /**
     * @description Perform root cause analysis and add to report
     */
    private static void performRootCauseAnalysis(
        String objectName,
        String fieldName,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        try {
            System.debug('=== PERFORMING ROOT CAUSE ANALYSIS ===');
            
            RootCauseAnalyzer.RootCause rootCause = 
                RootCauseAnalyzer.analyzeFieldVisibility(objectName, fieldName, userId, report.findings);
            
            // Add root cause as special finding
            DiagnosticReportBuilder.DiagnosticFinding finding = 
                new DiagnosticReportBuilder.DiagnosticFinding();
            finding.sequenceNumber = report.findings.size() + 1;
            finding.category = 'Root Cause Analysis';
            finding.title = '🎯 ROOT CAUSE IDENTIFIED';
            finding.status = 'INFO';
            finding.statusIcon = '🎯';
            finding.severity = DiagnosticReportBuilder.Severity.INFO;
            
            finding.details.add('PRIMARY CAUSE: ' + rootCause.primaryCause);
            finding.details.add('Confidence: ' + rootCause.confidence + '%');
            finding.details.add('');
            finding.details.add('EXPLANATION:');
            finding.details.add(rootCause.explanation);
            
            if (!rootCause.solutionSteps.isEmpty()) {
                finding.details.add('');
                finding.details.add('SOLUTION STEPS:');
                Integer stepNum = 1;
                for (String step : rootCause.solutionSteps) {
                    finding.details.add(stepNum + '. ' + step);
                    stepNum++;
                }
            }
            
            if (String.isNotBlank(rootCause.whoCanFix)) {
                finding.details.add('');
                finding.details.add('WHO CAN FIX: ' + rootCause.whoCanFix);
            }
            
            if (!rootCause.contributingFactors.isEmpty()) {
                finding.details.add('');
                finding.details.add('OTHER FACTORS TO CONSIDER:');
                for (String factor : rootCause.contributingFactors) {
                    finding.details.add('• ' + factor);
                }
            }
            
            report.findings.add(finding);
            
            // Update report summary with root cause
            report.summary.rootCause = rootCause.primaryCause;
            
            System.debug('Root cause added to report: ' + rootCause.primaryCause);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error performing root cause analysis: ' + e.getMessage());
        }
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
        String fieldName,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        DiagnosticReportBuilder.DiagnosticFinding finding = 
            new DiagnosticReportBuilder.DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Page Layout';
        
        if (String.isNotBlank(fieldName)) {
            // Check SPECIFIC field on layout
            finding.title = 'Page Layout Check: ' + objectName + '.' + fieldName;
            
            Boolean isOnLayout = MetadataQueryService.isFieldOnPageLayout(objectName, fieldName, null);
            
            if (isOnLayout) {
                finding.status = 'PASS';
                finding.statusIcon = '✓';
                finding.severity = DiagnosticReportBuilder.Severity.INFO;
                finding.details.add('✓ Field "' + fieldName + '" IS on the page layout');
            } else {
                finding.status = 'FAIL';
                finding.statusIcon = '✗';
                finding.severity = DiagnosticReportBuilder.Severity.HIGH;
                finding.details.add('✗ Field "' + fieldName + '" is NOT on the page layout');
                finding.impact = 'User cannot see this field because it is not added to the page layout';
                finding.details.add('Solution: Add field to page layout in Setup → Object Manager → ' + 
                                objectName + ' → Page Layouts');
            }
        } else {
            // General layout info
            List<String> layoutFields = MetadataQueryService.getPageLayoutFields(objectName, null);
            
            finding.title = 'Page Layout Fields on ' + objectName;
            finding.status = 'INFO';
            finding.statusIcon = 'ℹ';
            finding.severity = DiagnosticReportBuilder.Severity.INFO;
            finding.details.add('Found ' + layoutFields.size() + ' fields on layout');
            
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
    /**
     * @description Validate that target user exists and is active
     * @param analysis Message analysis with potential target user info
     * @return UserValidationResult with validation outcome
     */
    private static UserValidationResult validateTargetUser(MessageAnalyzer.MessageAnalysis analysis) {
        UserValidationResult result = new UserValidationResult();
        
        // If no target user mentioned, current user is valid
        if (analysis.targetUserId == null && 
            String.isBlank(analysis.targetUserName) && 
            String.isBlank(analysis.targetUserEmail)) {
            result.isValid = true;
            result.userId = UserInfo.getUserId();
            result.userName = UserInfo.getName();
            result.isCurrentUser = true;
            return result;
        }
        
        // Target user was mentioned - validate they exist
        try {
            User targetUser = null;
            
            // Priority 1: Direct User ID
            if (analysis.targetUserId != null) {
                List<User> users = [
                    SELECT Id, Name, Email, Username, IsActive 
                    FROM User 
                    WHERE Id = :analysis.targetUserId 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    targetUser = users[0];
                } else {
                    result.isValid = false;
                    result.errorMessage = 'User ID "' + analysis.targetUserId + '" not found or user is inactive.';
                    return result;
                }
            }
            
            // Priority 2: Email/Username (try both fields)
            if (targetUser == null && String.isNotBlank(analysis.targetUserEmail)) {
                String searchValue = analysis.targetUserEmail;
                
                // Try as Username first (more common for login identifiers)
                List<User> users = [
                    SELECT Id, Name, Email, Username, IsActive 
                    FROM User 
                    WHERE Username = :searchValue 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    targetUser = users[0];
                    System.debug('Found user by Username: ' + searchValue);
                } else {
                    // Try as Email field
                    users = [
                        SELECT Id, Name, Email, Username, IsActive 
                        FROM User 
                        WHERE Email = :searchValue 
                        AND IsActive = true 
                        LIMIT 1
                    ];
                    
                    if (!users.isEmpty()) {
                        targetUser = users[0];
                        System.debug('Found user by Email: ' + searchValue);
                    } else {
                        // One more try - case-insensitive search on both fields
                        String likePattern = '%' + searchValue + '%';
                        users = [
                            SELECT Id, Name, Email, Username, IsActive 
                            FROM User 
                            WHERE (Username LIKE :likePattern OR Email LIKE :likePattern)
                            AND IsActive = true 
                            LIMIT 2
                        ];
                        
                        if (users.isEmpty()) {
                            result.isValid = false;
                            result.errorMessage = 'No active user found with email or username "' + searchValue + '".';
                            return result;
                        } else if (users.size() > 1) {
                            result.isValid = false;
                            result.errorMessage = 'Multiple users found matching "' + searchValue + '". Please be more specific.';
                            result.ambiguousUsers = new List<String>();
                            for (User u : users) {
                                result.ambiguousUsers.add(u.Name + ' (' + u.Username + ')');
                            }
                            return result;
                        } else {
                            targetUser = users[0];
                            System.debug('Found user by partial match: ' + searchValue);
                        }
                    }
                }
            }
            
            // Priority 3: Name (exact or partial match)
            if (targetUser == null && String.isNotBlank(analysis.targetUserName)) {
                // Try exact Name match first
                List<User> users = [
                    SELECT Id, Name, Email, Username, IsActive 
                    FROM User 
                    WHERE Name = :analysis.targetUserName 
                    AND IsActive = true 
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    targetUser = users[0];
                    System.debug('Found user by exact Name: ' + analysis.targetUserName);
                } else {
                    // Try partial name match (first name or last name)
                    String likePattern = '%' + analysis.targetUserName + '%';
                    users = [
                        SELECT Id, Name, Email, Username, IsActive 
                        FROM User 
                        WHERE Name LIKE :likePattern 
                        AND IsActive = true 
                        ORDER BY Name
                        LIMIT 2 // Get 2 to detect ambiguity
                    ];
                    
                    if (users.isEmpty()) {
                        result.isValid = false;
                        result.errorMessage = 'No active user found with name "' + analysis.targetUserName + '".';
                        return result;
                    } else if (users.size() > 1) {
                        result.isValid = false;
                        result.errorMessage = 'Multiple users found matching "' + analysis.targetUserName + '". Please be more specific (use full name or username).';
                        result.ambiguousUsers = new List<String>();
                        for (User u : users) {
                            result.ambiguousUsers.add(u.Name + ' (' + u.Username + ')');
                        }
                        return result;
                    } else {
                        targetUser = users[0];
                        System.debug('Found user by partial Name: ' + analysis.targetUserName);
                    }
                }
            }
            
            // If we found a user, populate result
            if (targetUser != null) {
                result.isValid = true;
                result.userId = targetUser.Id;
                result.userName = targetUser.Name;
                result.userEmail = targetUser.Email;
                result.username = targetUser.Username;
                result.isCurrentUser = (targetUser.Id == UserInfo.getUserId());
                
                System.debug('✅ Target user validated: ' + targetUser.Name + ' (' + targetUser.Username + ')');
                return result;
            }
            
            // Should not reach here, but just in case
            result.isValid = false;
            result.errorMessage = 'Unable to identify the user. Please provide a valid email, username, or full name.';
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error validating target user: ' + e.getMessage());
            result.isValid = false;
            result.errorMessage = 'Error validating user: ' + e.getMessage();
        }
        
        return result;
    }

    /**
     * @description Inner class for user validation result
     */
    private class UserValidationResult {
        public Boolean isValid;
        public Id userId;
        public String userEmail;
        public String username;  
        public Boolean isCurrentUser;
        public String errorMessage;
        public List<String> ambiguousUsers;
        
        public UserValidationResult() {
            this.isValid = false;
            this.isCurrentUser = false;
            this.ambiguousUsers = new List<String>();
        }
    }
    
    @AuraEnabled(cacheable=false)
    public static Boolean testAPIConnection() {
        return GroqAPIService.testConnection();
    }
}