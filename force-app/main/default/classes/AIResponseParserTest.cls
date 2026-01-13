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
 * @description Test class for AIResponseParser
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class AIResponseParserTest {
    
    @isTest
    static void testParseResponse_FullResponse() {
        String response = 'I found the issue! The Phone field exists but your profile doesn\'t have ' +
                         'permission to view it.\n\n' +
                         '**How to fix it:**\n' +
                         '1. Contact your Salesforce administrator\n' +
                         '2. Ask them to enable Field-Level Security\n' +
                         '3. Wait for the change to take effect\n\n' +
                         'Your admin: John Smith (john@company.com)\n\n' +
                         'Need more help?';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(response);
        Test.stopTest();
        
        System.assertEquals(response, parsed.rawContent, 'Should preserve raw content');
        System.assertNotEquals(null, parsed.formattedContent, 'Should have formatted content');
        System.assertEquals(3, parsed.steps.size(), 'Should extract 3 steps');
        System.assertEquals(true, parsed.isComplete, 'Should be marked as complete');
        System.assertNotEquals(null, parsed.quality, 'Should have quality assessment');
    }
    
    @isTest
    static void testParseResponse_EmptyResponse() {
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse('');
        Test.stopTest();
        
        System.assertNotEquals(null, parsed.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testHandleMarkdown_Bold() {
        String input = 'This is **bold** text and this is __also bold__.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('<strong>bold</strong>'), 
                     'Should convert **bold** to <strong>');
        System.assert(parsed.formattedContent.contains('<strong>also bold</strong>'), 
                     'Should convert __bold__ to <strong>');
    }
    
    @isTest
    static void testHandleMarkdown_Italic() {
        String input = 'This is *italic* and this is _also italic_.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('<em>italic</em>'), 
                     'Should convert *italic* to <em>');
        System.assert(parsed.formattedContent.contains('<em>also italic</em>'), 
                     'Should convert _italic_ to <em>');
    }
    
    @isTest
    static void testHandleMarkdown_InlineCode() {
        String input = 'Check the `Field-Level Security` setting.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('<code>Field-Level Security</code>'), 
                     'Should convert `code` to <code>');
    }
    
    @isTest
    static void testHandleMarkdown_LineBreaks() {
        String input = 'Line 1\nLine 2\nLine 3';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('<br/>'), 
                     'Should convert \\n to <br/>');
    }
    
    @isTest
    static void testExtractSteps() {
        String input = 'Here are the steps:\n' +
                      '1. First step\n' +
                      '2. Second step\n' +
                      '3. Third step';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(3, parsed.steps.size(), 'Should extract 3 steps');
        System.assertEquals('First step', parsed.steps[0], 'First step should match');
        System.assertEquals('Second step', parsed.steps[1], 'Second step should match');
        System.assertEquals('Third step', parsed.steps[2], 'Third step should match');
    }
    
    @isTest
    static void testExtractWarnings() {
        String input = 'Important: This requires admin access. Note that changes take effect immediately.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.warnings.size() > 0, 'Should extract warnings');
    }
    
    @isTest
    static void testExtractAdminContacts() {
        String input = 'Contact John Smith (john@company.com) or jane@company.com for help.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(2, parsed.adminContacts.size(), 'Should extract 2 contacts');
        System.assert(parsed.adminContacts[0].contains('John Smith'), 'Should include name');
        System.assert(parsed.adminContacts[0].contains('john@company.com'), 'Should include email');
    }
    
    @isTest
    static void testExtractLinks_Markdown() {
        String input = 'Check out [Salesforce Help](https://help.salesforce.com) for more info.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(1, parsed.links.size(), 'Should extract 1 link');
        System.assertEquals('Salesforce Help', parsed.links[0].text, 'Link text should match');
        System.assertEquals('https://help.salesforce.com', parsed.links[0].url, 'URL should match');
        System.assertEquals(true, parsed.links[0].isValid, 'Should be valid URL');
    }
    
    @isTest
    static void testExtractLinks_Plain() {
        String input = 'Visit https://salesforce.com for more information.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(1, parsed.links.size(), 'Should extract 1 link');
        System.assertEquals(true, parsed.links[0].isValid, 'Should be valid URL');
    }
    
    @isTest
    static void testValidateCompleteness_Complete() {
        String input = 'The issue is that your profile lacks permission. ' +
                      'To fix this, contact your admin and request access. ' +
                      'Can I help with anything else?';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(true, parsed.isComplete, 'Should be marked as complete');
    }
    
    @isTest
    static void testValidateCompleteness_Incomplete() {
        String input = 'Problem with permissions.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals(false, parsed.isComplete, 'Should be marked as incomplete');
    }
    
    @isTest
    static void testAssessQuality_High() {
        String input = 'The issue is Field-Level Security. ' +
                      'To fix: 1. Contact admin 2. Request FLS 3. Wait for approval. ' +
                      'Your admin can help. Need more assistance?';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertNotEquals(null, parsed.quality, 'Should have quality assessment');
        System.assert(parsed.quality.length > 0, 'Should have length');
        System.assertEquals(true, parsed.quality.hasSteps, 'Should have steps');
        System.assertEquals(true, parsed.quality.hasExplanation, 'Should have explanation');
    }
    
    @isTest
    static void testAssessQuality_Low() {
        String input = 'Issue found.';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assertEquals('low', parsed.quality.qualityScore, 'Should be low quality');
    }
    
    @isTest
    static void testFormatErrorResponse_WithSuggestion() {
        Test.startTest();
        String formatted = AIResponseParser.formatErrorResponse(
            'API connection failed',
            'Please check your internet connection and try again'
        );
        Test.stopTest();
        
        System.assertNotEquals(null, formatted, 'Should return formatted error');
        System.assert(formatted.contains('API connection failed'), 'Should include error message');
        System.assert(formatted.contains('check your internet'), 'Should include suggestion');
    }
    
    @isTest
    static void testFormatErrorResponse_NoSuggestion() {
        Test.startTest();
        String formatted = AIResponseParser.formatErrorResponse('Something went wrong', null);
        Test.stopTest();
        
        System.assert(formatted.contains('Something went wrong'), 'Should include error');
        System.assert(formatted.contains('Try rephrasing'), 'Should have default suggestions');
    }
    
    @isTest
    static void testEscapeHtml() {
        String input = '<script>alert("XSS")</script>';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        // The formatted content should not contain actual < or > characters
        System.assert(!parsed.formattedContent.contains('<script>'), 
                     'Should escape HTML tags');
    }
    
    @isTest
    static void testCreateFallbackResponse() {
        String rawResponse = 'Simple response text';
        
        Test.startTest();
        AIResponseParser.ParsedResponse fallback = 
            AIResponseParser.createFallbackResponse(rawResponse);
        Test.stopTest();
        
        System.assertEquals(rawResponse, fallback.rawContent, 'Should preserve raw content');
        System.assertNotEquals(null, fallback.formattedContent, 'Should have formatted content');
        System.assertEquals('low', fallback.quality.qualityScore, 'Fallback should be low quality');
    }
    
    @isTest
    static void testTruncateResponse_Short() {
        String input = 'Short response';
        
        Test.startTest();
        String truncated = AIResponseParser.truncateResponse(input, 100);
        Test.stopTest();
        
        System.assertEquals(input, truncated, 'Should not truncate short response');
    }
    
    @isTest
    static void testTruncateResponse_Long() {
        String input = 'This is a very long response that needs to be truncated. ' +
                      'It contains multiple sentences. And it goes on and on. ' +
                      'Eventually it should be cut off at a sentence boundary.';
        
        Test.startTest();
        String truncated = AIResponseParser.truncateResponse(input, 50);
        Test.stopTest();
        
        System.assert(truncated.length() <= input.length(), 'Should be truncated');
        System.assert(truncated.length() > 0, 'Should not be empty');
    }
    
    @isTest
    static void testRemoveJsonWrapper() {
        String input = '```json\n{"content": "Actual response text"}\n```';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('Actual response text'), 
                     'Should extract content from JSON wrapper');
        System.assert(!parsed.formattedContent.contains('```json'), 
                     'Should remove JSON markers');
    }
    
    @isTest
    static void testComplexMarkdown() {
        String input = 'This has **bold**, *italic*, `code`, and\n' +
                      '1. A numbered list\n' +
                      '2. With multiple items\n' +
                      '- And a bullet\n' +
                      '- List too';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(input);
        Test.stopTest();
        
        System.assert(parsed.formattedContent.contains('<strong>bold</strong>'), 'Has bold');
        System.assert(parsed.formattedContent.contains('<em>italic</em>'), 'Has italic');
        System.assert(parsed.formattedContent.contains('<code>code</code>'), 'Has code');
        System.assert(parsed.formattedContent.contains('•'), 'Has bullets');
        System.assertEquals(2, parsed.steps.size(), 'Should extract numbered list as steps');
    }
    
    @isTest
    static void testRealWorldExample() {
        String response = 'I\'ve identified the issue! The Phone field exists on Account records, but your ' +
                         'profile doesn\'t have Field-Level Security (FLS) permission to view it.\n\n' +
                         '**What\'s happening:**\n' +
                         'Field-Level Security controls which fields you can see and edit. Your "Standard User" ' +
                         'profile hasn\'t been granted access to the Phone field.\n\n' +
                         '**How to fix it:**\n' +
                         '1. Contact your Salesforce administrator\n' +
                         '2. Ask them to enable "Visible" for the Phone field on your profile\n' +
                         '3. They can do this in Setup → Object Manager → Account → Fields → Phone → ' +
                         'Set Field-Level Security\n\n' +
                         '**Who can help:**\n' +
                         'Your administrators are:\n' +
                         '- Jennifer Smith (jennifer@company.com)\n' +
                         '- Mike Chen (mike@company.com)\n\n' +
                         'Once they make the change, you\'ll be able to see the Phone field immediately. ' +
                         'Is there anything else I can help with?';
        
        Test.startTest();
        AIResponseParser.ParsedResponse parsed = AIResponseParser.parseResponse(response);
        Test.stopTest();
        
        // Validate comprehensive parsing
        System.assert(parsed.isComplete, 'Real response should be complete');
        System.assertEquals(3, parsed.steps.size(), 'Should extract all 3 steps');
        System.assertEquals(2, parsed.adminContacts.size(), 'Should find both admin contacts');
        System.assert(parsed.formattedContent.contains('<strong>'), 'Should have markdown formatting');
        System.assert(parsed.quality.qualityScore == 'high' || 
                     parsed.quality.qualityScore == 'medium', 
                     'Real response should be medium to high quality');
    }
}