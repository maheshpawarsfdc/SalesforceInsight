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
 * @description Test class for MetadataRetriever
 * @author System
 * @date 2025
 */
@isTest
private class MetadataRetrieverTest {
    
    /**
     * @description Mock HTTP response for Tooling API
     */
    private class MockToolingAPIResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String responseBody;
        private Integer callCount = 0;
        
        public MockToolingAPIResponse(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }
        
        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            HTTPResponse res = new HTTPResponse();
            res.setStatusCode(statusCode);
            res.setBody(responseBody);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }
    
    /**
     * @description Mock for transient server errors (500) that retry
     */
    private class MockRetryResponse implements HttpCalloutMock {
        private Integer callCount = 0;
        
        public HTTPResponse respond(HTTPRequest req) {
            callCount++;
            HTTPResponse res = new HTTPResponse();
            
            // Fail first 2 attempts, succeed on 3rd
            if (callCount < 3) {
                res.setStatusCode(500);
                res.setBody('{"error": "Internal Server Error"}');
            } else {
                res.setStatusCode(200);
                res.setBody('{"records": [{"Id": "01p000000000001", "Name": "TestClass"}]}');
            }
            
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }
    
    @testSetup
    static void setup() {
        // Setup test data if needed
    }
    
    /**
     * @description Test successful Tooling API query
     */
    @isTest
    static void testQueryToolingAPI_Success() {
        // Arrange
        String query = 'SELECT Id, Name FROM ApexClass LIMIT 1';
        String mockResponse = '{"records": [{"Id": "01p000000000001", "Name": "TestClass"}], "totalSize": 1}';
        Test.setMock(HttpCalloutMock.class, new MockToolingAPIResponse(200, mockResponse));
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryToolingAPI(query);
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Query should succeed');
        System.assertNotEquals(null, response.data, 'Response data should not be null');
        System.assertEquals(null, response.errorMessage, 'Error message should be null');
    }
    
    /**
     * @description Test Tooling API query with empty query
     */
    @isTest
    static void testQueryToolingAPI_EmptyQuery() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryToolingAPI('');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Query should fail');
        System.assertEquals('Query cannot be empty', response.errorMessage, 'Should have empty query error');
    }
    
    /**
     * @description Test Tooling API query with insufficient permissions
     */
    @isTest
    static void testQueryToolingAPI_InsufficientPermissions() {
        // Arrange
        String query = 'SELECT Id FROM ApexClass';
        Test.setMock(HttpCalloutMock.class, new MockToolingAPIResponse(403, '{"error": "Insufficient privileges"}'));
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryToolingAPI(query);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Query should fail');
        System.assert(response.errorMessage.contains('Insufficient permissions'), 'Should have permission error');
    }
    
    /**
     * @description Test Tooling API query with timeout
     */
    @isTest
    static void testQueryToolingAPI_Timeout() {
        // Arrange
        String query = 'SELECT Id FROM ApexClass';
        Test.setMock(HttpCalloutMock.class, new MockToolingAPIResponse(408, '{"error": "Request Timeout"}'));
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryToolingAPI(query);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Query should fail on timeout');
    }
    
    /**
     * @description Test retry logic on server errors
     */
    @isTest
    static void testQueryToolingAPI_RetryLogic() {
        // Arrange
        String query = 'SELECT Id FROM ApexClass';
        Test.setMock(HttpCalloutMock.class, new MockRetryResponse());
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryToolingAPI(query);
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Query should eventually succeed after retries');
    }
    
    /**
     * @description Test caching mechanism
     */
    @isTest
    static void testQueryToolingAPI_Caching() {
        // Arrange
        String query = 'SELECT Id FROM ApexClass';
        String mockResponse = '{"records": [{"Id": "01p000000000001"}]}';
        MockToolingAPIResponse mock = new MockToolingAPIResponse(200, mockResponse);
        Test.setMock(HttpCalloutMock.class, mock);
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response1 = MetadataRetriever.queryToolingAPI(query);
        MetadataRetriever.MetadataResponse response2 = MetadataRetriever.queryToolingAPI(query);
        Test.stopTest();
        
        // Assert
        System.assert(response1.success, 'First query should succeed');
        System.assert(response2.success, 'Second query should succeed from cache');
        // Mock should only be called once due to caching
        System.assertEquals(1, mock.callCount, 'API should only be called once');
    }
    
    /**
     * @description Test queryMetadataAPI with valid inputs
     */
    @isTest
    static void testQueryMetadataAPI_Success() {
        // Arrange
        String mockResponse = '{"records": [{"Id": "01p000000000001", "Name": "Account", "DeveloperName": "Account"}]}';
        Test.setMock(HttpCalloutMock.class, new MockToolingAPIResponse(200, mockResponse));
        
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryMetadataAPI('CustomObject', 'Account');
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Metadata query should succeed');
    }
    
    /**
     * @description Test queryMetadataAPI with empty parameters
     */
    @isTest
    static void testQueryMetadataAPI_EmptyParams() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response1 = MetadataRetriever.queryMetadataAPI('', 'Account');
        MetadataRetriever.MetadataResponse response2 = MetadataRetriever.queryMetadataAPI('CustomObject', '');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response1.success, 'Should fail with empty metadata type');
        System.assertEquals(false, response2.success, 'Should fail with empty full name');
    }
    
    /**
     * @description Test queryMetadataAPI with unsupported metadata type
     */
    @isTest
    static void testQueryMetadataAPI_UnsupportedType() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.queryMetadataAPI('UnsupportedType', 'TestName');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Should fail with unsupported type');
        System.assert(response.errorMessage.contains('Unsupported metadata type'), 'Should have unsupported type error');
    }
    
    /**
     * @description Test describeObject with standard object
     */
    @isTest
    static void testDescribeObject_StandardObject() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.describeObject('Account');
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Describe should succeed for Account');
        System.assertNotEquals(null, response.data, 'Response data should not be null');
        
        Map<String, Object> objectInfo = (Map<String, Object>) response.data;
        System.assertEquals('Account', objectInfo.get('name'), 'Object name should be Account');
        System.assertEquals(false, objectInfo.get('isCustom'), 'Account should not be custom');
    }
    
    /**
     * @description Test describeObject with invalid object
     */
    @isTest
    static void testDescribeObject_InvalidObject() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.describeObject('InvalidObject__c');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Describe should fail for invalid object');
        System.assert(response.errorMessage.contains('Object not found'), 'Should have object not found error');
    }
    
    /**
     * @description Test describeObject with empty object name
     */
    @isTest
    static void testDescribeObject_EmptyName() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.describeObject('');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Should fail with empty object name');
        System.assertEquals('Object name cannot be empty', response.errorMessage);
    }
    
    /**
     * @description Test describeObject caching
     */
    @isTest
    static void testDescribeObject_Caching() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response1 = MetadataRetriever.describeObject('Account');
        MetadataRetriever.MetadataResponse response2 = MetadataRetriever.describeObject('Account');
        Test.stopTest();
        
        // Assert
        System.assert(response1.success, 'First describe should succeed');
        System.assert(response2.success, 'Second describe should succeed from cache');
        // Both should return the same cached data
        System.assertEquals(response1.data, response2.data, 'Cached data should be identical');
    }
    
    /**
     * @description Test getFieldMetadata with standard field
     */
    @isTest
    static void testGetFieldMetadata_StandardField() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.getFieldMetadata('Account', 'Name');
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Field metadata should succeed');
        System.assertNotEquals(null, response.data, 'Response data should not be null');
        
        Map<String, Object> fieldInfo = (Map<String, Object>) response.data;
        System.assertEquals('Name', fieldInfo.get('name'), 'Field name should be Name');
        System.assertEquals(false, fieldInfo.get('isCustom'), 'Name field should not be custom');
    }
    
    /**
     * @description Test getFieldMetadata with lookup field
     */
    @isTest
    static void testGetFieldMetadata_LookupField() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.getFieldMetadata('Contact', 'AccountId');
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Field metadata should succeed');
        Map<String, Object> fieldInfo = (Map<String, Object>) response.data;
        System.assertEquals('REFERENCE', fieldInfo.get('type'), 'AccountId should be a reference field');
        
        List<String> referenceTo = (List<String>) fieldInfo.get('referenceTo');
        System.assert(referenceTo.contains('Account'), 'Should reference Account object');
    }
    
    /**
     * @description Test getFieldMetadata with invalid field
     */
    @isTest
    static void testGetFieldMetadata_InvalidField() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.getFieldMetadata('Account', 'InvalidField__c');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Should fail for invalid field');
        System.assert(response.errorMessage.contains('Field not found'), 'Should have field not found error');
    }
    
    /**
     * @description Test getFieldMetadata with invalid object
     */
    @isTest
    static void testGetFieldMetadata_InvalidObject() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.getFieldMetadata('InvalidObject__c', 'Name');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response.success, 'Should fail for invalid object');
        System.assert(response.errorMessage.contains('Object not found'), 'Should have object not found error');
    }
    
    /**
     * @description Test getFieldMetadata with empty parameters
     */
    @isTest
    static void testGetFieldMetadata_EmptyParams() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response1 = MetadataRetriever.getFieldMetadata('', 'Name');
        MetadataRetriever.MetadataResponse response2 = MetadataRetriever.getFieldMetadata('Account', '');
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, response1.success, 'Should fail with empty object name');
        System.assertEquals(false, response2.success, 'Should fail with empty field name');
    }
    
    /**
     * @description Test getFieldMetadata caching
     */
    @isTest
    static void testGetFieldMetadata_Caching() {
        // Act
        Test.startTest();
        MetadataRetriever.MetadataResponse response1 = MetadataRetriever.getFieldMetadata('Account', 'Name');
        MetadataRetriever.MetadataResponse response2 = MetadataRetriever.getFieldMetadata('Account', 'Name');
        Test.stopTest();
        
        // Assert
        System.assert(response1.success, 'First call should succeed');
        System.assert(response2.success, 'Second call should succeed from cache');
    }
    
    /**
     * @description Test cache clearing functionality
     */
    @isTest
    static void testClearCache() {
        // Arrange
        MetadataRetriever.describeObject('Account');
        
        // Act
        Test.startTest();
        MetadataRetriever.clearCache();
        MetadataRetriever.MetadataResponse response = MetadataRetriever.describeObject('Account');
        Test.stopTest();
        
        // Assert
        System.assert(response.success, 'Should succeed after cache clear');
    }
    
    /**
     * @description Test async Tooling API query (future method)
     */
    @isTest
    static void testQueryToolingAPIAsync() {
        // Arrange
        String query = 'SELECT Id FROM ApexClass LIMIT 1';
        String mockResponse = '{"records": [{"Id": "01p000000000001"}]}';
        Test.setMock(HttpCalloutMock.class, new MockToolingAPIResponse(200, mockResponse));
        
        // Act
        Test.startTest();
        MetadataRetriever.queryToolingAPIAsync(query);
        Test.stopTest();
        
        // Assert - future method executes successfully (no exception thrown)
        // Cannot directly assert on future method results, but we verify it doesn't throw
    }
    
    /**
     * @description Test async query with empty string
     */
    @isTest
    static void testQueryToolingAPIAsync_EmptyQuery() {
        // Act
        Test.startTest();
        MetadataRetriever.queryToolingAPIAsync('');
        Test.stopTest();
        
        // Assert - should handle gracefully without throwing exception
    }
}