/**
 * @description Test class for DiagnosticReportBuilder
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
@isTest
private class DiagnosticReportBuilderTest {
    
    @testSetup
    static void setup() {
        // Create test user
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser',
            Email = 'testuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'testuser' + DateTime.now().getTime() + '@example.com'
        );
        insert testUser;
    }
    
    @isTest
    static void testCreateReport() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        
        Test.startTest();
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        Test.stopTest();
        
        // Verify report created
        System.assertNotEquals(null, report, 'Report should be created');
        System.assertNotEquals(null, report.reportId, 'Report ID should be generated');
        System.assertNotEquals(null, report.timestamp, 'Timestamp should be set');
        System.assertNotEquals(null, report.userContext, 'User context should be initialized');
        System.assertNotEquals(null, report.findings, 'Findings list should be initialized');
        System.assertNotEquals(null, report.summary, 'Summary should be initialized');
        
        // Verify user context populated
        System.assertEquals('TestUser', report.userContext.userName, 'User name should match');
        System.assertNotEquals(null, report.userContext.profileName, 'Profile name should be populated');
    }
    
    @isTest
    static void testAddObjectPermissionFinding_Pass() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock permission result - all permissions granted
        SalesforceDiagnosticService.ObjectPermissionResult permResult = 
            new SalesforceDiagnosticService.ObjectPermissionResult();
        permResult.objectName = 'Account';
        permResult.isAccessible = true;
        permResult.isCreateable = true;
        permResult.isUpdateable = true;
        permResult.isDeletable = true;
        permResult.permissionDetails.add('Read granted by: Standard User Profile');
        
        Test.startTest();
        DiagnosticReportBuilder.addObjectPermissionFinding(report, 'Account', permResult);
        Test.stopTest();
        
        // Verify finding added
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('Object Access', finding.category, 'Category should be Object Access');
        System.assertEquals('PASS', finding.status, 'Status should be PASS');
        System.assertEquals('✓', finding.statusIcon, 'Status icon should be checkmark');
        System.assertEquals(1, report.summary.passedChecks, 'Passed check counter should increment');
    }
    
    @isTest
    static void testAddObjectPermissionFinding_Fail() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock permission result - no access
        SalesforceDiagnosticService.ObjectPermissionResult permResult = 
            new SalesforceDiagnosticService.ObjectPermissionResult();
        permResult.objectName = 'Account';
        permResult.isAccessible = false;
        permResult.isCreateable = false;
        permResult.isUpdateable = false;
        permResult.isDeletable = false;
        
        Test.startTest();
        DiagnosticReportBuilder.addObjectPermissionFinding(report, 'Account', permResult);
        Test.stopTest();
        
        // Verify finding added with failure status
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('FAIL', finding.status, 'Status should be FAIL');
        System.assertEquals('✗', finding.statusIcon, 'Status icon should be X');
        System.assertEquals(DiagnosticReportBuilder.Severity.HIGH, finding.severity, 'Severity should be HIGH');
        System.assertEquals(1, report.summary.failedChecks, 'Failed check counter should increment');
    }
    
    @isTest
    static void testAddObjectPermissionFinding_Warning() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock permission result - partial access
        SalesforceDiagnosticService.ObjectPermissionResult permResult = 
            new SalesforceDiagnosticService.ObjectPermissionResult();
        permResult.objectName = 'Account';
        permResult.isAccessible = true;
        permResult.isCreateable = false;
        permResult.isUpdateable = false;
        permResult.isDeletable = false;
        
        Test.startTest();
        DiagnosticReportBuilder.addObjectPermissionFinding(report, 'Account', permResult);
        Test.stopTest();
        
        // Verify finding added with warning status
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('WARNING', finding.status, 'Status should be WARNING');
        System.assertEquals('⚠', finding.statusIcon, 'Status icon should be warning');
        System.assertEquals(1, report.summary.warningChecks, 'Warning check counter should increment');
    }
    
    @isTest
    static void testAddFieldSecurityFinding_Pass() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock field permission result - full access
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'Phone';
        fieldResult.isAccessible = true;
        fieldResult.isUpdateable = true;
        
        Test.startTest();
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'Phone', fieldResult);
        Test.stopTest();
        
        // Verify finding added
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('Field-Level Security', finding.category, 'Category should be FLS');
        System.assertEquals('PASS', finding.status, 'Status should be PASS');
        System.assertEquals(1, report.summary.passedChecks, 'Passed check counter should increment');
    }
    
    @isTest
    static void testAddFieldSecurityFinding_Fail() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock field permission result - no access
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'Phone';
        fieldResult.isAccessible = false;
        fieldResult.isUpdateable = false;
        
        Test.startTest();
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'Phone', fieldResult);
        Test.stopTest();
        
        // Verify finding added with failure
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('FAIL', finding.status, 'Status should be FAIL');
        System.assertEquals(DiagnosticReportBuilder.Severity.HIGH, finding.severity, 'Severity should be HIGH');
        System.assertNotEquals(null, finding.impact, 'Impact should be described');
        System.assertEquals(1, report.summary.failedChecks, 'Failed check counter should increment');
    }
    
    @isTest
    static void testAddFieldSecurityFinding_FieldNotExists() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock field permission result - field doesn't exist
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'NonExistentField';
        fieldResult.errorMessage = 'Field "NonExistentField" does not exist on object "Account"';
        
        Test.startTest();
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'NonExistentField', fieldResult);
        Test.stopTest();
        
        // Verify error handled
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('FAIL', finding.status, 'Status should be FAIL');
        System.assert(finding.impact.contains('does not exist'), 'Impact should mention field does not exist');
    }
    
    @isTest
    static void testAddRecordAccessFinding_Pass() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock record access result - full access
        SalesforceDiagnosticService.RecordAccess recordAccess = 
            new SalesforceDiagnosticService.RecordAccess();
        recordAccess.recordId = testAccount.Id;
        recordAccess.hasReadAccess = true;
        recordAccess.hasEditAccess = true;
        recordAccess.hasDeleteAccess = true;
        recordAccess.hasTransferAccess = true;
        recordAccess.maxAccessLevel = 'Edit';
        
        Test.startTest();
        DiagnosticReportBuilder.addRecordAccessFinding(report, testAccount.Id, recordAccess);
        Test.stopTest();
        
        // Verify finding added
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('Record Access', finding.category, 'Category should be Record Access');
        System.assertEquals('PASS', finding.status, 'Status should be PASS');
    }
    
    @isTest
    static void testAddRecordAccessFinding_NoAccess() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Create mock record access result - no access
        SalesforceDiagnosticService.RecordAccess recordAccess = 
            new SalesforceDiagnosticService.RecordAccess();
        recordAccess.recordId = testAccount.Id;
        recordAccess.hasReadAccess = false;
        recordAccess.hasEditAccess = false;
        recordAccess.hasDeleteAccess = false;
        recordAccess.hasTransferAccess = false;
        
        Test.startTest();
        DiagnosticReportBuilder.addRecordAccessFinding(report, testAccount.Id, recordAccess);
        Test.stopTest();
        
        // Verify finding shows failure
        System.assertEquals(1, report.findings.size(), 'One finding should be added');
        DiagnosticReportBuilder.DiagnosticFinding finding = report.findings[0];
        System.assertEquals('FAIL', finding.status, 'Status should be FAIL');
        System.assertNotEquals(null, finding.impact, 'Impact should be described');
    }
    
    @isTest
    static void testAddFieldExistenceFinding() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        Test.startTest();
        // Test field exists
        DiagnosticReportBuilder.addFieldExistenceFinding(report, 'Account', 'Phone', true);
        // Test field doesn't exist
        DiagnosticReportBuilder.addFieldExistenceFinding(report, 'Account', 'FakeField', false);
        Test.stopTest();
        
        // Verify both findings added
        System.assertEquals(2, report.findings.size(), 'Two findings should be added');
        System.assertEquals('PASS', report.findings[0].status, 'First should pass');
        System.assertEquals('FAIL', report.findings[1].status, 'Second should fail');
        System.assertEquals(1, report.summary.passedChecks, 'One passed check');
        System.assertEquals(1, report.summary.failedChecks, 'One failed check');
    }
    
    @isTest
    static void testAddObjectExistenceFinding() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        Test.startTest();
        // Test object exists
        DiagnosticReportBuilder.addObjectExistenceFinding(report, 'Account', true);
        // Test object doesn't exist
        DiagnosticReportBuilder.addObjectExistenceFinding(report, 'FakeObject', false);
        Test.stopTest();
        
        // Verify both findings added
        System.assertEquals(2, report.findings.size(), 'Two findings should be added');
        System.assertEquals('PASS', report.findings[0].status, 'First should pass');
        System.assertEquals('FAIL', report.findings[1].status, 'Second should fail');
    }
    
    @isTest
    static void testFinalizeReport_WithFailures() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Add some findings with failures
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'Phone';
        fieldResult.isAccessible = false;
        
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'Phone', fieldResult);
        
        Test.startTest();
        DiagnosticReportBuilder.finalizeReport(report);
        Test.stopTest();
        
        // Verify summary generated
        System.assertNotEquals(null, report.summary.rootCause, 'Root cause should be set');
        System.assertEquals(DiagnosticReportBuilder.Severity.HIGH, report.summary.overallSeverity, 
                          'Severity should be HIGH');
        System.assert(!report.summary.suggestedActions.isEmpty(), 'Should have suggested actions');
        System.assert(!report.summary.whoCanHelp.isEmpty(), 'Should list who can help');
        
        // Verify plain text report generated
        System.assertNotEquals(null, report.plainTextReport, 'Plain text report should be generated');
        System.assert(report.plainTextReport.contains('DIAGNOSTIC REPORT'), 
                     'Should contain report header');
        System.assert(report.plainTextReport.contains('FAIL'), 'Should show failure');
        
        // Verify JSON report generated
        System.assertNotEquals(null, report.jsonReport, 'JSON report should be generated');
    }
    
    @isTest
    static void testFinalizeReport_AllPass() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Add passing findings
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'Phone';
        fieldResult.isAccessible = true;
        fieldResult.isUpdateable = true;
        
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'Phone', fieldResult);
        
        Test.startTest();
        DiagnosticReportBuilder.finalizeReport(report);
        Test.stopTest();
        
        // Verify summary for all pass
        System.assert(report.summary.rootCause.contains('passed'), 'Root cause should mention passed');
        System.assertEquals(DiagnosticReportBuilder.Severity.INFO, report.summary.overallSeverity, 
                          'Severity should be INFO');
    }
    
    @isTest
    static void testGeneratePlainTextReport() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Add a finding
        DiagnosticReportBuilder.addFieldExistenceFinding(report, 'Account', 'Phone', true);
        DiagnosticReportBuilder.finalizeReport(report);
        
        Test.startTest();
        String plainText = DiagnosticReportBuilder.generatePlainTextReport(report);
        Test.stopTest();
        
        // Verify format
        System.assertNotEquals(null, plainText, 'Plain text should be generated');
        System.assert(plainText.contains('DIAGNOSTIC REPORT'), 'Should have header');
        System.assert(plainText.contains('USER CONTEXT'), 'Should have user context');
        System.assert(plainText.contains('FINDINGS'), 'Should have findings section');
        System.assert(plainText.contains('SUMMARY'), 'Should have summary');
        System.assert(plainText.contains('TestUser'), 'Should include user name');
    }
    
    @isTest
    static void testMultipleFindings() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        // Add multiple findings
        DiagnosticReportBuilder.addObjectExistenceFinding(report, 'Account', true);
        DiagnosticReportBuilder.addFieldExistenceFinding(report, 'Account', 'Phone', true);
        
        SalesforceDiagnosticService.FieldPermissionResult fieldResult = 
            new SalesforceDiagnosticService.FieldPermissionResult();
        fieldResult.objectName = 'Account';
        fieldResult.fieldName = 'Phone';
        fieldResult.isAccessible = false;
        DiagnosticReportBuilder.addFieldSecurityFinding(report, 'Account', 'Phone', fieldResult);
        
        Test.startTest();
        DiagnosticReportBuilder.finalizeReport(report);
        Test.stopTest();
        
        // Verify all findings tracked
        System.assertEquals(3, report.findings.size(), 'Should have 3 findings');
        System.assertEquals(3, report.summary.totalChecks, 'Should count 3 total checks');
        System.assertEquals(2, report.summary.passedChecks, 'Should have 2 passed');
        System.assertEquals(1, report.summary.failedChecks, 'Should have 1 failed');
        
        // Verify sequence numbers
        System.assertEquals(1, report.findings[0].sequenceNumber, 'First should be 1');
        System.assertEquals(2, report.findings[1].sequenceNumber, 'Second should be 2');
        System.assertEquals(3, report.findings[2].sequenceNumber, 'Third should be 3');
    }
    
    @isTest
    static void testNullHandling() {
        Test.startTest();
        // Test null report
        DiagnosticReportBuilder.addObjectPermissionFinding(null, 'Account', null);
        DiagnosticReportBuilder.addFieldSecurityFinding(null, 'Account', 'Phone', null);
        DiagnosticReportBuilder.finalizeReport(null);
        String plainText = DiagnosticReportBuilder.generatePlainTextReport(null);
        Test.stopTest();
        
        // Should not throw exceptions
        System.assertEquals('No report data available', plainText, 'Should return message for null report');
    }
    
    @isTest
    static void testEmptyReport() {
        User testUser = [SELECT Id FROM User WHERE LastName = 'TestUser' LIMIT 1];
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(testUser.Id);
        
        Test.startTest();
        DiagnosticReportBuilder.finalizeReport(report);
        Test.stopTest();
        
        // Verify empty report handling
        System.assertEquals(0, report.findings.size(), 'Should have no findings');
        System.assertNotEquals(null, report.summary.rootCause, 'Should have root cause even when empty');
        System.assertNotEquals(null, report.plainTextReport, 'Should generate plain text for empty report');
    }
}