/**
 * @description Test class for SalesforceDiagnosticService
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class SalesforceDiagnosticServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test user with Standard User profile
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@testorg.com',
            IsActive = true
        );
        insert testUser;
        
        // Create test account for record access checks
        Account testAccount = new Account(Name = 'Test Account', OwnerId = testUser.Id);
        insert testAccount;
        
        // Create test contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id
        );
        insert testContact;
    }
    
    @isTest
    static void testCheckObjectPermissions_Success() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.ObjectPermissionResult result = 
            SalesforceDiagnosticService.checkObjectPermissions('Account', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Account', result.objectName, 'Object name should match');
        System.assertEquals(testUser.Id, result.userId, 'User ID should match');
        // Permission results will depend on profile setup
    }
    
    @isTest
    static void testCheckObjectPermissions_InvalidObject() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.ObjectPermissionResult result = 
            SalesforceDiagnosticService.checkObjectPermissions('InvalidObject__c', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        System.assert(result.errorMessage.contains('does not exist'), 'Should indicate object does not exist');
    }
    
    @isTest
    static void testCheckObjectPermissions_BlankObjectName() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.ObjectPermissionResult result = 
            SalesforceDiagnosticService.checkObjectPermissions('', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        System.assert(result.errorMessage.contains('cannot be blank'), 'Should indicate blank input');
    }
    
    @isTest
    static void testCheckObjectPermissions_NullUserId() {
        Test.startTest();
        SalesforceDiagnosticService.ObjectPermissionResult result = 
            SalesforceDiagnosticService.checkObjectPermissions('Account', null);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        System.assert(result.errorMessage.contains('cannot be null'), 'Should indicate null user');
    }
    
    @isTest
    static void testCheckFieldLevelSecurity_Success() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.FieldPermissionResult result = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Account', 'Name', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Account', result.objectName, 'Object name should match');
        System.assertEquals('Name', result.fieldName, 'Field name should match');
        System.assertEquals(testUser.Id, result.userId, 'User ID should match');
    }
    
    @isTest
    static void testCheckFieldLevelSecurity_InvalidField() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.FieldPermissionResult result = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Account', 'InvalidField__c', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        System.assert(result.errorMessage.contains('does not exist'), 'Should indicate field does not exist');
    }
    
    @isTest
    static void testCheckFieldLevelSecurity_BlankInputs() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.FieldPermissionResult result = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('', '', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testCheckFieldLevelSecurity_NullUserId() {
        Test.startTest();
        SalesforceDiagnosticService.FieldPermissionResult result = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Account', 'Name', null);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testCheckRecordAccess_Success() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.RecordAccess result = 
            SalesforceDiagnosticService.checkRecordAccess(testAccount.Id, testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(testAccount.Id, result.recordId, 'Record ID should match');
        System.assertEquals(testUser.Id, result.userId, 'User ID should match');
    }
    
    @isTest
    static void testCheckRecordAccess_DifferentUser() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        
        // Check access for current running user (different from record owner)
        Test.startTest();
        SalesforceDiagnosticService.RecordAccess result = 
            SalesforceDiagnosticService.checkRecordAccess(testAccount.Id, UserInfo.getUserId());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // Access will depend on sharing settings
    }
    
    @isTest
    static void testCheckRecordAccess_NullRecordId() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.RecordAccess result = 
            SalesforceDiagnosticService.checkRecordAccess(null, testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
        System.assert(result.errorMessage.contains('cannot be null'), 'Should indicate null record');
    }
    
    @isTest
    static void testCheckRecordAccess_NullUserId() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.RecordAccess result = 
            SalesforceDiagnosticService.checkRecordAccess(testAccount.Id, null);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testGetUserProfile_Success() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.ProfileInfo result = 
            SalesforceDiagnosticService.getUserProfile(testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(testUser.Id, result.userId, 'User ID should match');
        System.assertNotEquals(null, result.profileName, 'Profile name should be populated');
        System.assertEquals(null, result.errorMessage, 'Should not have error message');
        System.assertEquals(true, result.isActive, 'Test user should be active');
    }
    
    @isTest
    static void testGetUserProfile_NullUserId() {
        Test.startTest();
        SalesforceDiagnosticService.ProfileInfo result = 
            SalesforceDiagnosticService.getUserProfile(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result.errorMessage, 'Should have error message');
    }
    
    @isTest
    static void testGetUserProfile_CurrentUser() {
        Test.startTest();
        SalesforceDiagnosticService.ProfileInfo result = 
            SalesforceDiagnosticService.getUserProfile(UserInfo.getUserId());
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(UserInfo.getUserId(), result.userId, 'User ID should match');
        System.assertNotEquals(null, result.profileName, 'Profile name should be populated');
    }
    
    @isTest
    static void testGetUserPermissionSets_Success() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        List<SalesforceDiagnosticService.PermissionSetInfo> result = 
            SalesforceDiagnosticService.getUserPermissionSets(testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        // User may or may not have permission sets assigned
    }
    
    @isTest
    static void testGetUserPermissionSets_NullUserId() {
        Test.startTest();
        List<SalesforceDiagnosticService.PermissionSetInfo> result = 
            SalesforceDiagnosticService.getUserPermissionSets(null);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.size(), 'Should return empty list for null user');
    }
    
    @isTest
    static void testBulkCheckObjectPermissions() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        Set<Id> userIds = new Set<Id>{testUser.Id, UserInfo.getUserId()};
        
        Test.startTest();
        Map<Id, SalesforceDiagnosticService.ObjectPermissionResult> results = 
            SalesforceDiagnosticService.bulkCheckObjectPermissions('Account', userIds);
        Test.stopTest();
        
        System.assertEquals(2, results.size(), 'Should have results for 2 users');
        System.assert(results.containsKey(testUser.Id), 'Should contain test user');
        System.assert(results.containsKey(UserInfo.getUserId()), 'Should contain current user');
    }
    
    @isTest
    static void testBulkCheckFieldPermissions() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        Set<String> fieldNames = new Set<String>{'Name', 'Industry', 'Phone'};
        
        Test.startTest();
        Map<String, SalesforceDiagnosticService.FieldPermissionResult> results = 
            SalesforceDiagnosticService.bulkCheckFieldPermissions('Account', fieldNames, testUser.Id);
        Test.stopTest();
        
        System.assertEquals(3, results.size(), 'Should have results for 3 fields');
        System.assert(results.containsKey('Name'), 'Should contain Name field');
        System.assert(results.containsKey('Industry'), 'Should contain Industry field');
        System.assert(results.containsKey('Phone'), 'Should contain Phone field');
    }
    
    @isTest
    static void testCheckObjectPermissions_CustomObject() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        // Test with Diagnostic_Session__c custom object
        SalesforceDiagnosticService.ObjectPermissionResult result = 
            SalesforceDiagnosticService.checkObjectPermissions('Diagnostic_Session__c', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Diagnostic_Session__c', result.objectName, 'Object name should match');
    }
    
    @isTest
    static void testCheckFieldPermissions_MultipleFields() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.FieldPermissionResult result1 = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Contact', 'FirstName', testUser.Id);
        SalesforceDiagnosticService.FieldPermissionResult result2 = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Contact', 'LastName', testUser.Id);
        SalesforceDiagnosticService.FieldPermissionResult result3 = 
            SalesforceDiagnosticService.checkFieldLevelSecurity('Contact', 'Email', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result1, 'FirstName result should not be null');
        System.assertNotEquals(null, result2, 'LastName result should not be null');
        System.assertNotEquals(null, result3, 'Email result should not be null');
    }
    
    @isTest
    static void testCacheClearing() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        
        Test.startTest();
        // First call - no cache
        SalesforceDiagnosticService.ObjectPermissionResult result1 = 
            SalesforceDiagnosticService.checkObjectPermissions('Account', testUser.Id);
        
        // Clear cache
        SalesforceDiagnosticService.clearCache();
        
        // Second call - cache cleared
        SalesforceDiagnosticService.ObjectPermissionResult result2 = 
            SalesforceDiagnosticService.checkObjectPermissions('Account', testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result1, 'First result should not be null');
        System.assertNotEquals(null, result2, 'Second result should not be null');
    }
    
    @isTest
    static void testRecordAccess_MultipleRecords() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'Testing' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Contact' LIMIT 1];
        
        Test.startTest();
        SalesforceDiagnosticService.RecordAccess accountAccess = 
            SalesforceDiagnosticService.checkRecordAccess(testAccount.Id, testUser.Id);
        SalesforceDiagnosticService.RecordAccess contactAccess = 
            SalesforceDiagnosticService.checkRecordAccess(testContact.Id, testUser.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, accountAccess, 'Account access result should not be null');
        System.assertNotEquals(null, contactAccess, 'Contact access result should not be null');
    }
}