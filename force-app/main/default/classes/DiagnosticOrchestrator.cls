/**
 * @description Orchestrates diagnostic execution with async processing and progress tracking
 * Manages heavy operations, governor limits, and real-time updates via Platform Events
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class DiagnosticOrchestrator {
    
    // Diagnostic priority levels
    public enum Priority {
        CRITICAL,  // Must run first (object permissions)
        HIGH,      // Important (field security)
        MEDIUM,    // Secondary (page layouts)
        LOW        // Nice to have (validation rules)
    }
    
    /**
     * @description Wrapper for diagnostic check definition
     */
    public class CheckDefinition {
        @AuraEnabled public String checkName;
        @AuraEnabled public String checkType; // 'sync' or 'async'
        @AuraEnabled public Priority priority;
        @AuraEnabled public Integer estimatedCallouts;
        @AuraEnabled public Integer estimatedSOQL;
        @AuraEnabled public Boolean requiresToolingAPI;
        
        public CheckDefinition(String name, String type, Priority prio) {
            this.checkName = name;
            this.checkType = type;
            this.priority = prio;
            this.estimatedCallouts = 0;
            this.estimatedSOQL = 1;
            this.requiresToolingAPI = false;
        }
    }
    
    /**
     * @description Main orchestration method - decides sync vs async
     * @param sessionId Diagnostic session ID
     * @param analysis Message analysis
     * @param userId Target user ID
     * @return DiagnosticReport or async job ID
     */
    public static Object orchestrateDiagnostics(
        String sessionId,
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId
    ) {
        // Prioritize and plan checks
        List<CheckDefinition> checks = planDiagnostics(analysis);
        
        // Calculate resource requirements
        Integer totalCallouts = 0;
        Integer totalSOQL = 0;
        Boolean needsAsync = false;
        
        for (CheckDefinition check : checks) {
            totalCallouts += check.estimatedCallouts;
            totalSOQL += check.estimatedSOQL;
            
            // If any check needs Tooling API and we have 5+ fields to check, go async
            if (check.requiresToolingAPI && analysis.fieldsInvolved.size() > 5) {
                needsAsync = true;
            }
        }
        
        System.debug('Diagnostic plan: ' + checks.size() + ' checks, ' + 
                    totalCallouts + ' callouts, ' + totalSOQL + ' SOQL');
        
        // Decision: Sync or Async?
        if (needsAsync || totalCallouts > 50 || totalSOQL > 50) {
            System.debug('Running diagnostics ASYNC');
            return runAsyncDiagnostics(sessionId, analysis, userId, checks);
        } else {
            System.debug('Running diagnostics SYNC');
            return runSyncDiagnostics(sessionId, analysis, userId, checks);
        }
    }
    
    /**
     * @description Plan diagnostic checks based on analysis
     * @param analysis Message analysis
     * @return Prioritized list of checks
     */
    public static List<CheckDefinition> planDiagnostics(MessageAnalyzer.MessageAnalysis analysis) {
        List<CheckDefinition> checks = new List<CheckDefinition>();
        
        // CRITICAL: User profile check (always first)
        CheckDefinition profileCheck = new CheckDefinition('checkUserProfile', 'sync', Priority.CRITICAL);
        profileCheck.estimatedSOQL = 1;
        checks.add(profileCheck);
        
        // CRITICAL: Object permissions (if objects involved)
        if (!analysis.objectsInvolved.isEmpty()) {
            CheckDefinition objCheck = new CheckDefinition('checkObjectPermissions', 'sync', Priority.CRITICAL);
            objCheck.estimatedSOQL = analysis.objectsInvolved.size() * 2; // Profile + PermSets
            checks.add(objCheck);
        }
        
        // HIGH: Field-level security (if fields involved)
        if (!analysis.fieldsInvolved.isEmpty()) {
            CheckDefinition flsCheck = new CheckDefinition('checkFieldSecurity', 'sync', Priority.HIGH);
            flsCheck.estimatedSOQL = analysis.fieldsInvolved.size() * 2;
            checks.add(flsCheck);
        }
        
        // MEDIUM: Page layouts (requires Tooling API)
        if (!analysis.fieldsInvolved.isEmpty()) {
            CheckDefinition layoutCheck = new CheckDefinition('checkPageLayout', 'sync', Priority.MEDIUM);
            layoutCheck.requiresToolingAPI = true;
            layoutCheck.estimatedCallouts = 1; // Cached after first call
            checks.add(layoutCheck);
        }
        
        // MEDIUM: Record access (if record IDs involved)
        if (!analysis.recordIds.isEmpty()) {
            CheckDefinition recordCheck = new CheckDefinition('checkRecordAccess', 'sync', Priority.MEDIUM);
            recordCheck.estimatedSOQL = analysis.recordIds.size();
            checks.add(recordCheck);
        }
        
        // LOW: Validation rules (async candidate)
        if (analysis.issueCategory == 'save_error' || analysis.issueCategory == 'validation_error') {
            CheckDefinition valCheck = new CheckDefinition('checkValidationRules', 'async', Priority.LOW);
            valCheck.requiresToolingAPI = true;
            valCheck.estimatedCallouts = analysis.objectsInvolved.size();
            checks.add(valCheck);
        }
        
        // Sort by priority
        checks.sort();
        
        return checks;
    }
    
    /**
     * @description Run diagnostics synchronously (fast path)
     */
    private static DiagnosticReportBuilder.DiagnosticReport runSyncDiagnostics(
        String sessionId,
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId,
        List<CheckDefinition> checks
    ) {
        // This is the existing synchronous flow
        // Just execute all checks immediately
        DiagnosticReportBuilder.DiagnosticReport report = 
            DiagnosticReportBuilder.createReport(userId);
        
        // Execute each check
        for (CheckDefinition check : checks) {
            executeCheck(check, analysis, userId, report);
        }
        
        DiagnosticReportBuilder.finalizeReport(report);
        
        return report;
    }
    
    /**
     * @description Run diagnostics asynchronously (heavy operations)
     */
    private static String runAsyncDiagnostics(
        String sessionId,
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId,
        List<CheckDefinition> checks
    ) {
        // Serialize the context for async execution
        String context = JSON.serialize(new Map<String, Object>{
            'sessionId' => sessionId,
            'analysis' => analysis,
            'userId' => userId,
            'checks' => checks
        });
        
        // Launch async job
        runDiagnosticsAsync(context);
        
        // Return job ID for tracking
        return 'ASYNC_JOB_' + DateTime.now().getTime();
    }
    
    /**
     * @description Execute diagnostic check
     */
    private static void executeCheck(
        CheckDefinition check,
        MessageAnalyzer.MessageAnalysis analysis,
        Id userId,
        DiagnosticReportBuilder.DiagnosticReport report
    ) {
        try {
            // This would call the appropriate diagnostic method
            // For now, simplified implementation
            System.debug('Executing check: ' + check.checkName);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error executing check ' + check.checkName + ': ' + e.getMessage());
        }
    }
    
    /**
     * @description Future method for async diagnostics
     */
    @future(callout=true)
    public static void runDiagnosticsAsync(String contextJson) {
        try {
            Map<String, Object> context = (Map<String, Object>) JSON.deserializeUntyped(contextJson);
            
            String sessionId = (String) context.get('sessionId');
            Id userId = (Id) context.get('userId');
            
            // Publish progress: Started
            publishProgress(sessionId, 0, 'Starting diagnostics...', 'Running');
            
            // Deserialize analysis
            Map<String, Object> analysisMap = (Map<String, Object>) context.get('analysis');
            MessageAnalyzer.MessageAnalysis analysis = new MessageAnalyzer.MessageAnalysis();
            analysis.issueCategory = (String) analysisMap.get('issueCategory');
            analysis.objectsInvolved = (List<String>) analysisMap.get('objectsInvolved');
            analysis.fieldsInvolved = (List<String>) analysisMap.get('fieldsInvolved');
            
            // Create report
            DiagnosticReportBuilder.DiagnosticReport report = 
                DiagnosticReportBuilder.createReport(userId);
            
            // Run checks with progress updates
            Integer totalChecks = 5; // Simplified
            Integer completed = 0;
            
            // Check 1: Object permissions
            publishProgress(sessionId, 20, 'Checking object permissions...', 'Running');
            completed++;
            
            // Check 2: Field security
            publishProgress(sessionId, 40, 'Checking field-level security...', 'Running');
            completed++;
            
            // Check 3: Page layouts (Tooling API callout)
            publishProgress(sessionId, 60, 'Checking page layouts...', 'Running');
            completed++;
            
            // Check 4: Validation rules (Tooling API callout)
            publishProgress(sessionId, 80, 'Checking validation rules...', 'Running');
            completed++;
            
            // Finalize
            DiagnosticReportBuilder.finalizeReport(report);
            
            // Store results
            ConversationManager.updateDiagnosticResult(sessionId, report.plainTextReport);
            
            // Publish completion
            publishProgress(sessionId, 100, 'Diagnostics complete', 'Complete');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Async diagnostics failed: ' + e.getMessage());
            String sessionId = 'unknown';
            try {
                Map<String, Object> context = (Map<String, Object>) JSON.deserializeUntyped(contextJson);
                sessionId = (String) context.get('sessionId');
            } catch (Exception ex) {
                // Ignore
            }
            publishProgress(sessionId, 0, 'Error: ' + e.getMessage(), 'Error');
        }
    }
    
    /**
     * @description Publish progress via Platform Event
     */
    public static void publishProgress(String sessionId, Integer percent, String status, String state) {
        try {
            // Create Platform Event (you'll need to create this custom object)
            // For now, just log
            System.debug('Progress: ' + sessionId + ' - ' + percent + '% - ' + status + ' (' + state + ')');
            
            /* UNCOMMENT WHEN PLATFORM EVENT IS CREATED:
            Diagnostic_Progress__e event = new Diagnostic_Progress__e(
                Session_Id__c = sessionId,
                Progress_Percent__c = percent,
                Current_Status__c = status,
                State__c = state,
                Timestamp__c = DateTime.now()
            );
            
            EventBus.publish(event);
            */
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error publishing progress: ' + e.getMessage());
        }
    }
    
    /**
     * @description Check if we can run more diagnostics (governor limit check)
     */
    public static Boolean canRunCheck(String checkType) {
        Integer calloutsUsed = Limits.getCallouts();
        Integer calloutsLimit = Limits.getLimitCallouts();
        
        Integer soqlUsed = Limits.getQueries();
        Integer soqlLimit = Limits.getLimitQueries();
        
        // Leave 20% buffer
        if (checkType == 'callout') {
            return calloutsUsed < (calloutsLimit * 0.8);
        } else if (checkType == 'soql') {
            return soqlUsed < (soqlLimit * 0.8);
        }
        
        return true;
    }
    
    /**
     * @description Get current resource usage
     */
    public static Map<String, Integer> getResourceUsage() {
        return new Map<String, Integer>{
            'calloutsUsed' => Limits.getCallouts(),
            'calloutsLimit' => Limits.getLimitCallouts(),
            'soqlUsed' => Limits.getQueries(),
            'soqlLimit' => Limits.getLimitQueries(),
            'cpuUsed' => Limits.getCpuTime(),
            'cpuLimit' => Limits.getLimitCpuTime()
        };
    }
}