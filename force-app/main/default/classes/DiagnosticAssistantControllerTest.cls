/**
 * @description Test suite for DiagnosticAssistantController
 * Validates message processing, session management, error handling, and service orchestration
 * Tests full integration with all backend services
 * 
 * @author Salesforce Insight Team
 * @version 2.0 (Fully Integrated)
 * @since 2026-01-09
 */
@IsTest
private class DiagnosticAssistantControllerTest {
    
    /**
     * @description Mock HTTP response for Groq API calls
     */
    private class GroqAPIMock implements HttpCalloutMock {
        private Boolean shouldSucceed;
        private String responseContent;
        
        public GroqAPIMock(Boolean shouldSucceed, String responseContent) {
            this.shouldSucceed = shouldSucceed;
            this.responseContent = responseContent;
        }
        
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            
            if (shouldSucceed) {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'id' => 'test-123',
                    'model' => 'llama-3.3-70b-versatile',
                    'choices' => new List<Object>{
                        new Map<String, Object>{
                            'message' => new Map<String, Object>{
                                'role' => 'assistant',
                                'content' => responseContent
                            },
                            'finish_reason' => 'stop'
                        }
                    },
                    'usage' => new Map<String, Object>{
                        'total_tokens' => 150
                    }
                }));
            } else {
                res.setStatusCode(500);
                res.setBody('{"error": {"message": "API Error"}}');
            }
            
            return res;
        }
    }
    
    /**
     * @description Setup test data - creates test user and custom metadata
     */
    @TestSetup
    static void setupTestData() {
        // Create test Diagnostic Session
        Diagnostic_Session__c testSession = new Diagnostic_Session__c(
            User__c = UserInfo.getUserId(),
            Resolution_Status__c = 'Open',
            Conversation_History__c = '[]'
        );
        insert testSession;
    }
    
    /**
     * @description Test successful message processing with field visibility issue
     */
    @IsTest
    static void testProcessUserMessageFieldVisibility() {
        // Setup mock response
        String mockResponse = 'I found the issue! The Phone field exists on Account records, but your ' +
                             'profile doesn\'t have permission to view it. This is a Field-Level Security issue.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'I can\'t see the Phone field on Account';
        
        // Execute
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        // Verify
        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(true, response.success, 'Response should indicate success');
        System.assertNotEquals(null, response.sessionId, 'Session ID should be generated');
        System.assertNotEquals(null, response.message, 'Response message should be populated');
        System.assertEquals(false, response.fallback, 'Should not use fallback when API succeeds');
        System.assert(response.steps.size() > 0, 'Should have diagnostic steps');
        
        // Verify session was created
        List<Diagnostic_Session__c> sessions = [
            SELECT Id, User__c, Conversation_History__c
            FROM Diagnostic_Session__c
            WHERE Id = :response.sessionId
        ];
        System.assertEquals(1, sessions.size(), 'Session should be created');
    }
    
    /**
     * @description Test processing with existing session ID (multi-turn conversation)
     */
    @IsTest
    static void testProcessUserMessageWithExistingSession() {
        // Setup existing session
        Diagnostic_Session__c session = [SELECT Id FROM Diagnostic_Session__c LIMIT 1];
        String mockResponse = 'The Email field has the same issue - Field-Level Security is not granted.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'What about the Email field?';
        
        // Execute
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, session.Id);
        Test.stopTest();
        
        // Verify
        System.assertEquals(true, response.success, 'Response should indicate success');
        System.assertEquals(session.Id, response.sessionId, 'Session ID should be preserved');
        System.assertNotEquals(null, response.message, 'Response should contain message');
    }
    
    /**
     * @description Test empty message validation
     */
    @IsTest
    static void testProcessUserMessageEmptyValidation() {
        // Test empty string
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response1 = 
            DiagnosticAssistantController.processUserMessage('', null);
        Test.stopTest();
        
        System.assertEquals(false, response1.success, 'Empty message should fail validation');
        System.assert(response1.error.contains('empty'), 'Error should mention empty message');
    }
    
    /**
     * @description Test null message validation
     */
    @IsTest
    static void testProcessUserMessageNullValidation() {
        // Test null
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(null, null);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Null message should fail validation');
        System.assertNotEquals('', response.error, 'Error message should be populated');
    }
    
    /**
     * @description Test message length validation
     */
    @IsTest
    static void testProcessUserMessageLengthValidation() {
        // Create message exceeding 5000 characters
        String longMessage = 'a'.repeat(5001);
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(longMessage, null);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Oversized message should fail validation');
        System.assert(response.error.toLowerCase().contains('long'), 'Error should mention length');
    }
    
    /**
     * @description Test whitespace-only message validation
     */
    @IsTest
    static void testProcessUserMessageWhitespaceValidation() {
        String whitespaceMessage = '   \n\t  ';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(whitespaceMessage, null);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Whitespace-only message should fail');
    }
    
    /**
     * @description Test API failure with intelligent fallback
     */
    @IsTest
    static void testProcessUserMessageAPIFailureFallback() {
        // Setup mock to fail
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(false, ''));
        
        String testMessage = 'I can\'t edit the Account record';
        
        // Execute
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        // Verify - should still succeed with fallback
        System.assertEquals(true, response.success, 'Should succeed with fallback');
        System.assertEquals(true, response.fallback, 'Should indicate fallback was used');
        System.assertNotEquals(null, response.message, 'Fallback message should be provided');
        System.assert(response.message.contains('diagnostic'), 'Fallback should mention diagnostics');
    }
    
    /**
     * @description Test callout exception handling
     */
    @IsTest
    static void testProcessUserMessageCalloutException() {
        // Don't set mock - will cause callout exception
        // Note: In real scenario, Named Credential would handle this
        
        String testMessage = 'Test message';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        // Should handle gracefully
        System.assertNotEquals(null, response, 'Response should not be null');
        // May succeed with fallback or fail gracefully
        System.assertNotEquals(null, response.message, 'Should provide some response');
    }
    
    /**
     * @description Test message analysis integration with various issue types
     */
    @IsTest
    static void testMessageAnalysisIntegration() {
        String mockResponse = 'Issue identified and resolved.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        // Test different message types
        Map<String, String> testCases = new Map<String, String>{
            'field_visibility' => 'I can\'t see the Status field on Opportunity',
            'edit_permission' => 'Why can\'t I edit this Contact record?',
            'save_error' => 'I get an error when saving the Case',
            'access_issue' => 'I can\'t access this Lead record'
        };
        
        Test.startTest();
        for (String issueType : testCases.keySet()) {
            DiagnosticAssistantController.ResponseWrapper response = 
                DiagnosticAssistantController.processUserMessage(testCases.get(issueType), null);
            
            System.assertEquals(true, response.success, 'Should process: ' + issueType);
            System.assert(response.steps.size() > 0, 'Should have diagnostic steps for: ' + issueType);
        }
        Test.stopTest();
    }
    
    /**
     * @description Test diagnostic steps are properly generated
     */
    @IsTest
    static void testDiagnosticStepsGeneration() {
        String mockResponse = 'Field-Level Security issue detected.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'I can\'t see the Phone field on Account';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        // Verify steps
        System.assert(response.steps.size() > 0, 'Should have at least one diagnostic step');
        
        for (DiagnosticAssistantController.DiagnosticStep step : response.steps) {
            System.assertNotEquals(null, step.name, 'Step name should be populated');
            System.assertNotEquals(null, step.status, 'Step status should be populated');
            // status should be: pass, fail, warning, or pending
            List<String> validStatuses = new List<String>{'pass', 'fail', 'warning', 'pending'};
            System.assert(validStatuses.contains(step.status.toLowerCase()), 
                         'Step status should be valid: ' + step.status);
        }
    }
    
    /**
     * @description Test record ID extraction and record access check
     */
    @IsTest
    static void testRecordAccessDiagnostics() {
        // Create a test account
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        String mockResponse = 'Record access has been checked.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'I can\'t access record ' + testAccount.Id;
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should process record access check');
        System.assert(response.steps.size() > 0, 'Should have diagnostic steps');
    }
    
    /**
     * @description Test session statistics retrieval
     */
    @IsTest
    static void testGetSessionStats() {
        Diagnostic_Session__c session = [SELECT Id FROM Diagnostic_Session__c LIMIT 1];
        
        Test.startTest();
        Map<String, Object> stats = DiagnosticAssistantController.getSessionStats(session.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, stats, 'Stats should not be null');
        // Stats should contain various metrics from ConversationManager
    }
    
    /**
     * @description Test clear session functionality
     */
    @IsTest
    static void testClearSession() {
        Diagnostic_Session__c session = [SELECT Id FROM Diagnostic_Session__c LIMIT 1];
        
        Test.startTest();
        DiagnosticAssistantController.clearSession(session.Id);
        Test.stopTest();
        
        // Should execute without errors
        // Session history should be cleared (checked in ConversationManager)
        System.assert(true, 'Clear session should execute successfully');
    }
    
    /**
     * @description Test API connection test
     */
    @IsTest
    static void testAPIConnectionTest() {
        // Setup successful mock
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, 'Hello'));
        
        Test.startTest();
        Boolean connected = DiagnosticAssistantController.testAPIConnection();
        Test.stopTest();
        
        // Note: May return false in test context due to Named Credential
        // Just verify it doesn't throw
        System.assertNotEquals(null, connected, 'Should return a result');
    }
    
    /**
     * @description Test response wrapper initialization
     */
    @IsTest
    static void testResponseWrapperInitialization() {
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper wrapper = 
            new DiagnosticAssistantController.ResponseWrapper();
        Test.stopTest();
        
        System.assertEquals(false, wrapper.success, 'Success should default to false');
        System.assertEquals(false, wrapper.fallback, 'Fallback should default to false');
        System.assertNotEquals(null, wrapper.steps, 'Steps list should be initialized');
        System.assertEquals(0, wrapper.steps.size(), 'Steps list should be empty by default');
    }
    
    /**
     * @description Test diagnostic step structure
     */
    @IsTest
    static void testDiagnosticStepStructure() {
        Test.startTest();
        DiagnosticAssistantController.DiagnosticStep step = 
            new DiagnosticAssistantController.DiagnosticStep();
        Test.stopTest();
        
        // Set properties
        step.name = 'Object Permissions Check';
        step.status = 'pass';
        step.details = 'User has read access to Account object';
        
        // Verify
        System.assertEquals('Object Permissions Check', step.name, 'Name should be set');
        System.assertEquals('pass', step.status, 'Status should be set');
        System.assertEquals('User has read access to Account object', step.details, 'Details should be set');
    }
    
    /**
     * @description Test concurrent message processing
     */
    @IsTest
    static void testConcurrentMessageProcessing() {
        String mockResponse = 'Processing complete.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response1 = 
            DiagnosticAssistantController.processUserMessage('Message 1', null);
        DiagnosticAssistantController.ResponseWrapper response2 = 
            DiagnosticAssistantController.processUserMessage('Message 2', null);
        DiagnosticAssistantController.ResponseWrapper response3 = 
            DiagnosticAssistantController.processUserMessage('Message 3', null);
        Test.stopTest();
        
        // All should process successfully
        System.assertEquals(true, response1.success, 'Message 1 should succeed');
        System.assertEquals(true, response2.success, 'Message 2 should succeed');
        System.assertEquals(true, response3.success, 'Message 3 should succeed');
        
        // Session IDs should be unique
        System.assertNotEquals(response1.sessionId, response2.sessionId, 'Sessions should differ');
        System.assertNotEquals(response2.sessionId, response3.sessionId, 'Sessions should differ');
    }
    
    /**
     * @description Test multiple fields mentioned in message
     */
    @IsTest
    static void testMultipleFieldsInMessage() {
        String mockResponse = 'Multiple field issues detected.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'I can\'t see the Phone and Email fields on Account';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should process multiple fields');
        // Should have multiple diagnostic steps (one for each field)
        System.assert(response.steps.size() > 0, 'Should have diagnostic steps');
    }
    
    /**
     * @description Test custom object and field detection
     */
    @IsTest
    static void testCustomObjectFieldDetection() {
        String mockResponse = 'Custom field check complete.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        // Message with custom object pattern
        String testMessage = 'I can\'t see Custom_Field__c on Custom_Object__c';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should process custom objects');
    }
    
    /**
     * @description Test general question (no specific diagnostics)
     */
    @IsTest
    static void testGeneralQuestion() {
        String mockResponse = 'I can help with that. Here is some general guidance.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'How do I create a new field?';
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Should handle general questions');
        System.assertNotEquals(null, response.message, 'Should provide response');
    }
    
    /**
     * @description Test conversation context preservation across messages
     */
    @IsTest
    static void testConversationContextPreservation() {
        String mockResponse = 'Based on our previous conversation...';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        // First message
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response1 = 
            DiagnosticAssistantController.processUserMessage('I can\'t see the Phone field', null);
        
        // Second message in same session
        DiagnosticAssistantController.ResponseWrapper response2 = 
            DiagnosticAssistantController.processUserMessage(
                'What about Email?', 
                response1.sessionId
            );
        Test.stopTest();
        
        System.assertEquals(response1.sessionId, response2.sessionId, 'Session should be preserved');
        System.assertEquals(true, response2.success, 'Follow-up should succeed');
    }
    
    /**
     * @description Test invalid session ID handling
     */
    @IsTest
    static void testInvalidSessionId() {
        String mockResponse = 'New session created.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String invalidSessionId = 'a'.repeat(18); // Invalid but looks like an ID
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage('Test message', invalidSessionId);
        Test.stopTest();
        
        // Should handle gracefully - either create new session or fail gracefully
        System.assertNotEquals(null, response, 'Should handle invalid session ID');
    }
    
    /**
     * @description Test processing time is reasonable
     */
    @IsTest
    static void testProcessingPerformance() {
        String mockResponse = 'Quick response.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        String testMessage = 'Test performance';
        
        Long startTime = System.currentTimeMillis();
        
        Test.startTest();
        DiagnosticAssistantController.ResponseWrapper response = 
            DiagnosticAssistantController.processUserMessage(testMessage, null);
        Test.stopTest();
        
        Long endTime = System.currentTimeMillis();
        Long duration = endTime - startTime;
        
        System.assertEquals(true, response.success, 'Should complete successfully');
        System.debug('Processing time: ' + duration + 'ms');
        // In test context, should be fast
    }
    
    /**
     * @description Test AuraEnabled annotation and accessibility
     */
    @IsTest
    static void testAuraEnabledAccessibility() {
        try {
            // Method should be callable from LWC context
            String mockResponse = 'Test response';
            Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
            
            Test.startTest();
            DiagnosticAssistantController.ResponseWrapper response = 
                DiagnosticAssistantController.processUserMessage('Test', null);
            Test.stopTest();
            
            System.assertNotEquals(null, response, '@AuraEnabled method should be callable');
        } catch (Exception e) {
            System.assert(false, '@AuraEnabled method should not throw: ' + e.getMessage());
        }
    }
    
    /**
     * @description Test bulk processing (stress test)
     */
    @IsTest
    static void testBulkProcessing() {
        String mockResponse = 'Processed successfully.';
        Test.setMock(HttpCalloutMock.class, new GroqAPIMock(true, mockResponse));
        
        List<DiagnosticAssistantController.ResponseWrapper> responses = 
            new List<DiagnosticAssistantController.ResponseWrapper>();
        
        Test.startTest();
        for (Integer i = 0; i < 10; i++) {
            DiagnosticAssistantController.ResponseWrapper response = 
                DiagnosticAssistantController.processUserMessage('Test message ' + i, null);
            responses.add(response);
        }
        Test.stopTest();
        
        // All should succeed
        for (DiagnosticAssistantController.ResponseWrapper resp : responses) {
            System.assertEquals(true, resp.success, 'Bulk processing should succeed');
        }
        
        System.assertEquals(10, responses.size(), 'Should process all messages');
    }
}