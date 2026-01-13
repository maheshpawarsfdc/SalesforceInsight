/**
 * @description Test class for GroqAPIService
 * @author Salesforce AI Diagnostic Assistant  
 * @date 2026
 */
@isTest
private class GroqAPIServiceTest {
    
    /**
     * @description Mock HTTP callout for successful API response
     */
    private class GroqAPIMockSuccess implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            
            // Mock successful Groq API response
            String responseBody = '{' +
                '"id": "chatcmpl-123",' +
                '"object": "chat.completion",' +
                '"created": 1677652288,' +
                '"model": "llama-3.3-70b-versatile",' +
                '"choices": [{' +
                    '"index": 0,' +
                    '"message": {' +
                        '"role": "assistant",' +
                        '"content": "I\'ve identified the issue. The Phone field exists but your profile doesn\'t have permission to view it due to Field-Level Security settings."' +
                    '},' +
                    '"finish_reason": "stop"' +
                '}],' +
                '"usage": {' +
                    '"prompt_tokens": 50,' +
                    '"completion_tokens": 30,' +
                    '"total_tokens": 80' +
                '}' +
            '}';
            
            res.setBody(responseBody);
            return res;
        }
    }
    
    /**
     * @description Mock HTTP callout for rate limit error
     */
    private class GroqAPIMockRateLimit implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(429);
            res.setBody('{"error": {"message": "Rate limit exceeded", "type": "rate_limit_error"}}');
            return res;
        }
    }
    
    /**
     * @description Mock HTTP callout for authentication error
     */
    private class GroqAPIMockAuthError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(401);
            res.setBody('{"error": {"message": "Invalid API key", "type": "invalid_request_error"}}');
            return res;
        }
    }
    
    /**
     * @description Mock HTTP callout for server error
     */
    private class GroqAPIMockServerError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(500);
            res.setBody('{"error": {"message": "Internal server error"}}');
            return res;
        }
    }
    
    @isTest
    static void testSendMessage_Success() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockSuccess());
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessage(
            'I can\'t see the Phone field on Account', 
            100
        );
        Test.stopTest();
        
        // Verify response
        System.assertEquals(true, response.success, 'API call should succeed');
        System.assertNotEquals(null, response.content, 'Response content should not be null');
        System.assert(response.content.contains('Field-Level Security'), 'Response should mention FLS');
        System.assertEquals(80, response.tokensUsed, 'Token usage should be tracked');
    }
    
    @isTest
    static void testSendMessageWithContext_Success() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockSuccess());
        
        String systemPrompt = GroqAPIService.buildDiagnosticSystemPrompt();
        String context = 'User Profile: Standard User\nObject: Account\nField: Phone\nFLS: Not Granted';
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessageWithContext(
            'Why can\'t I see this field?',
            systemPrompt,
            context
        );
        Test.stopTest();
        
        // Verify response
        System.assertEquals(true, response.success, 'API call should succeed');
        System.assertNotEquals(null, response.content, 'Response content should not be null');
    }
    
    @isTest
    static void testSendMessages_WithMultipleMessages() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockSuccess());
        
        List<GroqAPIService.Message> messages = new List<GroqAPIService.Message>();
        messages.add(new GroqAPIService.Message('system', 'You are a helpful assistant'));
        messages.add(new GroqAPIService.Message('user', 'I need help with permissions'));
        messages.add(new GroqAPIService.Message('assistant', 'I can help with that'));
        messages.add(new GroqAPIService.Message('user', 'Great, I can\'t see a field'));
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessages(messages, 200);
        Test.stopTest();
        
        // Verify response
        System.assertEquals(true, response.success, 'API call should succeed');
        System.assertNotEquals(null, response.content, 'Response should have content');
    }
    
    @isTest
    static void testSendMessage_EmptyMessage() {
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessages(null, 100);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, response.success, 'Should fail with empty messages');
        System.assertNotEquals(null, response.errorMessage, 'Should have error message');
        System.assert(response.errorMessage.contains('empty'), 'Error should mention empty messages');
    }
    
    @isTest
    static void testSendMessage_RateLimitError() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockRateLimit());
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessage('Test message', 100);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, response.success, 'Should fail due to rate limit');
        System.assertNotEquals(null, response.errorMessage, 'Should have error message');
        System.assert(response.errorMessage.contains('Rate limit'), 'Error should mention rate limit');
    }
    
    @isTest
    static void testSendMessage_AuthenticationError() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockAuthError());
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessage('Test message', 100);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, response.success, 'Should fail due to auth error');
        System.assertNotEquals(null, response.errorMessage, 'Should have error message');
        System.assert(response.errorMessage.contains('authentication'), 'Error should mention auth');
    }
    
    @isTest
    static void testSendMessage_ServerError() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockServerError());
        
        Test.startTest();
        GroqAPIService.APIResponse response = GroqAPIService.sendMessage('Test message', 100);
        Test.stopTest();
        
        // Verify error handling
        System.assertEquals(false, response.success, 'Should fail due to server error');
        System.assertNotEquals(null, response.errorMessage, 'Should have error message');
        System.assert(response.errorMessage.contains('unavailable'), 'Error should mention unavailability');
    }
    
    @isTest
    static void testBuildDiagnosticSystemPrompt() {
        Test.startTest();
        String prompt = GroqAPIService.buildDiagnosticSystemPrompt();
        Test.stopTest();
        
        // Verify prompt content
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('Salesforce'), 'Prompt should mention Salesforce');
        System.assert(prompt.contains('diagnostic'), 'Prompt should mention diagnostic');
        System.assert(prompt.contains('permission'), 'Prompt should mention permissions');
    }
    
    @isTest
    static void testTestConnection_Success() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockSuccess());
        
        Test.startTest();
        Boolean connected = GroqAPIService.testConnection();
        Test.stopTest();
        
        System.assertEquals(true, connected, 'Connection test should succeed');
    }
    
    @isTest
    static void testTestConnection_Failure() {
        Test.setMock(HttpCalloutMock.class, new GroqAPIMockAuthError());
        
        Test.startTest();
        Boolean connected = GroqAPIService.testConnection();
        Test.stopTest();
        
        System.assertEquals(false, connected, 'Connection test should fail');
    }
    
    @isTest
    static void testGetUsageStats() {
        Test.startTest();
        Map<String, Integer> stats = GroqAPIService.getUsageStats();
        Test.stopTest();
        
        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assert(stats.containsKey('totalCalls'), 'Stats should have totalCalls');
        System.assert(stats.containsKey('totalTokens'), 'Stats should have totalTokens');
    }
    
    @isTest
    static void testMessageWrapper() {
        Test.startTest();
        GroqAPIService.Message msg = new GroqAPIService.Message('user', 'Test content');
        Test.stopTest();
        
        System.assertEquals('user', msg.role, 'Role should be set');
        System.assertEquals('Test content', msg.content, 'Content should be set');
    }
    
    @isTest
    static void testAPIResponseWrapper() {
        Test.startTest();
        GroqAPIService.APIResponse response = new GroqAPIService.APIResponse();
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Default success should be false');
    }
}