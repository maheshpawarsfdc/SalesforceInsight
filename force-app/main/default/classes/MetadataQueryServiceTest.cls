/**
 * @description Test class for MetadataQueryService
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class MetadataQueryServiceTest {
    
    @isTest
    static void testCheckFieldExists_ValidField() {
        Test.startTest();
        Boolean exists = MetadataQueryService.checkFieldExists('Account', 'Name');
        Test.stopTest();
        
        System.assertEquals(true, exists, 'Account.Name field should exist');
    }
    
    @isTest
    static void testCheckFieldExists_InvalidField() {
        Test.startTest();
        Boolean exists = MetadataQueryService.checkFieldExists('Account', 'InvalidField__c');
        Test.stopTest();
        
        System.assertEquals(false, exists, 'Invalid field should not exist');
    }
    
    @isTest
    static void testCheckFieldExists_BlankInputs() {
        Test.startTest();
        Boolean exists1 = MetadataQueryService.checkFieldExists('', 'Name');
        Boolean exists2 = MetadataQueryService.checkFieldExists('Account', '');
        Boolean exists3 = MetadataQueryService.checkFieldExists(null, 'Name');
        Test.stopTest();
        
        System.assertEquals(false, exists1, 'Should return false for blank object');
        System.assertEquals(false, exists2, 'Should return false for blank field');
        System.assertEquals(false, exists3, 'Should return false for null object');
    }
    
    @isTest
    static void testCheckFieldExists_CaseInsensitive() {
        Test.startTest();
        Boolean exists1 = MetadataQueryService.checkFieldExists('Account', 'name');
        Boolean exists2 = MetadataQueryService.checkFieldExists('Account', 'NAME');
        Boolean exists3 = MetadataQueryService.checkFieldExists('account', 'Name');
        Test.stopTest();
        
        System.assertEquals(true, exists1, 'Should handle lowercase field name');
        System.assertEquals(true, exists2, 'Should handle uppercase field name');
        System.assertEquals(true, exists3, 'Should handle lowercase object name');
    }
    
    @isTest
    static void testCheckObjectExists_ValidObject() {
        Test.startTest();
        Boolean exists = MetadataQueryService.checkObjectExists('Account');
        Test.stopTest();
        
        System.assertEquals(true, exists, 'Account object should exist');
    }
    
    @isTest
    static void testCheckObjectExists_InvalidObject() {
        Test.startTest();
        Boolean exists = MetadataQueryService.checkObjectExists('InvalidObject__c');
        Test.stopTest();
        
        System.assertEquals(false, exists, 'Invalid object should not exist');
    }
    
    @isTest
    static void testCheckObjectExists_BlankInput() {
        Test.startTest();
        Boolean exists1 = MetadataQueryService.checkObjectExists('');
        Boolean exists2 = MetadataQueryService.checkObjectExists(null);
        Test.stopTest();
        
        System.assertEquals(false, exists1, 'Should return false for blank object');
        System.assertEquals(false, exists2, 'Should return false for null object');
    }
    
    @isTest
    static void testCheckObjectExists_CustomObject() {
        Test.startTest();
        Boolean exists = MetadataQueryService.checkObjectExists('Diagnostic_Session__c');
        Test.stopTest();
        
        System.assertEquals(true, exists, 'Custom object should exist');
    }
    
    @isTest
    static void testGetPageLayoutFields_ValidObject() {
        Test.startTest();
        List<String> fields = MetadataQueryService.getPageLayoutFields('Account', 'Account Layout');
        Test.stopTest();
        
        System.assertNotEquals(null, fields, 'Should return field list');
        System.assert(fields.size() > 0, 'Should have at least some fields');
        System.assert(fields.contains('Name'), 'Should include Name field');
    }
    
    @isTest
    static void testGetPageLayoutFields_InvalidObject() {
        Test.startTest();
        List<String> fields = MetadataQueryService.getPageLayoutFields('InvalidObject__c', 'Some Layout');
        Test.stopTest();
        
        System.assertNotEquals(null, fields, 'Should return empty list, not null');
        System.assertEquals(0, fields.size(), 'Should return empty list for invalid object');
    }
    
    @isTest
    static void testGetPageLayoutFields_BlankInput() {
        Test.startTest();
        List<String> fields = MetadataQueryService.getPageLayoutFields('', 'Some Layout');
        Test.stopTest();
        
        System.assertNotEquals(null, fields, 'Should return empty list');
        System.assertEquals(0, fields.size(), 'Should return empty list for blank object');
    }
    
    @isTest
    static void testGetValidationRules_ValidObject() {
        Test.startTest();
        List<MetadataQueryService.ValidationRuleInfo> rules = 
            MetadataQueryService.getValidationRules('Account');
        Test.stopTest();
        
        System.assertNotEquals(null, rules, 'Should return list (may be empty)');
        // Validation rules may or may not exist depending on org setup
    }
    
    @isTest
    static void testGetValidationRules_InvalidObject() {
        Test.startTest();
        List<MetadataQueryService.ValidationRuleInfo> rules = 
            MetadataQueryService.getValidationRules('InvalidObject__c');
        Test.stopTest();
        
        System.assertNotEquals(null, rules, 'Should return empty list');
        System.assertEquals(0, rules.size(), 'Should return empty list for invalid object');
    }
    
    @isTest
    static void testGetValidationRules_BlankInput() {
        Test.startTest();
        List<MetadataQueryService.ValidationRuleInfo> rules = 
            MetadataQueryService.getValidationRules('');
        Test.stopTest();
        
        System.assertNotEquals(null, rules, 'Should return empty list');
        System.assertEquals(0, rules.size(), 'Should return empty list for blank object');
    }
    
    @isTest
    static void testGetFieldMap_ValidObject() {
        Test.startTest();
        Map<String, Schema.SObjectField> fieldMap = 
            MetadataQueryService.getFieldMap('Account');
        Test.stopTest();
        
        System.assertNotEquals(null, fieldMap, 'Should return field map');
        System.assert(fieldMap.size() > 0, 'Should have fields');
        System.assert(fieldMap.containsKey('name'), 'Should contain Name field');
    }
    
    @isTest
    static void testGetFieldMap_InvalidObject() {
        Test.startTest();
        Map<String, Schema.SObjectField> fieldMap = 
            MetadataQueryService.getFieldMap('InvalidObject__c');
        Test.stopTest();
        
        System.assertEquals(null, fieldMap, 'Should return null for invalid object');
    }
    
    @isTest
    static void testGetFieldMap_BlankInput() {
        Test.startTest();
        Map<String, Schema.SObjectField> fieldMap = 
            MetadataQueryService.getFieldMap('');
        Test.stopTest();
        
        System.assertEquals(null, fieldMap, 'Should return null for blank object');
    }
    
    @isTest
    static void testGetFieldMap_Caching() {
        Test.startTest();
        // First call - not cached
        Map<String, Schema.SObjectField> fieldMap1 = 
            MetadataQueryService.getFieldMap('Contact');
        
        // Second call - should be cached
        Map<String, Schema.SObjectField> fieldMap2 = 
            MetadataQueryService.getFieldMap('Contact');
        Test.stopTest();
        
        System.assertNotEquals(null, fieldMap1, 'First call should return field map');
        System.assertNotEquals(null, fieldMap2, 'Second call should return field map');
        System.assertEquals(fieldMap1.size(), fieldMap2.size(), 'Both calls should return same data');
    }
    
    @isTest
    static void testGetObjectDescribe_ValidObject() {
        Test.startTest();
        Schema.DescribeSObjectResult describe = 
            MetadataQueryService.getObjectDescribe('Account');
        Test.stopTest();
        
        System.assertNotEquals(null, describe, 'Should return describe result');
        System.assertEquals('Account', describe.getName(), 'Object name should match');
    }
    
    @isTest
    static void testGetObjectDescribe_InvalidObject() {
        Test.startTest();
        Schema.DescribeSObjectResult describe = 
            MetadataQueryService.getObjectDescribe('InvalidObject__c');
        Test.stopTest();
        
        System.assertEquals(null, describe, 'Should return null for invalid object');
    }
    
    @isTest
    static void testGetFieldDescribe_ValidField() {
        Test.startTest();
        Schema.DescribeFieldResult describe = 
            MetadataQueryService.getFieldDescribe('Account', 'Name');
        Test.stopTest();
        
        System.assertNotEquals(null, describe, 'Should return field describe');
        System.assertEquals('Name', describe.getName(), 'Field name should match');
    }
    
    @isTest
    static void testGetFieldDescribe_InvalidField() {
        Test.startTest();
        Schema.DescribeFieldResult describe = 
            MetadataQueryService.getFieldDescribe('Account', 'InvalidField__c');
        Test.stopTest();
        
        System.assertEquals(null, describe, 'Should return null for invalid field');
    }
    
    @isTest
    static void testIsFieldRequired_RequiredField() {
        Test.startTest();
        Boolean isRequired = MetadataQueryService.isFieldRequired('Account', 'Name');
        Test.stopTest();
        
        System.assertEquals(true, isRequired, 'Account.Name should be required');
    }
    
    @isTest
    static void testIsFieldRequired_OptionalField() {
        Test.startTest();
        Boolean isRequired = MetadataQueryService.isFieldRequired('Account', 'Phone');
        Test.stopTest();
        
        System.assertEquals(false, isRequired, 'Account.Phone should be optional');
    }
    
    @isTest
    static void testIsFieldRequired_InvalidField() {
        Test.startTest();
        Boolean isRequired = MetadataQueryService.isFieldRequired('Account', 'InvalidField__c');
        Test.stopTest();
        
        System.assertEquals(false, isRequired, 'Should return false for invalid field');
    }
    
    @isTest
    static void testGetRequiredFields_ValidObject() {
        Test.startTest();
        List<String> requiredFields = MetadataQueryService.getRequiredFields('Account');
        Test.stopTest();
        
        System.assertNotEquals(null, requiredFields, 'Should return list');
        System.assert(requiredFields.size() > 0, 'Should have at least some required fields');
        System.assert(requiredFields.contains('Name'), 'Should include Name field');
    }
    
    @isTest
    static void testGetRequiredFields_InvalidObject() {
        Test.startTest();
        List<String> requiredFields = MetadataQueryService.getRequiredFields('InvalidObject__c');
        Test.stopTest();
        
        System.assertNotEquals(null, requiredFields, 'Should return empty list');
        System.assertEquals(0, requiredFields.size(), 'Should return empty list for invalid object');
    }
    
    @isTest
    static void testClearCache() {
        // Populate caches
        MetadataQueryService.checkObjectExists('Account');
        MetadataQueryService.getFieldMap('Contact');
        MetadataQueryService.getObjectDescribe('Opportunity');
        
        Test.startTest();
        // Clear caches
        MetadataQueryService.clearCache();
        
        // Verify caches are cleared by checking stats
        Map<String, Integer> stats = MetadataQueryService.getCacheStats();
        Test.stopTest();
        
        System.assertEquals(0, stats.get('globalDescribeLoaded'), 'Global describe should be cleared');
        System.assertEquals(0, stats.get('fieldMapsCached'), 'Field maps should be cleared');
        System.assertEquals(0, stats.get('objectDescribesCached'), 'Object describes should be cleared');
    }
    
    @isTest
    static void testGetCacheStats() {
        // Populate caches
        MetadataQueryService.getFieldMap('Account');
        MetadataQueryService.getFieldMap('Contact');
        MetadataQueryService.getObjectDescribe('Opportunity');
        
        Test.startTest();
        Map<String, Integer> stats = MetadataQueryService.getCacheStats();
        Test.stopTest();
        
        System.assertNotEquals(null, stats, 'Should return stats map');
        System.assert(stats.containsKey('globalDescribeLoaded'), 'Should include global describe stat');
        System.assert(stats.containsKey('fieldMapsCached'), 'Should include field maps stat');
        System.assert(stats.containsKey('objectDescribesCached'), 'Should include object describes stat');
        
        System.assertEquals(1, stats.get('globalDescribeLoaded'), 'Global describe should be loaded');
        System.assert(stats.get('fieldMapsCached') >= 2, 'Should have cached at least 2 field maps');
    }
    
    @isTest
    static void testMultipleObjects() {
        Test.startTest();
        Boolean accountExists = MetadataQueryService.checkObjectExists('Account');
        Boolean contactExists = MetadataQueryService.checkObjectExists('Contact');
        Boolean oppExists = MetadataQueryService.checkObjectExists('Opportunity');
        Boolean leadExists = MetadataQueryService.checkObjectExists('Lead');
        Boolean caseExists = MetadataQueryService.checkObjectExists('Case');
        Test.stopTest();
        
        System.assertEquals(true, accountExists, 'Account should exist');
        System.assertEquals(true, contactExists, 'Contact should exist');
        System.assertEquals(true, oppExists, 'Opportunity should exist');
        System.assertEquals(true, leadExists, 'Lead should exist');
        System.assertEquals(true, caseExists, 'Case should exist');
    }
    
    @isTest
    static void testMultipleFieldsOnSameObject() {
        Test.startTest();
        Boolean nameExists = MetadataQueryService.checkFieldExists('Account', 'Name');
        Boolean phoneExists = MetadataQueryService.checkFieldExists('Account', 'Phone');
        Boolean industryExists = MetadataQueryService.checkFieldExists('Account', 'Industry');
        Boolean emailExists = MetadataQueryService.checkFieldExists('Account', 'Email__c');
        Test.stopTest();
        
        System.assertEquals(true, nameExists, 'Name field should exist');
        System.assertEquals(true, phoneExists, 'Phone field should exist');
        System.assertEquals(true, industryExists, 'Industry field should exist');
        // Email__c custom field may or may not exist
    }
    
    @isTest
    static void testCustomObject() {
        Test.startTest();
        Boolean objectExists = MetadataQueryService.checkObjectExists('Diagnostic_Session__c');
        
        if (objectExists) {
            Map<String, Schema.SObjectField> fieldMap = 
                MetadataQueryService.getFieldMap('Diagnostic_Session__c');
            List<String> fields = 
                MetadataQueryService.getPageLayoutFields('Diagnostic_Session__c', null);
            
            System.assertNotEquals(null, fieldMap, 'Should return field map for custom object');
            System.assertNotEquals(null, fields, 'Should return fields for custom object');
        }
        Test.stopTest();
        
        System.assertEquals(true, objectExists, 'Diagnostic_Session__c should exist');
    }
}