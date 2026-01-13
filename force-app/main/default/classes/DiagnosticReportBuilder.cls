/**
 * @description Builder class for creating comprehensive diagnostic reports
 * Formats results from SalesforceDiagnosticService and MetadataQueryService
 * into human-readable and AI-friendly reports
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class DiagnosticReportBuilder {
    
    // Inner classes for structured report data
    public class DiagnosticReport {
        @AuraEnabled public String reportId;
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public UserContext userContext;
        @AuraEnabled public List<DiagnosticFinding> findings;
        @AuraEnabled public ReportSummary summary;
        @AuraEnabled public String plainTextReport;
        @AuraEnabled public String jsonReport;
        
        public DiagnosticReport() {
            this.reportId = generateReportId();
            this.timestamp = DateTime.now();
            this.findings = new List<DiagnosticFinding>();
            this.userContext = new UserContext();
            this.summary = new ReportSummary();
        }
        
        private String generateReportId() {
            return 'DR-' + String.valueOf(DateTime.now().getTime());
        }
    }
    
    public class UserContext {
        @AuraEnabled public String userName;
        @AuraEnabled public String userId;
        @AuraEnabled public String profileName;
        @AuraEnabled public List<String> permissionSets;
        @AuraEnabled public String userRole;
        @AuraEnabled public Boolean isActive;
        
        public UserContext() {
            this.permissionSets = new List<String>();
        }
    }
    
    public class DiagnosticFinding {
        @AuraEnabled public Integer sequenceNumber;
        @AuraEnabled public String category;
        @AuraEnabled public String status; // PASS, FAIL, WARNING
        @AuraEnabled public String statusIcon; // ✓, ✗, ⚠
        @AuraEnabled public String title;
        @AuraEnabled public List<String> details;
        @AuraEnabled public String impact;
        @AuraEnabled public Severity severity;
        
        public DiagnosticFinding() {
            this.details = new List<String>();
        }
    }
    
    public class ReportSummary {
        @AuraEnabled public String rootCause;
        @AuraEnabled public Severity overallSeverity;
        @AuraEnabled public Integer totalChecks;
        @AuraEnabled public Integer passedChecks;
        @AuraEnabled public Integer failedChecks;
        @AuraEnabled public Integer warningChecks;
        @AuraEnabled public List<String> suggestedActions;
        @AuraEnabled public List<String> whoCanHelp;
        @AuraEnabled public String nextSteps;
        
        public ReportSummary() {
            this.suggestedActions = new List<String>();
            this.whoCanHelp = new List<String>();
            this.totalChecks = 0;
            this.passedChecks = 0;
            this.failedChecks = 0;
            this.warningChecks = 0;
        }
    }
    
    public enum Severity {
        HIGH, MEDIUM, LOW, INFO
    }
    
    /**
     * @description Create a new diagnostic report builder instance
     * @param userId User being diagnosed
     * @return DiagnosticReport instance
     */
    public static DiagnosticReport createReport(Id userId) {
        DiagnosticReport report = new DiagnosticReport();
        
        try {
            // Populate user context
            populateUserContext(report, userId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error creating report: ' + e.getMessage());
        }
        
        return report;
    }
    
    /**
     * @description Add object permission check results to report
     * @param report The diagnostic report
     * @param objectName Object being checked
     * @param permResult Permission check result from SalesforceDiagnosticService
     */
    public static void addObjectPermissionFinding(
        DiagnosticReport report, 
        String objectName,
        SalesforceDiagnosticService.ObjectPermissionResult permResult
    ) {
        if (report == null || permResult == null) {
            return;
        }
        
        DiagnosticFinding finding = new DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Object Access';
        finding.title = 'Object-Level Permissions: ' + objectName;
        
        // Determine overall status
        if (permResult.errorMessage != null) {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('Error: ' + permResult.errorMessage);
        } else if (permResult.isAccessible) {
            finding.status = 'PASS';
            finding.statusIcon = '✓';
            finding.severity = Severity.INFO;
            finding.details.add('✓ Can Read: YES');
            finding.details.add(permResult.isCreateable ? '✓ Can Create: YES' : '✗ Can Create: NO');
            finding.details.add(permResult.isUpdateable ? '✓ Can Edit: YES' : '✗ Can Edit: NO');
            finding.details.add(permResult.isDeletable ? '✓ Can Delete: YES' : '✗ Can Delete: NO');
            
            if (!permResult.isCreateable || !permResult.isUpdateable || !permResult.isDeletable) {
                finding.status = 'WARNING';
                finding.statusIcon = '⚠';
                finding.severity = Severity.MEDIUM;
            }
        } else {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('✗ No Read Access');
            finding.impact = 'User cannot view any ' + objectName + ' records';
        }
        
        // Add permission details
        if (permResult.permissionDetails != null && !permResult.permissionDetails.isEmpty()) {
            finding.details.addAll(permResult.permissionDetails);
        }
        
        report.findings.add(finding);
        updateReportCounters(report, finding);
    }
    
    /**
     * @description Add field-level security check results to report
     * @param report The diagnostic report
     * @param objectName Object name
     * @param fieldName Field name
     * @param fieldResult FLS check result from SalesforceDiagnosticService
     */
    public static void addFieldSecurityFinding(
        DiagnosticReport report,
        String objectName,
        String fieldName,
        SalesforceDiagnosticService.FieldPermissionResult fieldResult
    ) {
        if (report == null || fieldResult == null) {
            return;
        }
        
        DiagnosticFinding finding = new DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Field-Level Security';
        finding.title = 'Field Access: ' + objectName + '.' + fieldName;
        
        // Determine status
        if (fieldResult.errorMessage != null) {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('Error: ' + fieldResult.errorMessage);
            
            // Check if it's a "field doesn't exist" error
            if (fieldResult.errorMessage.contains('does not exist')) {
                finding.impact = 'Field "' + fieldName + '" does not exist on ' + objectName + ' object';
            }
        } else if (fieldResult.isAccessible) {
            finding.status = 'PASS';
            finding.statusIcon = '✓';
            finding.severity = Severity.INFO;
            finding.details.add('✓ Field Exists: YES');
            finding.details.add('✓ Can View: YES');
            finding.details.add(fieldResult.isUpdateable ? '✓ Can Edit: YES' : '✗ Can Edit: NO (Read-only)');
            
            if (!fieldResult.isUpdateable) {
                finding.status = 'WARNING';
                finding.statusIcon = '⚠';
                finding.severity = Severity.MEDIUM;
                finding.impact = 'Field is visible but read-only';
            }
        } else {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('✓ Field Exists: YES');
            finding.details.add('✗ Can View: NO');
            finding.details.add('✗ Can Edit: NO');
            finding.impact = 'Field exists but Field-Level Security prevents viewing';
        }
        
        // Add permission details
        if (fieldResult.permissionDetails != null && !fieldResult.permissionDetails.isEmpty()) {
            finding.details.addAll(fieldResult.permissionDetails);
        }
        
        report.findings.add(finding);
        updateReportCounters(report, finding);
    }
    
    /**
     * @description Add record access check results to report
     * @param report The diagnostic report
     * @param recordId Record ID being checked
     * @param recordAccess Access check result from SalesforceDiagnosticService
     */
    public static void addRecordAccessFinding(
        DiagnosticReport report,
        Id recordId,
        SalesforceDiagnosticService.RecordAccess recordAccess
    ) {
        if (report == null || recordAccess == null) {
            return;
        }
        
        DiagnosticFinding finding = new DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Record Access';
        finding.title = 'Record-Level Access: ' + recordId;
        
        // Determine status
        if (recordAccess.errorMessage != null) {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('Error: ' + recordAccess.errorMessage);
            finding.impact = 'Unable to determine record access';
        } else if (recordAccess.hasReadAccess) {
            finding.status = 'PASS';
            finding.statusIcon = '✓';
            finding.severity = Severity.INFO;
            finding.details.add('✓ Can View: YES');
            finding.details.add(recordAccess.hasEditAccess ? '✓ Can Edit: YES' : '✗ Can Edit: NO');
            finding.details.add(recordAccess.hasDeleteAccess ? '✓ Can Delete: YES' : '✗ Can Delete: NO');
            finding.details.add(recordAccess.hasTransferAccess ? '✓ Can Transfer: YES' : '✗ Can Transfer: NO');
            finding.details.add('Max Access Level: ' + recordAccess.maxAccessLevel);
            
            if (!recordAccess.hasEditAccess) {
                finding.status = 'WARNING';
                finding.statusIcon = '⚠';
                finding.severity = Severity.MEDIUM;
                finding.impact = 'Read-only access to record';
            }
        } else {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('✗ No Access to Record');
            finding.impact = 'User cannot view this record due to sharing rules or ownership';
        }
        
        report.findings.add(finding);
        updateReportCounters(report, finding);
    }
    
    /**
     * @description Add field existence check results to report
     * @param report The diagnostic report
     * @param objectName Object name
     * @param fieldName Field name
     * @param exists Whether field exists
     */
    public static void addFieldExistenceFinding(
        DiagnosticReport report,
        String objectName,
        String fieldName,
        Boolean exists
    ) {
        if (report == null) {
            return;
        }
        
        DiagnosticFinding finding = new DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Field Existence';
        finding.title = 'Field Validation: ' + objectName + '.' + fieldName;
        
        if (exists) {
            finding.status = 'PASS';
            finding.statusIcon = '✓';
            finding.severity = Severity.INFO;
            finding.details.add('✓ Field exists on ' + objectName);
        } else {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('✗ Field "' + fieldName + '" does not exist on ' + objectName);
            finding.impact = 'Field name may be misspelled or field may have been deleted';
        }
        
        report.findings.add(finding);
        updateReportCounters(report, finding);
    }
    
    /**
     * @description Add object existence check results to report
     * @param report The diagnostic report
     * @param objectName Object name
     * @param exists Whether object exists
     */
    public static void addObjectExistenceFinding(
        DiagnosticReport report,
        String objectName,
        Boolean exists
    ) {
        if (report == null) {
            return;
        }
        
        DiagnosticFinding finding = new DiagnosticFinding();
        finding.sequenceNumber = report.findings.size() + 1;
        finding.category = 'Object Existence';
        finding.title = 'Object Validation: ' + objectName;
        
        if (exists) {
            finding.status = 'PASS';
            finding.statusIcon = '✓';
            finding.severity = Severity.INFO;
            finding.details.add('✓ Object exists in org');
        } else {
            finding.status = 'FAIL';
            finding.statusIcon = '✗';
            finding.severity = Severity.HIGH;
            finding.details.add('✗ Object "' + objectName + '" does not exist');
            finding.impact = 'Object name may be misspelled or object may not be deployed to this org';
        }
        
        report.findings.add(finding);
        updateReportCounters(report, finding);
    }
    
    /**
     * @description Finalize the report by generating summary and output formats
     * @param report The diagnostic report
     */
    public static void finalizeReport(DiagnosticReport report) {
        if (report == null) {
            return;
        }
        
        try {
            // Generate summary
            generateSummary(report);
            
            // Generate plain text format
            report.plainTextReport = generatePlainTextReport(report);
            
            // Generate JSON format
            report.jsonReport = JSON.serializePretty(report);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error finalizing report: ' + e.getMessage());
        }
    }
    
    /**
     * @description Generate summary section of the report
     * @param report The diagnostic report
     */
    private static void generateSummary(DiagnosticReport report) {
        if (report == null || report.findings.isEmpty()) {
            report.summary.rootCause = 'No diagnostic checks performed';
            report.summary.overallSeverity = Severity.INFO;
            return;
        }
        
        // Determine root cause based on failed checks
        List<String> failedCategories = new List<String>();
        Severity highestSeverity = Severity.INFO;
        
        for (DiagnosticFinding finding : report.findings) {
            if (finding.status == 'FAIL') {
                failedCategories.add(finding.category);
            }
            
            // Track highest severity
            if (finding.severity == Severity.HIGH) {
                highestSeverity = Severity.HIGH;
            } else if (finding.severity == Severity.MEDIUM && highestSeverity != Severity.HIGH) {
                highestSeverity = Severity.MEDIUM;
            } else if (finding.severity == Severity.LOW && highestSeverity == Severity.INFO) {
                highestSeverity = Severity.LOW;
            }
        }
        
        report.summary.overallSeverity = highestSeverity;
        
        // Set root cause
        if (failedCategories.isEmpty()) {
            if (report.summary.warningChecks > 0) {
                report.summary.rootCause = 'Some permissions are limited but functional';
            } else {
                report.summary.rootCause = 'All checks passed successfully';
            }
        } else if (failedCategories.size() == 1) {
            report.summary.rootCause = failedCategories[0] + ' restriction';
        } else {
            report.summary.rootCause = 'Multiple permission issues: ' + String.join(failedCategories, ', ');
        }
        
        // Generate suggested actions based on findings
        generateSuggestedActions(report);
        
        // Set next steps
        if (report.summary.failedChecks > 0) {
            report.summary.nextSteps = 'Contact your Salesforce administrator to review and update permissions';
        } else if (report.summary.warningChecks > 0) {
            report.summary.nextSteps = 'Review limited permissions with your administrator if full access is needed';
        } else {
            report.summary.nextSteps = 'All permissions are in order. If issue persists, check for other causes.';
        }
    }
    
    /**
     * @description Generate suggested actions based on findings
     * @param report The diagnostic report
     */
    private static void generateSuggestedActions(DiagnosticReport report) {
        Set<String> actions = new Set<String>();
        
        for (DiagnosticFinding finding : report.findings) {
            if (finding.status == 'FAIL' || finding.status == 'WARNING') {
                if (finding.category == 'Field-Level Security') {
                    actions.add('Update Field-Level Security settings for affected fields');
                    actions.add('Grant "Visible" and "Editable" permissions to user profile or permission set');
                } else if (finding.category == 'Object Access') {
                    actions.add('Update Object permissions in user profile or permission set');
                    actions.add('Grant Read, Create, Edit, or Delete access as needed');
                } else if (finding.category == 'Record Access') {
                    actions.add('Review sharing rules for the object');
                    actions.add('Check if user is record owner or has role hierarchy access');
                    actions.add('Consider adding user to sharing rule or manual sharing');
                } else if (finding.category == 'Field Existence' || finding.category == 'Object Existence') {
                    actions.add('Verify correct spelling of object/field name');
                    actions.add('Check if field/object exists in this org');
                    actions.add('Deploy field/object if missing');
                }
            }
        }
        
        report.summary.suggestedActions.addAll(actions);
        
        // Add who can help
        report.summary.whoCanHelp.add('Salesforce Administrator');
        if (report.summary.failedChecks > 0 || report.summary.warningChecks > 0) {
            report.summary.whoCanHelp.add('System Administrator');
        }
    }
    
    /**
     * @description Generate plain text version of the report
     * @param report The diagnostic report
     * @return Formatted plain text report
     */
    public static String generatePlainTextReport(DiagnosticReport report) {
        if (report == null) {
            return 'No report data available';
        }
        
        StringBuilder sb = new StringBuilder();
        
        // Header
        sb.append('═══════════════════════════════════════════════════════════\n');
        sb.append('DIAGNOSTIC REPORT\n');
        sb.append('═══════════════════════════════════════════════════════════\n');
        sb.append('Report ID: ' + report.reportId + '\n');
        sb.append('Generated: ' + report.timestamp.format('yyyy-MM-dd HH:mm:ss') + '\n\n');
        
        // User Context
        sb.append('USER CONTEXT:\n');
        sb.append('───────────────────────────────────────────────────────────\n');
        if (report.userContext != null) {
            sb.append('Name: ' + (report.userContext.userName != null ? report.userContext.userName : 'Unknown') + '\n');
            sb.append('Profile: ' + (report.userContext.profileName != null ? report.userContext.profileName : 'Unknown') + '\n');
            if (report.userContext.userRole != null) {
                sb.append('Role: ' + report.userContext.userRole + '\n');
            }
            if (report.userContext.permissionSets != null && !report.userContext.permissionSets.isEmpty()) {
                sb.append('Permission Sets: ' + String.join(report.userContext.permissionSets, ', ') + '\n');
            }
        }
        sb.append('\n');
        
        // Findings
        if (report.findings != null && !report.findings.isEmpty()) {
            sb.append('FINDINGS:\n');
            sb.append('───────────────────────────────────────────────────────────\n');
            
            for (DiagnosticFinding finding : report.findings) {
                sb.append('\n' + finding.sequenceNumber + '. ' + finding.title.toUpperCase() + '\n');
                sb.append('   Status: ' + finding.statusIcon + ' ' + finding.status + '\n');
                if (finding.severity != null) {
                    sb.append('   Severity: ' + finding.severity + '\n');
                }
                
                if (finding.details != null && !finding.details.isEmpty()) {
                    for (String detail : finding.details) {
                        sb.append('   ' + detail + '\n');
                    }
                }
                
                if (String.isNotBlank(finding.impact)) {
                    sb.append('   Impact: ' + finding.impact + '\n');
                }
            }
        } else {
            sb.append('No diagnostic findings recorded.\n');
        }
        
        sb.append('\n');
        
        // Summary
        sb.append('SUMMARY:\n');
        sb.append('───────────────────────────────────────────────────────────\n');
        if (report.summary != null) {
            sb.append('Root Cause: ' + (report.summary.rootCause != null ? report.summary.rootCause : 'Unknown') + '\n');
            sb.append('Overall Severity: ' + (report.summary.overallSeverity != null ? report.summary.overallSeverity : Severity.INFO) + '\n');
            sb.append('Total Checks: ' + report.summary.totalChecks + 
                     ' (Passed: ' + report.summary.passedChecks + 
                     ', Failed: ' + report.summary.failedChecks + 
                     ', Warnings: ' + report.summary.warningChecks + ')\n');
            
            if (report.summary.suggestedActions != null && !report.summary.suggestedActions.isEmpty()) {
                sb.append('\nSUGGESTED ACTIONS:\n');
                Integer actionNum = 1;
                for (String action : report.summary.suggestedActions) {
                    sb.append('   ' + actionNum + '. ' + action + '\n');
                    actionNum++;
                }
            }
            
            if (report.summary.whoCanHelp != null && !report.summary.whoCanHelp.isEmpty()) {
                sb.append('\nWHO CAN HELP:\n');
                for (String contact : report.summary.whoCanHelp) {
                    sb.append('   • ' + contact + '\n');
                }
            }
            
            if (String.isNotBlank(report.summary.nextSteps)) {
                sb.append('\nNEXT STEPS:\n');
                sb.append('   ' + report.summary.nextSteps + '\n');
            }
        }
        
        sb.append('\n═══════════════════════════════════════════════════════════\n');
        
        return sb.toString();
    }
    
    /**
     * @description Populate user context information
     * @param report The diagnostic report
     * @param userId User ID
     */
    private static void populateUserContext(DiagnosticReport report, Id userId) {
        if (report == null || userId == null) {
            return;
        }
        
        try {
            // Get user profile info
            SalesforceDiagnosticService.ProfileInfo profile = 
                SalesforceDiagnosticService.getUserProfile(userId);
            
            if (profile != null && profile.errorMessage == null) {
                report.userContext.userId = String.valueOf(userId);
                report.userContext.profileName = profile.profileName;
                report.userContext.userRole = profile.userRole;
                report.userContext.isActive = profile.isActive;
                
                // Get user name
                User u = [SELECT Name FROM User WHERE Id = :userId LIMIT 1];
                report.userContext.userName = u.Name;
            }
            
            // Get permission sets
            List<SalesforceDiagnosticService.PermissionSetInfo> permSets = 
                SalesforceDiagnosticService.getUserPermissionSets(userId);
            
            for (SalesforceDiagnosticService.PermissionSetInfo ps : permSets) {
                report.userContext.permissionSets.add(ps.permissionSetLabel);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error populating user context: ' + e.getMessage());
        }
    }
    
    /**
     * @description Update report counters based on finding status
     * @param report The diagnostic report
     * @param finding The finding being added
     */
    private static void updateReportCounters(DiagnosticReport report, DiagnosticFinding finding) {
        if (report == null || finding == null) {
            return;
        }
        
        report.summary.totalChecks++;
        
        if (finding.status == 'PASS') {
            report.summary.passedChecks++;
        } else if (finding.status == 'FAIL') {
            report.summary.failedChecks++;
        } else if (finding.status == 'WARNING') {
            report.summary.warningChecks++;
        }
    }
    
    /**
     * @description Helper class for building report text
     */
    private class StringBuilder {
        private List<String> parts = new List<String>();
        
        public void append(String text) {
            parts.add(text);
        }
        
        public override String toString() {
            return String.join(parts, '');
        }
    }
}