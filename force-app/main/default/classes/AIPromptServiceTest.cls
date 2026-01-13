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
 * @description Test class for AIPromptService
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class AIPromptServiceTest {
    
    @isTest
    static void testGetMainSystemPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getMainSystemPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.length() > 100, 'Prompt should be substantial');
        System.assert(prompt.contains('Salesforce'), 'Should mention Salesforce');
        System.assert(prompt.contains('diagnostic'), 'Should mention diagnostic');
        System.assert(prompt.contains('YOUR ROLE'), 'Should have role section');
        System.assert(prompt.contains('RESPONSE FORMAT'), 'Should have format section');
        System.assert(prompt.contains('TONE'), 'Should have tone section');
    }
    
    @isTest
    static void testGetFieldVisibilityPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getFieldVisibilityPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('field'), 'Should mention field');
        System.assert(prompt.contains('Field-Level Security'), 'Should mention FLS');
        System.assert(prompt.contains('page layout'), 'Should mention page layout');
    }
    
    @isTest
    static void testGetEditPermissionPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getEditPermissionPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('edit'), 'Should mention edit');
        System.assert(prompt.contains('approval'), 'Should mention approval process');
        System.assert(prompt.contains('locked'), 'Should mention locked records');
    }
    
    @isTest
    static void testGetRecordAccessPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getRecordAccessPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('access'), 'Should mention access');
        System.assert(prompt.contains('sharing'), 'Should mention sharing rules');
        System.assert(prompt.contains('ownership'), 'Should mention ownership');
    }
    
    @isTest
    static void testGetSaveErrorPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getSaveErrorPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('save'), 'Should mention save');
        System.assert(prompt.contains('validation'), 'Should mention validation');
        System.assert(prompt.contains('required'), 'Should mention required fields');
    }
    
    @isTest
    static void testGetNewUserPrompt() {
        Test.startTest();
        String prompt = AIPromptService.getNewUserPrompt();
        Test.stopTest();
        
        System.assertNotEquals(null, prompt, 'Prompt should not be null');
        System.assert(prompt.contains('patient'), 'Should emphasize patience');
        System.assert(prompt.contains('educational'), 'Should be educational');
        System.assert(prompt.contains('profile'), 'Should explain profiles');
    }
    
    @isTest
    static void testBuildCompletePrompt_AllParameters() {
        String basePrompt = 'Base system prompt';
        String scenarioPrompt = 'Scenario guidance';
        String diagnosticResults = 'Diagnostic data';
        String conversationContext = 'Previous messages';
        
        Test.startTest();
        String completePrompt = AIPromptService.buildCompletePrompt(
            basePrompt,
            scenarioPrompt,
            diagnosticResults,
            conversationContext
        );
        Test.stopTest();
        
        System.assertNotEquals(null, completePrompt, 'Complete prompt should not be null');
        System.assert(completePrompt.contains(basePrompt), 'Should include base prompt');
        System.assert(completePrompt.contains(scenarioPrompt), 'Should include scenario prompt');
        System.assert(completePrompt.contains(diagnosticResults), 'Should include diagnostic results');
        System.assert(completePrompt.contains(conversationContext), 'Should include conversation context');
    }
    
    @isTest
    static void testBuildCompletePrompt_MinimalParameters() {
        String basePrompt = 'Base system prompt';
        
        Test.startTest();
        String completePrompt = AIPromptService.buildCompletePrompt(
            basePrompt,
            null,
            null,
            null
        );
        Test.stopTest();
        
        System.assertNotEquals(null, completePrompt, 'Complete prompt should not be null');
        System.assert(completePrompt.contains(basePrompt), 'Should include base prompt');
    }
    
    @isTest
    static void testFormatDiagnosticResults_ObjectOnly() {
        Map<String, Object> diagnosticData = new Map<String, Object>();
        
        Map<String, Object> objPerms = new Map<String, Object>{
            'isAccessible' => true,
            'isCreateable' => false,
            'isUpdateable' => true,
            'isDeletable' => false,
            'profileName' => 'Standard User'
        };
        diagnosticData.put('objectPermissions', objPerms);
        
        Test.startTest();
        String formatted = AIPromptService.formatDiagnosticResults(
            'Account',
            null,
            UserInfo.getUserId(),
            diagnosticData
        );
        Test.stopTest();
        
        System.assertNotEquals(null, formatted, 'Formatted result should not be null');
        System.assert(formatted.contains('Account'), 'Should mention Account');
        System.assert(formatted.contains('Standard User'), 'Should mention profile');
        System.assert(formatted.contains('Can Read'), 'Should include read permission');
    }
    
    @isTest
    static void testFormatDiagnosticResults_WithField() {
        Map<String, Object> diagnosticData = new Map<String, Object>();
        
        Map<String, Object> fieldPerms = new Map<String, Object>{
            'isAccessible' => false,
            'isUpdateable' => false
        };
        diagnosticData.put('fieldPermissions', fieldPerms);
        
        Test.startTest();
        String formatted = AIPromptService.formatDiagnosticResults(
            'Account',
            'Phone',
            UserInfo.getUserId(),
            diagnosticData
        );
        Test.stopTest();
        
        System.assertNotEquals(null, formatted, 'Formatted result should not be null');
        System.assert(formatted.contains('Account.Phone'), 'Should mention field');
        System.assert(formatted.contains('FIELD-LEVEL SECURITY'), 'Should have FLS section');
    }
    
    @isTest
    static void testFormatDiagnosticResults_WithRecordAccess() {
        Map<String, Object> diagnosticData = new Map<String, Object>();
        
        Map<String, Object> recAccess = new Map<String, Object>{
            'hasReadAccess' => true,
            'hasEditAccess' => false,
            'hasDeleteAccess' => false
        };
        diagnosticData.put('recordAccess', recAccess);
        
        Test.startTest();
        String formatted = AIPromptService.formatDiagnosticResults(
            'Account',
            null,
            UserInfo.getUserId(),
            diagnosticData
        );
        Test.stopTest();
        
        System.assert(formatted.contains('RECORD ACCESS'), 'Should have record access section');
        System.assert(formatted.contains('Can View Record'), 'Should mention view access');
    }
    
    @isTest
    static void testFormatConversationContext_MultipleMessages() {
        List<Map<String, String>> messages = new List<Map<String, String>>();
        
        messages.add(new Map<String, String>{
            'role' => 'user',
            'content' => 'I can\'t see a field'
        });
        messages.add(new Map<String, String>{
            'role' => 'assistant',
            'content' => 'Let me check that for you'
        });
        messages.add(new Map<String, String>{
            'role' => 'user',
            'content' => 'It\'s the Phone field'
        });
        
        Test.startTest();
        String context = AIPromptService.formatConversationContext(messages);
        Test.stopTest();
        
        System.assertNotEquals(null, context, 'Context should not be null');
        System.assert(context.contains('User:'), 'Should label user messages');
        System.assert(context.contains('Assistant:'), 'Should label assistant messages');
        System.assert(context.contains('Phone field'), 'Should include message content');
    }
    
    @isTest
    static void testFormatConversationContext_EmptyList() {
        Test.startTest();
        String context = AIPromptService.formatConversationContext(new List<Map<String, String>>());
        Test.stopTest();
        
        System.assertEquals('', context, 'Should return empty string for empty list');
    }
    
    @isTest
    static void testFormatConversationContext_NullList() {
        Test.startTest();
        String context = AIPromptService.formatConversationContext(null);
        Test.stopTest();
        
        System.assertEquals('', context, 'Should return empty string for null list');
    }
    
    @isTest
    static void testGetScenarioPrompt_AllTypes() {
        Test.startTest();
        String fieldVis = AIPromptService.getScenarioPrompt('field_visibility');
        String editPerm = AIPromptService.getScenarioPrompt('edit_permission');
        String recAccess = AIPromptService.getScenarioPrompt('record_access');
        String saveError = AIPromptService.getScenarioPrompt('save_error');
        String newUser = AIPromptService.getScenarioPrompt('new_user');
        String unknown = AIPromptService.getScenarioPrompt('unknown_type');
        Test.stopTest();
        
        System.assertNotEquals('', fieldVis, 'Should return field visibility prompt');
        System.assertNotEquals('', editPerm, 'Should return edit permission prompt');
        System.assertNotEquals('', recAccess, 'Should return record access prompt');
        System.assertNotEquals('', saveError, 'Should return save error prompt');
        System.assertNotEquals('', newUser, 'Should return new user prompt');
        System.assertEquals('', unknown, 'Should return empty for unknown type');
    }
    
    @isTest
    static void testGetScenarioPrompt_CaseInsensitive() {
        Test.startTest();
        String lower = AIPromptService.getScenarioPrompt('field_visibility');
        String upper = AIPromptService.getScenarioPrompt('FIELD_VISIBILITY');
        String mixed = AIPromptService.getScenarioPrompt('Field_Visibility');
        Test.stopTest();
        
        System.assertEquals(lower, upper, 'Should be case insensitive');
        System.assertEquals(lower, mixed, 'Should be case insensitive');
    }
    
    @isTest
    static void testValidatePromptLength_Valid() {
        String shortPrompt = 'This is a short prompt';
        
        Test.startTest();
        Boolean valid = AIPromptService.validatePromptLength(shortPrompt);
        Test.stopTest();
        
        System.assertEquals(true, valid, 'Short prompt should be valid');
    }
    
    @isTest
    static void testValidatePromptLength_TooLong() {
        // Create a very long prompt (over 8000 characters)
        String longPrompt = '';
        for (Integer i = 0; i < 200; i++) {
            longPrompt += 'This is a very long prompt that exceeds the token limit. ';
        }
        
        Test.startTest();
        Boolean valid = AIPromptService.validatePromptLength(longPrompt);
        Test.stopTest();
        
        System.assertEquals(false, valid, 'Very long prompt should be invalid');
    }
    
    @isTest
    static void testValidatePromptLength_Blank() {
        Test.startTest();
        Boolean valid1 = AIPromptService.validatePromptLength('');
        Boolean valid2 = AIPromptService.validatePromptLength(null);
        Test.stopTest();
        
        System.assertEquals(false, valid1, 'Blank prompt should be invalid');
        System.assertEquals(false, valid2, 'Null prompt should be invalid');
    }
    
    @isTest
    static void testGetPromptVersion() {
        Test.startTest();
        String version = AIPromptService.getPromptVersion();
        Test.stopTest();
        
        System.assertNotEquals(null, version, 'Version should not be null');
        System.assert(version.length() > 0, 'Version should not be empty');
    }
    
    @isTest
    static void testLogPromptUsage() {
        Test.startTest();
        // Should not throw any errors
        AIPromptService.logPromptUsage('main_system', 'field_visibility', 150);
        AIPromptService.logPromptUsage('scenario', 'edit_permission', 200);
        Test.stopTest();
        
        // Logging method should complete without errors
        System.assert(true, 'Logging should complete successfully');
    }
    
    @isTest
    static void testFullWorkflow() {
        // Simulate a complete workflow
        Test.startTest();
        
        // 1. Get main prompt
        String mainPrompt = AIPromptService.getMainSystemPrompt();
        System.assertNotEquals(null, mainPrompt, 'Main prompt should exist');
        
        // 2. Get scenario prompt
        String scenarioPrompt = AIPromptService.getScenarioPrompt('field_visibility');
        System.assertNotEquals('', scenarioPrompt, 'Scenario prompt should exist');
        
        // 3. Format diagnostic results
        Map<String, Object> diagnostics = new Map<String, Object>();
        diagnostics.put('objectPermissions', new Map<String, Object>{
            'isAccessible' => true,
            'profileName' => 'Standard User'
        });
        
        String diagnosticResults = AIPromptService.formatDiagnosticResults(
            'Account',
            'Phone',
            UserInfo.getUserId(),
            diagnostics
        );
        System.assertNotEquals(null, diagnosticResults, 'Diagnostic results should be formatted');
        
        // 4. Format conversation
        List<Map<String, String>> messages = new List<Map<String, String>>();
        messages.add(new Map<String, String>{
            'role' => 'user',
            'content' => 'I can\'t see the Phone field'
        });
        
        String context = AIPromptService.formatConversationContext(messages);
        System.assertNotEquals('', context, 'Context should be formatted');
        
        // 5. Build complete prompt
        String completePrompt = AIPromptService.buildCompletePrompt(
            mainPrompt,
            scenarioPrompt,
            diagnosticResults,
            context
        );
        System.assertNotEquals(null, completePrompt, 'Complete prompt should be built');
        
        // 6. Validate length
        Boolean valid = AIPromptService.validatePromptLength(completePrompt);
        System.assertEquals(true, valid, 'Complete prompt should be valid length');
        
        Test.stopTest();
    }
}