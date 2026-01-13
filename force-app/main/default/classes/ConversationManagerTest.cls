/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an org are executed whenever Apex code is deployed
 * to a production org to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production org. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the org size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
/**
 * @description Test class for ConversationManager
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class ConversationManagerTest {
    
    @testSetup
    static void setup() {
        // Create test user
        User testUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }
    
    @isTest
    static void testAddMessage_NewSession() {
        Test.startTest();
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'I can\'t see the Phone field');
        Test.stopTest();
        
        System.assertNotEquals(null, context, 'Context should be created');
        System.assertNotEquals(null, context.sessionId, 'Session ID should be generated');
        System.assertEquals(1, context.recentMessages.size(), 'Should have one message');
        System.assertEquals('user', context.recentMessages[0].role, 'Message role should be user');
    }
    
    @isTest
    static void testAddMessage_ExistingSession() {
        // Create initial message
        ConversationManager.ConversationContext context1 = 
            ConversationManager.addMessage(null, 'user', 'I can\'t see the Phone field');
        
        Test.startTest();
        // Add second message
        ConversationManager.ConversationContext context2 = 
            ConversationManager.addMessage(context1.sessionId, 'assistant', 'Let me check that for you');
        Test.stopTest();
        
        System.assertEquals(context1.sessionId, context2.sessionId, 'Should be same session');
        System.assertEquals(2, context2.recentMessages.size(), 'Should have two messages');
    }
    
    @isTest
    static void testGetContext() {
        // Create session with messages
        ConversationManager.ConversationContext context1 = 
            ConversationManager.addMessage(null, 'user', 'Can\'t edit Account records');
        ConversationManager.addMessage(context1.sessionId, 'assistant', 'I\'ll check your permissions');
        
        Test.startTest();
        ConversationManager.ConversationContext context = 
            ConversationManager.getContext(context1.sessionId);
        Test.stopTest();
        
        System.assertNotEquals(null, context, 'Context should be retrieved');
        System.assertEquals(2, context.recentMessages.size(), 'Should have two messages');
        System.assertNotEquals(null, context.formattedContext, 'Formatted context should exist');
    }
    
    @isTest
    static void testBuildContext_WithSummary() {
        ConversationManager.ConversationContext context1 = 
            ConversationManager.addMessage(null, 'user', 'I can\'t see Phone field on Account');
        
        Test.startTest();
        ConversationManager.ConversationContext context = 
            ConversationManager.getContext(context1.sessionId);
        Test.stopTest();
        
        System.assertNotEquals(null, context.summary, 'Summary should exist');
        System.assert(context.summary.objectsDiscussed.contains('Account'), 
                     'Summary should include Account');
        System.assert(context.summary.fieldsDiscussed.contains('Phone'), 
                     'Summary should include Phone');
    }
    
    @isTest
    static void testFormattedContext_Structure() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Help with permissions');
        
        Test.startTest();
        String formatted = context.formattedContext;
        Test.stopTest();
        
        System.assert(formatted.contains('[CONVERSATION CONTEXT]'), 
                     'Should contain context header');
        System.assert(formatted.contains('[CONVERSATION SUMMARY]'), 
                     'Should contain summary section');
        System.assert(formatted.contains('[RECENT MESSAGES]'), 
                     'Should contain messages section');
        System.assert(formatted.contains('[CURRENT STATE]'), 
                     'Should contain state section');
    }
    
    @isTest
    static void testTokenEstimation() {
        String testText = 'This is a test message with some content to estimate tokens.';
        
        Test.startTest();
        // Create context with message
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', testText);
        Test.stopTest();
        
        System.assert(context.estimatedTokens > 0, 'Should estimate some tokens');
        System.debug('Estimated tokens: ' + context.estimatedTokens);
    }
    
    @isTest
    static void testMultipleMessages_RecentOnly() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Message 1');
        
        // Add 9 more messages (total 10)
            for (Integer i = 2; i <= 10; i++) {
                ConversationManager.addMessage(
                    context.sessionId,
                    (Math.mod(i, 2) == 0) ? 'assistant' : 'user',
                    'Message ' + i
                );
            }

        
        Test.startTest();
        ConversationManager.ConversationContext finalContext = 
            ConversationManager.getContext(context.sessionId);
        Test.stopTest();
        
        // Should only keep last 5 messages
        System.assertEquals(5, finalContext.recentMessages.size(), 
                          'Should keep only last 5 messages');
        System.assertEquals('Message 10', finalContext.recentMessages[4].content, 
                          'Last message should be Message 10');
    }
    
    @isTest
    static void testUpdateDiagnosticResult() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Test message');
        
        String diagnosticResult = 'Field-Level Security check: FAILED\nObject Access check: PASSED';
        
        Test.startTest();
        ConversationManager.updateDiagnosticResult(context.sessionId, diagnosticResult);
        Test.stopTest();
        
        // Verify diagnostic result stored
        Diagnostic_Session__c session = [
            SELECT Diagnosis_Result__c 
            FROM Diagnostic_Session__c 
            WHERE Id = :context.sessionId
        ];
        
        System.assertEquals(diagnosticResult, session.Diagnosis_Result__c, 
                          'Diagnostic result should be stored');
    }
    
    @isTest
    static void testMarkSessionResolved() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Issue fixed!');
        
        Test.startTest();
        ConversationManager.markSessionResolved(context.sessionId);
        Test.stopTest();
        
        Diagnostic_Session__c session = [
            SELECT Resolution_Status__c 
            FROM Diagnostic_Session__c 
            WHERE Id = :context.sessionId
        ];
        
        System.assertEquals('Resolved', session.Resolution_Status__c, 
                          'Session should be marked resolved');
    }
    
    @isTest
    static void testClearHistory() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Message 1');
        ConversationManager.addMessage(context.sessionId, 'assistant', 'Message 2');
        
        Test.startTest();
        ConversationManager.clearHistory(context.sessionId);
        Test.stopTest();
        
        ConversationManager.ConversationContext clearedContext = 
            ConversationManager.getContext(context.sessionId);
        
        System.assertEquals(0, clearedContext.recentMessages.size(), 
                          'History should be cleared');
    }
    
    @isTest
    static void testGetConversationStats() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Message 1');
        ConversationManager.addMessage(context.sessionId, 'assistant', 'Message 2');
        ConversationManager.addMessage(context.sessionId, 'user', 'Message 3');
        
        Test.startTest();
        Map<String, Object> stats = 
            ConversationManager.getConversationStats(context.sessionId);
        Test.stopTest();
        
        System.assertEquals(3, stats.get('totalMessages'), 'Should have 3 total messages');
        System.assertEquals(2, stats.get('userMessages'), 'Should have 2 user messages');
        System.assertEquals(1, stats.get('assistantMessages'), 'Should have 1 assistant message');
        System.assertNotEquals(null, stats.get('sessionAge'), 'Should have session age');
    }
    
    @isTest
    static void testSessionState_TracksDiagnostics() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Can\'t see field');
        
        // Add diagnostic result
        String diagnosticResult = 'Field-Level Security check completed\nObject Access verified';
        ConversationManager.updateDiagnosticResult(context.sessionId, diagnosticResult);
        
        Test.startTest();
        ConversationManager.ConversationContext updatedContext = 
            ConversationManager.getContext(context.sessionId);
        Test.stopTest();
        
        System.assert(!updatedContext.currentState.diagnosticsRun.isEmpty(), 
                     'Should track diagnostics run');
    }
    
    @isTest
    static void testConversationSummary_TracksEntities() {
        Test.startTest();
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 
                'I can\'t see Phone field on Account and Email field on Contact');
        Test.stopTest();
        
        System.assertEquals(2, context.summary.objectsDiscussed.size(), 
                          'Should track 2 objects');
        System.assertEquals(2, context.summary.fieldsDiscussed.size(), 
                          'Should track 2 fields');
    }
    
    @isTest
    static void testLongConversation_Pruning() {
        ConversationManager.ConversationContext context = 
            ConversationManager.addMessage(null, 'user', 'Start of conversation');
        
        // Add many messages to exceed token limit
        String longMessage = 'This is a very long message with lots of content. '.repeat(50);
        
        for (Integer i = 0; i < 20; i++) {
            ConversationManager.addMessage(context.sessionId, 
                                          (Math.mod(i, 2) == 0) ? 'user' : 'assistant', 
                                          longMessage);
        }
        
        Test.startTest();
        ConversationManager.ConversationContext finalContext = 
            ConversationManager.getContext(context.sessionId);
        Test.stopTest();
        
        // Should be pruned to fit token limit
        System.assert(finalContext.estimatedTokens <= 3000, 
                     'Should be within token limit after pruning');
    }
    
    @isTest
    static void testInvalidSessionId() {
        Boolean exceptionThrown = false;
        
        Test.startTest();
        try {
            ConversationManager.getContext('invalid_session_id');
        } catch (ConversationManager.ConversationException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        
        System.assertEquals(true, exceptionThrown, 
                          'Should throw exception for invalid session');
    }
    
    @isTest
    static void testMessageWrapper() {
        Test.startTest();
        ConversationManager.Message msg = 
            new ConversationManager.Message('user', 'Test content', 1);
        Test.stopTest();
        
        System.assertEquals('user', msg.role, 'Role should be set');
        System.assertEquals('Test content', msg.content, 'Content should be set');
        System.assertEquals(1, msg.sequenceNumber, 'Sequence should be set');
        System.assertNotEquals(null, msg.timestamp, 'Timestamp should be set');
    }
    
    @isTest
    static void testConversationContext_Initialization() {
        Test.startTest();
        ConversationManager.ConversationContext context = 
            new ConversationManager.ConversationContext();
        Test.stopTest();
        
        System.assertNotEquals(null, context.recentMessages, 'Recent messages should be initialized');
        System.assertNotEquals(null, context.summary, 'Summary should be initialized');
        System.assertNotEquals(null, context.currentState, 'State should be initialized');
    }
}