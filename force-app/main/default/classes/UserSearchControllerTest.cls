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
 * @description Test class for UserSearchController
 * @author System
 * @date 2025
 */
@isTest
private class UserSearchControllerTest {
    
    /**
     * @description Setup test data
     */
    @testSetup
    static void setup() {
        // Test users are created automatically by Salesforce
        // We'll use existing system users for testing
    }
    
    /**
     * @description Test successful user search
     */
    @isTest
    static void testSearchUsers_Success() {
        // Arrange
        User testUser = [SELECT Name FROM User WHERE IsActive = true LIMIT 1];
        String searchTerm = testUser.Name.substring(0, 3);
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should find at least one user');
        
        // Verify result structure
        UserSearchController.UserResult firstResult = results[0];
        System.assertNotEquals(null, firstResult.id, 'User ID should not be null');
        System.assertNotEquals(null, firstResult.name, 'User name should not be null');
        System.assertNotEquals(null, firstResult.username, 'Username should not be null');
        System.assertNotEquals(null, firstResult.profileName, 'Profile name should not be null');
        System.assertEquals(true, firstResult.isActive, 'User should be active');
    }
    
    /**
     * @description Test search with empty string
     */
    @isTest
    static void testSearchUsers_EmptyString() {
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers('');
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Empty search should return no results');
    }
    
    /**
     * @description Test search with null string
     */
    @isTest
    static void testSearchUsers_NullString() {
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(null);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Null search should return no results');
    }
    
    /**
     * @description Test search with whitespace only
     */
    @isTest
    static void testSearchUsers_WhitespaceOnly() {
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers('   ');
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Whitespace only search should return no results');
    }
    
    /**
     * @description Test search with special characters
     */
    @isTest
    static void testSearchUsers_SpecialCharacters() {
        // Arrange
        String searchTerm = 'Test!@#$%^&*()';
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert - Should handle gracefully without errors
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    /**
     * @description Test search with SOSL injection attempt
     */
    @isTest
    static void testSearchUsers_SOSLInjection() {
        // Arrange
        String maliciousSearch = 'admin\' OR IsActive = false OR \'1\'=\'1';
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(maliciousSearch);
        Test.stopTest();
        
        // Assert - Should sanitize and handle safely
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    /**
     * @description Test search result limit
     */
    @isTest
    static void testSearchUsers_ResultLimit() {
        // Arrange - Search for common term that might return many results
        String searchTerm = 'User';
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert - Should not exceed max results
        System.assert(results.size() <= 50, 'Results should not exceed 50');
    }
    
    /**
     * @description Test search with very long string
     */
    @isTest
    static void testSearchUsers_LongString() {
        // Arrange - Create string longer than 100 characters
        String longSearch = 'a'.repeat(150);
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(longSearch);
        Test.stopTest();
        
        // Assert - Should handle without error
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    /**
     * @description Test getUserDetails with valid user ID
     */
    @isTest
    static void testGetUserDetails_Success() {
        // Arrange
        User testUser = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        
        // Act
        Test.startTest();
        UserSearchController.UserResult result = UserSearchController.getUserDetails(testUser.Id);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(testUser.Id, result.id, 'User ID should match');
        System.assertNotEquals(null, result.name, 'User name should not be null');
        System.assertNotEquals(null, result.username, 'Username should not be null');
        System.assertNotEquals(null, result.profileName, 'Profile name should not be null');
    }
    
    /**
     * @description Test getUserDetails with empty user ID
     */
    @isTest
    static void testGetUserDetails_EmptyId() {
        // Act & Assert
        Test.startTest();
        try {
            UserSearchController.getUserDetails('');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('cannot be empty'), 'Should have empty ID error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getUserDetails with null user ID
     */
    @isTest
    static void testGetUserDetails_NullId() {
        // Act & Assert
        Test.startTest();
        try {
            UserSearchController.getUserDetails(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('cannot be empty'), 'Should have empty ID error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getUserDetails with invalid user ID
     */
    @isTest
    static void testGetUserDetails_InvalidId() {
        // Act & Assert
        Test.startTest();
        try {
            UserSearchController.getUserDetails('005000000000000AAA');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found'), 'Should have not found error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test UserResult wrapper construction
     */
    @isTest
    static void testUserResult_Construction() {
        // Arrange
        User testUser = [
            SELECT Id, Name, Username, Profile.Name, IsActive, 
                   LastLoginDate, SmallPhotoUrl
            FROM User 
            WHERE IsActive = true 
            LIMIT 1
        ];
        
        // Act
        Test.startTest();
        UserSearchController.UserResult result = new UserSearchController.UserResult(testUser);
        Test.stopTest();
        
        // Assert
        System.assertEquals(testUser.Id, result.id, 'ID should match');
        System.assertEquals(testUser.Name, result.name, 'Name should match');
        System.assertEquals(testUser.Username, result.username, 'Username should match');
        System.assertEquals(testUser.Profile.Name, result.profileName, 'Profile name should match');
        System.assertEquals(testUser.IsActive, result.isActive, 'IsActive should match');
        System.assertEquals(testUser.LastLoginDate, result.lastLoginDate, 'LastLoginDate should match');
        System.assertEquals(testUser.SmallPhotoUrl, result.smallPhotoUrl, 'SmallPhotoUrl should match');
    }
    
    /**
     * @description Test search with partial username match
     */
    @isTest
    static void testSearchUsers_PartialUsernameMatch() {
        // Arrange
        User testUser = [SELECT Username FROM User WHERE IsActive = true LIMIT 1];
        String searchTerm = testUser.Username.substring(0, Math.min(5, testUser.Username.length()));
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should find users matching partial username');
    }
    
    /**
     * @description Test search is case insensitive
     */
    @isTest
    static void testSearchUsers_CaseInsensitive() {
        // Arrange
        User testUser = [SELECT Name FROM User WHERE IsActive = true LIMIT 1];
        String searchTerm = testUser.Name.substring(0, 3).toLowerCase();
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() > 0, 'Should find users regardless of case');
    }
    
    /**
     * @description Test that only active users are returned
     */
    @isTest
    static void testSearchUsers_OnlyActiveUsers() {
        // Arrange
        String searchTerm = 'User';
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert
        for (UserSearchController.UserResult result : results) {
            System.assertEquals(true, result.isActive, 'All returned users should be active');
        }
    }
    
    /**
     * @description Test search with numeric characters
     */
    @isTest
    static void testSearchUsers_NumericCharacters() {
        // Arrange
        String searchTerm = 'user123';
        
        // Act
        Test.startTest();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Test.stopTest();
        
        // Assert - Should handle without error
        System.assertNotEquals(null, results, 'Results should not be null');
    }
    
    /**
     * @description Test search performance with common term
     */
    @isTest
    static void testSearchUsers_Performance() {
        // Arrange
        String searchTerm = 'a';
        
        // Act
        Test.startTest();
        Long startTime = System.currentTimeMillis();
        List<UserSearchController.UserResult> results = UserSearchController.searchUsers(searchTerm);
        Long endTime = System.currentTimeMillis();
        Test.stopTest();
        
        // Assert - Query should complete
        System.assertNotEquals(null, results, 'Results should not be null');
        System.debug('Search completed in: ' + (endTime - startTime) + 'ms');
    }
}