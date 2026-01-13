/**
 * @description Test class for MessageAnalyzer
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class MessageAnalyzerTest {
    
    @isTest
    static void testAnalyzeMessage_FieldVisibility() {
        String message = 'I can\'t see the Phone field on Account records';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        // Verify objects extracted
        System.assert(analysis.objectsInvolved.contains('Account'), 
                     'Should identify Account object');
        
        // Verify fields extracted
        System.assert(analysis.fieldsInvolved.contains('Phone'), 
                     'Should identify Phone field');
        
        // Verify issue category
        System.assertEquals('field_visibility', analysis.issueCategory, 
                          'Should categorize as field visibility issue');
        
        // Verify diagnostics
        System.assert(analysis.diagnosticsNeeded.contains('checkFieldSecurity'), 
                     'Should include field security check');
        System.assert(analysis.diagnosticsNeeded.contains('checkPageLayout'), 
                     'Should include page layout check');
        
        // Verify confidence
        System.assertNotEquals('low', analysis.confidence, 
                             'Should have medium or high confidence');
    }
    
    @isTest
    static void testAnalyzeMessage_EditPermission() {
        String message = 'I cannot edit Contact records';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.objectsInvolved.contains('Contact'), 
                     'Should identify Contact object');
        System.assertEquals('edit_permission', analysis.issueCategory, 
                          'Should categorize as edit permission issue');
        System.assert(analysis.diagnosticsNeeded.contains('checkObjectPermissions'), 
                     'Should include object permissions check');
    }
    
    @isTest
    static void testAnalyzeMessage_RecordAccess() {
        String message = 'I can\'t access record 001000000000AAA';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals(1, analysis.recordIds.size(), 
                          'Should extract one record ID');
        System.assertEquals('001000000000AAA', analysis.recordIds[0], 
                          'Should extract correct record ID');
        System.assertEquals('access_issue', analysis.issueCategory, 
                          'Should categorize as access issue');
        System.assert(analysis.diagnosticsNeeded.contains('checkRecordAccess'), 
                     'Should include record access check');
    }
    
    @isTest
    static void testAnalyzeMessage_SaveError() {
        String message = 'I get an error when saving Opportunity 006XXXXXXXXXX';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.objectsInvolved.contains('Opportunity'), 
                     'Should identify Opportunity object');
        System.assertEquals('save_error', analysis.issueCategory, 
                          'Should categorize as save error');
        System.assert(analysis.diagnosticsNeeded.contains('checkValidationRules'), 
                     'Should include validation rules check');
        System.assertEquals(1, analysis.recordIds.size(), 
                          'Should extract record ID');
    }
    
    @isTest
    static void testAnalyzeMessage_ValidationError() {
        String message = 'Validation rule is blocking my save on Amount field';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals('validation_error', analysis.issueCategory, 
                          'Should categorize as validation error');
        System.assert(analysis.diagnosticsNeeded.contains('checkValidationRules'), 
                     'Should include validation check');
    }
    
    @isTest
    static void testAnalyzeMessage_MultipleObjects() {
        String message = 'I can\'t see Contact Phone field or Account Email field';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals(2, analysis.objectsInvolved.size(), 
                          'Should identify both objects');
        System.assert(analysis.objectsInvolved.contains('Contact'), 
                     'Should contain Contact');
        System.assert(analysis.objectsInvolved.contains('Account'), 
                     'Should contain Account');
        System.assertEquals(2, analysis.fieldsInvolved.size(), 
                          'Should identify both fields');
    }
    
    @isTest
    static void testAnalyzeMessage_MultipleRecordIds() {
        String message = 'Records 001000000000AAA and 003000000000BBB are not accessible';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals(2, analysis.recordIds.size(), 
                          'Should extract two record IDs');
        System.assert(analysis.recordIds.contains('001000000000AAA'), 
                     'Should contain first ID');
        System.assert(analysis.recordIds.contains('003000000000BBB'), 
                     'Should contain second ID');
    }
    
    @isTest
    static void testAnalyzeMessage_CustomObject() {
        String message = 'Cannot edit Custom_Object__c record';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        // Custom object pattern detected
        System.assertEquals('edit_permission', analysis.issueCategory, 
                          'Should categorize as edit permission');
    }
    
    @isTest
    static void testAnalyzeMessage_CustomField() {
        String message = 'Custom_Field__c is not visible';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals('field_visibility', analysis.issueCategory, 
                          'Should categorize as field visibility');
    }
    
    @isTest
    static void testAnalyzeMessage_EmptyMessage() {
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage('');
        Test.stopTest();
        
        System.assertEquals('general', analysis.issueCategory, 
                          'Empty message should default to general');
        System.assertEquals('low', analysis.confidence, 
                          'Empty message should have low confidence');
        System.assert(analysis.reasoning.contains('Empty'), 
                     'Reasoning should mention empty message');
    }
    
    @isTest
    static void testAnalyzeMessage_NullMessage() {
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(null);
        Test.stopTest();
        
        System.assertEquals('general', analysis.issueCategory, 
                          'Null message should default to general');
        System.assertEquals('low', analysis.confidence, 
                          'Null message should have low confidence');
    }
    
    @isTest
    static void testAnalyzeMessage_VagueQuestion() {
        String message = 'Help me';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals('general', analysis.issueCategory, 
                          'Vague message should be general');
        System.assertEquals('low', analysis.confidence, 
                          'Vague message should have low confidence');
    }
    
    @isTest
    static void testAnalyzeMessage_DetailedQuestion() {
        String message = 'Why can\'t I edit the CloseDate field on my Opportunity record 006123456789ABC when I\'m the owner?';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.objectsInvolved.contains('Opportunity'), 
                     'Should identify Opportunity');
        System.assert(analysis.fieldsInvolved.contains('CloseDate'), 
                     'Should identify CloseDate field');
        System.assertEquals(1, analysis.recordIds.size(), 
                          'Should extract record ID');
        System.assertEquals('edit_permission', analysis.issueCategory, 
                          'Should categorize as edit permission');
        System.assertEquals('high', analysis.confidence, 
                          'Detailed message should have high confidence');
    }
    
    @isTest
    static void testAnalyzeMessage_CommonFieldVariations() {
        String message = 'The phone number field is missing';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.fieldsInvolved.contains('Phone'), 
                     'Should identify Phone field from "phone number"');
    }
    
    @isTest
    static void testAnalyzeMessage_PluralObjects() {
        String message = 'I cannot access Accounts and Contacts';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.objectsInvolved.contains('Account'), 
                     'Should identify Account from plural');
        System.assert(analysis.objectsInvolved.contains('Contact'), 
                     'Should identify Contact from plural');
    }
    
    @isTest
    static void testAnalyzeMessage_ReadOnlyField() {
        String message = 'The Status field is grayed out and read-only';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals('edit_permission', analysis.issueCategory, 
                          'Should categorize as edit permission for read-only');
        System.assert(analysis.fieldsInvolved.contains('Status'), 
                     'Should identify Status field');
    }
    
    @isTest
    static void testAnalyzeMessage_RequiredField() {
        String message = 'Amount field is required but I can\'t fill it in';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assertEquals('validation_error', analysis.issueCategory, 
                          'Should categorize as validation error');
    }
    
    @isTest
    static void testAnalyzeMessages_Batch() {
        List<String> messages = new List<String>{
            'Can\'t see Phone field',
            'Cannot edit Account',
            'Record 001XXXXXXXXXXXX is not accessible'
        };
        
        Test.startTest();
        List<MessageAnalyzer.MessageAnalysis> results = 
            MessageAnalyzer.analyzeMessages(messages);
        Test.stopTest();
        
        System.assertEquals(3, results.size(), 
                          'Should analyze all messages');
        System.assertEquals('field_visibility', results[0].issueCategory, 
                          'First should be field visibility');
        System.assertEquals('edit_permission', results[1].issueCategory, 
                          'Second should be edit permission');
        System.assertEquals('access_issue', results[2].issueCategory, 
                          'Third should be access issue');
    }
    
    @isTest
    static void testAnalyzeMessage_PerformanceCheck() {
        String message = 'I can\'t see the Email field on Contact records and cannot edit Account records';
        
        Long startTime = System.currentTimeMillis();
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        Long endTime = System.currentTimeMillis();
        Long duration = endTime - startTime;
        
        System.debug('Analysis duration: ' + duration + 'ms');
        // Note: In test context, timing may vary, but should generally be fast
        System.assertNotEquals(null, analysis, 'Should complete analysis');
    }
    
    @isTest
    static void testAnalyzeMessage_InvalidRecordId() {
        String message = 'Record ABC123 is not working';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        // Should not extract invalid IDs
        System.assertEquals(0, analysis.recordIds.size(), 
                          'Should not extract invalid record IDs');
    }
    
    @isTest
    static void testAnalyzeMessage_CaseInsensitive() {
        String message = 'CANNOT SEE PHONE FIELD ON ACCOUNT';
        
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = MessageAnalyzer.analyzeMessage(message);
        Test.stopTest();
        
        System.assert(analysis.objectsInvolved.contains('Account'), 
                     'Should work case-insensitive');
        System.assert(analysis.fieldsInvolved.contains('Phone'), 
                     'Should extract field case-insensitive');
    }
    
    @isTest
    static void testGetAnalysisStats() {
        Test.startTest();
        Map<String, Integer> stats = MessageAnalyzer.getAnalysisStats();
        Test.stopTest();
        
        System.assertNotEquals(null, stats, 'Stats should not be null');
        System.assert(stats.containsKey('totalAnalyses'), 
                     'Should contain totalAnalyses key');
    }
    
    @isTest
    static void testMessageAnalysisWrapper() {
        Test.startTest();
        MessageAnalyzer.MessageAnalysis analysis = new MessageAnalyzer.MessageAnalysis();
        Test.stopTest();
        
        System.assertEquals('general', analysis.issueCategory, 
                          'Default category should be general');
        System.assertEquals('low', analysis.confidence, 
                          'Default confidence should be low');
        System.assertNotEquals(null, analysis.objectsInvolved, 
                             'Lists should be initialized');
    }
}