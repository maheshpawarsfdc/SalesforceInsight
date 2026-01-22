/**
 * @description Analyzes diagnostic findings to identify THE root cause
 * Uses decision tree logic to correlate findings and provide definitive diagnosis
 * @author Salesforce AI Diagnostic Assistant  
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class RootCauseAnalyzer {
    
    /**
     * @description Root cause result
     */
    public class RootCause {
        @AuraEnabled public String primaryCause;
        @AuraEnabled public String category;
        @AuraEnabled public Integer confidence; // 0-100
        @AuraEnabled public List<String> contributingFactors;
        @AuraEnabled public List<String> solutionSteps;
        @AuraEnabled public String whoCanFix;
        @AuraEnabled public String explanation;
        
        public RootCause() {
            this.contributingFactors = new List<String>();
            this.solutionSteps = new List<String>();
            this.confidence = 0;
        }
    }
    
    /**
     * @description Analyze field visibility issue
     * Uses decision tree to identify THE root cause
     */
    public static RootCause analyzeFieldVisibility(
        String objectName,
        String fieldName,
        Id userId,
        List<DiagnosticReportBuilder.DiagnosticFinding> findings
    ) {
        RootCause cause = new RootCause();
        
        // Extract key findings
        Boolean fieldExists = false;
        Boolean hasFLS = false;
        Boolean hasObjectRead = false;
        Boolean isOnLayout = false;
        
        for (DiagnosticReportBuilder.DiagnosticFinding finding : findings) {
            if (finding.category == 'Field Existence') {
                fieldExists = (finding.status == 'PASS');
            } else if (finding.category == 'Field-Level Security') {
                hasFLS = (finding.status == 'PASS');
            } else if (finding.category == 'Object Access') {
                hasObjectRead = finding.details.contains('Can Read: YES') || 
                               finding.details.contains('✓ Can Read: YES');
            } else if (finding.category == 'Page Layout') {
                isOnLayout = (finding.status == 'PASS');
            }
        }
        
        System.debug('=== ROOT CAUSE ANALYSIS ===');
        System.debug('Field Exists: ' + fieldExists);
        System.debug('Has FLS: ' + hasFLS);
        System.debug('Has Object Read: ' + hasObjectRead);
        System.debug('Is On Layout: ' + isOnLayout);
        
        // DECISION TREE
        if (!fieldExists) {
            // ===== CASE 1: Field doesn't exist =====
            cause.primaryCause = 'Field does not exist';
            cause.category = 'Field Existence';
            cause.confidence = 100;
            cause.explanation = 'The field "' + fieldName + '" does not exist on the ' + 
                               objectName + ' object.';
            cause.solutionSteps.add('Verify the field name spelling (it is case-sensitive for API names)');
            cause.solutionSteps.add('Check if the field was recently deleted');
            cause.solutionSteps.add('Confirm you are looking at the correct object');
            cause.whoCanFix = 'System Administrator (can create field if needed)';
            
        } else if (!hasObjectRead) {
            // ===== CASE 2: No object-level read permission =====
            cause.primaryCause = 'No object-level read permission';
            cause.category = 'Object Permissions';
            cause.confidence = 100;
            cause.explanation = 'You do not have Read permission on the ' + objectName + 
                               ' object. Without object-level read access, you cannot view any fields on this object.';
            cause.solutionSteps.add('Go to Setup → Profiles → [Your Profile]');
            cause.solutionSteps.add('Find Object Settings → ' + objectName);
            cause.solutionSteps.add('Enable "Read" permission');
            cause.solutionSteps.add('Alternative: Create a Permission Set with Read access and assign to user');
            cause.whoCanFix = 'System Administrator or Profile Manager';
            
        } else if (!hasFLS) {
            // ===== CASE 3: Field exists, has object read, but no FLS =====
            cause.primaryCause = 'Field-Level Security not granted';
            cause.category = 'Field-Level Security';
            cause.confidence = 100;
            cause.explanation = 'The field exists and you can view ' + objectName + 
                               ' records, but Field-Level Security (FLS) blocks access to the "' + 
                               fieldName + '" field specifically.';
            cause.solutionSteps.add('Go to Setup → Profiles → [Your Profile]');
            cause.solutionSteps.add('Find Object Settings → ' + objectName + ' → ' + fieldName);
            cause.solutionSteps.add('Enable "Visible" checkbox');
            cause.solutionSteps.add('Save the profile');
            cause.solutionSteps.add('Alternative: Create Permission Set with FLS access');
            cause.whoCanFix = 'System Administrator';
            
        } else if (!isOnLayout) {
            // ===== CASE 4: Field exists, has FLS, has object read, but NOT on layout =====
            cause.primaryCause = 'Field not on page layout';
            cause.category = 'Page Layout';
            cause.confidence = 95;
            cause.explanation = 'The field "' + fieldName + '" exists and you have all necessary permissions. ' +
                               'However, it is not on the page layout, so it doesn\'t display on the record page.';
            cause.solutionSteps.add('Go to Setup → Object Manager → ' + objectName);
            cause.solutionSteps.add('Click "Page Layouts"');
            cause.solutionSteps.add('Edit the layout you use (check your record type if applicable)');
            cause.solutionSteps.add('Drag "' + fieldName + '" from the field palette onto the layout');
            cause.solutionSteps.add('Save the layout');
            cause.whoCanFix = 'System Administrator or page layout manager';
            cause.contributingFactors.add('Field may be on a different page layout for another record type');
            cause.contributingFactors.add('Lightning Dynamic Forms might be hiding the field');
            
        } else {
            // ===== CASE 5: Everything looks good - check edge cases =====
            cause.primaryCause = 'Advanced visibility restriction';
            cause.category = 'Advanced';
            cause.confidence = 60;
            cause.explanation = 'All basic permissions are correct. The field should be visible. ' +
                               'This suggests an advanced configuration issue.';
            cause.solutionSteps.add('Check if Lightning Dynamic Forms are hiding the field');
            cause.solutionSteps.add('Check if a different record type uses a different layout');
            cause.solutionSteps.add('Try hard-refreshing the page (Ctrl+Shift+R)');
            cause.solutionSteps.add('Clear browser cache');
            cause.solutionSteps.add('Check if field is conditionally hidden by Lightning Component');
            cause.whoCanFix = 'System Administrator';
            cause.contributingFactors.add('May be Lightning-specific issue (try Classic to test)');
            cause.contributingFactors.add('May be record type specific');
        }
        
        System.debug('Root Cause: ' + cause.primaryCause + ' (Confidence: ' + cause.confidence + '%)');
        
        return cause;
    }
    
    /**
     * @description Analyze edit permission issue
     */
    public static RootCause analyzeEditPermission(
        String objectName,
        String fieldName,
        Id userId,
        List<DiagnosticReportBuilder.DiagnosticFinding> findings
    ) {
        RootCause cause = new RootCause();
        
        Boolean hasObjectEdit = false;
        Boolean hasFLSEdit = false;
        Boolean fieldReadOnly = false;
        
        for (DiagnosticReportBuilder.DiagnosticFinding finding : findings) {
            if (finding.category == 'Object Access') {
                hasObjectEdit = finding.details.contains('Can Edit: YES') || 
                               finding.details.contains('✓ Can Edit: YES');
            } else if (finding.category == 'Field-Level Security') {
                hasFLSEdit = finding.details.contains('Can Edit: YES') || 
                            finding.details.contains('✓ Can Edit: YES');
                fieldReadOnly = finding.details.contains('Read-only');
            }
        }
        
        // Decision tree for edit issues
        if (!hasObjectEdit) {
            cause.primaryCause = 'No object-level edit permission';
            cause.category = 'Object Permissions';
            cause.confidence = 100;
            cause.explanation = 'You do not have Edit permission on the ' + objectName + ' object.';
            cause.solutionSteps.add('Contact your Salesforce administrator');
            cause.solutionSteps.add('Request Edit permission on ' + objectName);
            cause.whoCanFix = 'System Administrator';
            
        } else if (fieldReadOnly) {
            cause.primaryCause = 'Field is read-only (formula or system field)';
            cause.category = 'Field Type';
            cause.confidence = 100;
            cause.explanation = 'The field "' + fieldName + '" is read-only by design (formula field or system field).';
            cause.solutionSteps.add('Formula fields cannot be edited directly');
            cause.solutionSteps.add('To change the value, modify the fields used in the formula');
            cause.whoCanFix = 'Cannot be changed (field design limitation)';
            
        } else if (!hasFLSEdit) {
            cause.primaryCause = 'Field-Level Security blocks editing';
            cause.category = 'Field-Level Security';
            cause.confidence = 100;
            cause.explanation = 'You can view the field but Field-Level Security prevents editing.';
            cause.solutionSteps.add('Go to Setup → Profiles → [Your Profile]');
            cause.solutionSteps.add('Find Object Settings → ' + objectName + ' → ' + fieldName);
            cause.solutionSteps.add('Enable "Read/Write" access');
            cause.whoCanFix = 'System Administrator';
        }
        
        return cause;
    }
    
    /**
     * @description Analyze record access issue
     */
    public static RootCause analyzeRecordAccess(
        Id recordId,
        Id userId,
        List<DiagnosticReportBuilder.DiagnosticFinding> findings
    ) {
        RootCause cause = new RootCause();
        
        Boolean hasRecordRead = false;
        
        for (DiagnosticReportBuilder.DiagnosticFinding finding : findings) {
            if (finding.category == 'Record Access') {
                hasRecordRead = finding.details.contains('Can View: YES') || 
                               finding.details.contains('✓ Can View: YES');
            }
        }
        
        if (!hasRecordRead) {
            cause.primaryCause = 'No record-level access (sharing restriction)';
            cause.category = 'Sharing';
            cause.confidence = 90;
            cause.explanation = 'Org-Wide Defaults or sharing rules prevent you from accessing this specific record.';
            cause.solutionSteps.add('Check if Org-Wide Default is set to Private');
            cause.solutionSteps.add('Verify you are not the record owner');
            cause.solutionSteps.add('Check role hierarchy (owner may be in lower role)');
            cause.solutionSteps.add('Request manual sharing or sharing rule from admin');
            cause.whoCanFix = 'System Administrator or record owner';
            cause.contributingFactors.add('May need to be added to sharing rule');
            cause.contributingFactors.add('May need manual share from record owner');
        }
        
        return cause;
    }
    
    /**
     * @description Compare two users to identify permission differences
     */
    public static Map<String, Object> compareUsers(
        Id workingUserId,
        Id failingUserId,
        String objectName,
        String fieldName
    ) {
        Map<String, Object> comparison = new Map<String, Object>();
        
        try {
            // Get permissions for both users
            SalesforceDiagnosticService.ObjectPermissionResult workingObj = 
                SalesforceDiagnosticService.checkObjectPermissions(objectName, workingUserId);
            
            SalesforceDiagnosticService.ObjectPermissionResult failingObj = 
                SalesforceDiagnosticService.checkObjectPermissions(objectName, failingUserId);
            
            // Compare object permissions
            comparison.put('workingUserObjectRead', workingObj.isAccessible);
            comparison.put('failingUserObjectRead', failingObj.isAccessible);
            comparison.put('objectReadDifference', workingObj.isAccessible != failingObj.isAccessible);
            
            if (String.isNotBlank(fieldName)) {
                // Compare field permissions
                SalesforceDiagnosticService.FieldPermissionResult workingField = 
                    SalesforceDiagnosticService.checkFieldLevelSecurity(objectName, fieldName, workingUserId);
                
                SalesforceDiagnosticService.FieldPermissionResult failingField = 
                    SalesforceDiagnosticService.checkFieldLevelSecurity(objectName, fieldName, failingUserId);
                
                comparison.put('workingUserFieldRead', workingField.isAccessible);
                comparison.put('failingUserFieldRead', failingField.isAccessible);
                comparison.put('fieldReadDifference', workingField.isAccessible != failingField.isAccessible);
            }
            
            // Compare profiles
            comparison.put('workingUserProfile', workingObj.profileName);
            comparison.put('failingUserProfile', failingObj.profileName);
            comparison.put('profileDifference', workingObj.profileName != failingObj.profileName);
            
        } catch (Exception e) {
            comparison.put('error', e.getMessage());
        }
        
        return comparison;
    }
}