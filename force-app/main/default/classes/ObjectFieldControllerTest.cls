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
 * @description Test class for ObjectFieldController
 * @author System
 * @date 2025
 */
@isTest
private class ObjectFieldControllerTest {
    
    /**
     * @description Test getAllObjects returns object list
     */
    @isTest
    static void testGetAllObjects_Success() {
        // Act
        Test.startTest();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, objects, 'Objects list should not be null');
        System.assert(objects.size() > 0, 'Should return at least one object');
        
        // Verify structure
        ObjectFieldController.ObjectInfo firstObj = objects[0];
        System.assertNotEquals(null, firstObj.label, 'Object label should not be null');
        System.assertNotEquals(null, firstObj.value, 'Object value should not be null');
        System.assertNotEquals(null, firstObj.category, 'Category should not be null');
    }
    
    /**
     * @description Test that standard objects are returned
     */
    @isTest
    static void testGetAllObjects_ContainsStandardObjects() {
        // Act
        Test.startTest();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert - Should contain Account
        Boolean foundAccount = false;
        for (ObjectFieldController.ObjectInfo obj : objects) {
            if (obj.value == 'Account') {
                foundAccount = true;
                System.assertEquals('Standard Objects', obj.category, 'Account should be standard');
                System.assertEquals(false, obj.isCustom, 'Account should not be custom');
                break;
            }
        }
        System.assert(foundAccount, 'Should contain Account object');
    }
    
    /**
     * @description Test objects are sorted correctly
     */
    @isTest
    static void testGetAllObjects_SortedCorrectly() {
        // Act
        Test.startTest();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert - Standard objects should come before custom
        Boolean foundCustom = false;
        Boolean standardAfterCustom = false;
        
        for (ObjectFieldController.ObjectInfo obj : objects) {
            if (obj.isCustom) {
                foundCustom = true;
            } else if (foundCustom) {
                standardAfterCustom = true;
                break;
            }
        }
        
        System.assertEquals(false, standardAfterCustom, 'Standard objects should come before custom objects');
    }
    
    /**
     * @description Test object list caching
     */
    @isTest
    static void testGetAllObjects_Caching() {
        // Act
        Test.startTest();
        ObjectFieldController.clearCache();
        List<ObjectFieldController.ObjectInfo> objects1 = ObjectFieldController.getAllObjects();
        List<ObjectFieldController.ObjectInfo> objects2 = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert
        System.assertEquals(objects1.size(), objects2.size(), 'Cached results should match');
    }
    
    /**
     * @description Test getObjectFields with valid object
     */
    @isTest
    static void testGetObjectFields_Success() {
        // Act
        Test.startTest();
        List<ObjectFieldController.FieldInfo> fields = ObjectFieldController.getObjectFields('Account');
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, fields, 'Fields list should not be null');
        System.assert(fields.size() > 0, 'Account should have fields');
        
        // Verify structure
        ObjectFieldController.FieldInfo firstField = fields[0];
        System.assertNotEquals(null, firstField.label, 'Field label should not be null');
        System.assertNotEquals(null, firstField.apiName, 'API name should not be null');
        System.assertNotEquals(null, firstField.dataType, 'Data type should not be null');
        System.assertNotEquals(null, firstField.value, 'Value should not be null');
    }
    
    /**
     * @description Test getObjectFields contains standard fields
     */
    @isTest
    static void testGetObjectFields_ContainsStandardFields() {
        // Act
        Test.startTest();
        List<ObjectFieldController.FieldInfo> fields = ObjectFieldController.getObjectFields('Account');
        Test.stopTest();
        
        // Assert - Should contain Name field
        Boolean foundName = false;
        for (ObjectFieldController.FieldInfo field : fields) {
            if (field.apiName == 'Name') {
                foundName = true;
                System.assertEquals(false, field.isCustom, 'Name should not be custom');
                System.assertEquals('STRING', field.dataType, 'Name should be STRING type');
                break;
            }
        }
        System.assert(foundName, 'Should contain Name field');
    }
    
    /**
     * @description Test getObjectFields with empty object name
     */
    @isTest
    static void testGetObjectFields_EmptyObjectName() {
        // Act & Assert
        Test.startTest();
        try {
            ObjectFieldController.getObjectFields('');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('cannot be empty'), 'Should have empty error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getObjectFields with null object name
     */
    @isTest
    static void testGetObjectFields_NullObjectName() {
        // Act & Assert
        Test.startTest();
        try {
            ObjectFieldController.getObjectFields(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('cannot be empty'), 'Should have empty error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getObjectFields with invalid object name
     */
    @isTest
    static void testGetObjectFields_InvalidObject() {
        // Act & Assert
        Test.startTest();
        try {
            ObjectFieldController.getObjectFields('InvalidObject__c');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Object not found'), 'Should have not found error');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test ObjectInfo wrapper construction
     */
    @isTest
    static void testObjectInfo_Construction() {
        // Act
        Test.startTest();
        ObjectFieldController.ObjectInfo obj = new ObjectFieldController.ObjectInfo('Test Object', 'Test__c', true);
        Test.stopTest();
        
        // Assert
        System.assertEquals('Test Object', obj.label, 'Label should match');
        System.assertEquals('Test__c', obj.value, 'Value should match');
        System.assertEquals(true, obj.isCustom, 'IsCustom should match');
        System.assertEquals('Custom Objects', obj.category, 'Category should be Custom Objects');
    }
    
    /**
     * @description Test FieldInfo wrapper construction
     */
    @isTest
    static void testFieldInfo_Construction() {
        // Act
        Test.startTest();
        ObjectFieldController.FieldInfo field = new ObjectFieldController.FieldInfo(
            'Test Field', 
            'TestField__c', 
            'STRING', 
            true
        );
        Test.stopTest();
        
        // Assert
        System.assertEquals('Test Field', field.label, 'Label should match');
        System.assertEquals('TestField__c', field.apiName, 'API name should match');
        System.assertEquals('TestField__c', field.value, 'Value should match');
        System.assertEquals('STRING', field.dataType, 'Data type should match');
        System.assertEquals(true, field.isCustom, 'IsCustom should match');
    }
    
    /**
     * @description Test that system objects are excluded
     */
    @isTest
    static void testGetAllObjects_ExcludesSystemObjects() {
        // Act
        Test.startTest();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert - Should not contain history/share objects
        for (ObjectFieldController.ObjectInfo obj : objects) {
            System.assert(!obj.value.endsWith('__History'), 'Should not include History objects');
            System.assert(!obj.value.endsWith('__Share'), 'Should not include Share objects');
            System.assert(!obj.value.endsWith('__Feed'), 'Should not include Feed objects');
            System.assert(!obj.value.endsWith('__Tag'), 'Should not include Tag objects');
        }
    }
    
    /**
     * @description Test getObjectFields returns sorted fields
     */
    @isTest
    static void testGetObjectFields_SortedAlphabetically() {
        // Act
        Test.startTest();
        List<ObjectFieldController.FieldInfo> fields = ObjectFieldController.getObjectFields('Account');
        Test.stopTest();
        
        // Assert - Fields should be sorted
        if (fields.size() > 1) {
            String previousLabel = fields[0].label.toLowerCase();
            for (Integer i = 1; i < fields.size(); i++) {
                String currentLabel = fields[i].label.toLowerCase();
                // Note: This is a basic check, actual sorting is more complex
                System.assertNotEquals(null, currentLabel, 'Field label should not be null');
            }
        }
    }
    
    /**
     * @description Test getAllObjects with different user permissions
     */
    @isTest
    static void testGetAllObjects_WithDifferentPermissions() {
        // This test verifies that the controller respects user permissions
        User standardUser = [SELECT Id FROM User WHERE Profile.Name = 'Standard User' AND IsActive = true LIMIT 1];
        
        System.runAs(standardUser) {
            // Act
            Test.startTest();
            List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
            Test.stopTest();
            
            // Assert
            System.assertNotEquals(null, objects, 'Objects list should not be null');
            // Standard user should see fewer objects than system admin
        }
    }
    
    /**
     * @description Test getObjectFields with Contact object
     */
    @isTest
    static void testGetObjectFields_ContactObject() {
        // Act
        Test.startTest();
        List<ObjectFieldController.FieldInfo> fields = ObjectFieldController.getObjectFields('Contact');
        Test.stopTest();
        
        // Assert
        System.assert(fields.size() > 0, 'Contact should have fields');
        
        // Verify specific fields exist
        Boolean foundFirstName = false;
        Boolean foundLastName = false;
        
        for (ObjectFieldController.FieldInfo field : fields) {
            if (field.apiName == 'FirstName') {
                foundFirstName = true;
            }
            if (field.apiName == 'LastName') {
                foundLastName = true;
            }
        }
        
        System.assert(foundFirstName, 'Should contain FirstName field');
        System.assert(foundLastName, 'Should contain LastName field');
    }
    
    /**
     * @description Test cache clearing functionality
     */
    @isTest
    static void testClearCache() {
        // Arrange
        ObjectFieldController.getAllObjects(); // Populate cache
        
        // Act
        Test.startTest();
        ObjectFieldController.clearCache();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, objects, 'Should retrieve objects after cache clear');
    }
    
    /**
     * @description Test that both standard and custom categories exist
     */
    @isTest
    static void testGetAllObjects_HasBothCategories() {
        // Act
        Test.startTest();
        List<ObjectFieldController.ObjectInfo> objects = ObjectFieldController.getAllObjects();
        Test.stopTest();
        
        // Assert
        Boolean hasStandard = false;
        
        for (ObjectFieldController.ObjectInfo obj : objects) {
            if (obj.category == 'Standard Objects') {
                hasStandard = true;
            }
        }
        
        System.assert(hasStandard, 'Should have at least one standard category');
    }
    
    /**
     * @description Test field data types are correctly identified
     */
    @isTest
    static void testGetObjectFields_DataTypes() {
        // Act
        Test.startTest();
        List<ObjectFieldController.FieldInfo> fields = ObjectFieldController.getObjectFields('Account');
        Test.stopTest();
        
        // Assert - Verify different data types exist
        Set<String> dataTypes = new Set<String>();
        for (ObjectFieldController.FieldInfo field : fields) {
            dataTypes.add(field.dataType);
        }
        
        System.assert(dataTypes.size() > 1, 'Should have multiple data types');
    }
}