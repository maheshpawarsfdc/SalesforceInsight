/**
 * @description Centralized error handling and recovery for diagnostic operations
 * Implements retry logic, graceful degradation, and error categorization
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class ErrorRecoveryService {
    
    // Error categories
    public enum ErrorCategory {
        GOVERNOR_LIMIT,
        CALLOUT_FAILURE,
        PERMISSION_DENIED,
        INVALID_INPUT,
        DATA_NOT_FOUND,
        SYSTEM_ERROR
    }
    
    /**
     * @description Error details wrapper
     */
    public class ErrorInfo {
        @AuraEnabled public ErrorCategory category;
        @AuraEnabled public String message;
        @AuraEnabled public String userFriendlyMessage;
        @AuraEnabled public Boolean isRecoverable;
        @AuraEnabled public String suggestedAction;
        @AuraEnabled public Integer retryAttempts;
        
        public ErrorInfo() {
            this.retryAttempts = 0;
            this.isRecoverable = false;
        }
    }
    
    /**
     * @description Categorize and handle exception
     * @param e Exception to handle
     * @param context Context where error occurred
     * @return ErrorInfo with categorization and recovery suggestions
     */
    public static ErrorInfo handleException(Exception e, String context) {
        ErrorInfo info = new ErrorInfo();
        info.message = e.getMessage();
        
        try {
            // Categorize the exception
            info.category = categorizeException(e);
            
            // Generate user-friendly message
            info.userFriendlyMessage = generateUserFriendlyMessage(e, context);
            
            // Determine if recoverable
            info.isRecoverable = isRecoverable(info.category);
            
            // Suggest action
            info.suggestedAction = suggestAction(info.category, context);
            
            // Log for monitoring
            logError(e, context, info);
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error in error handler: ' + ex.getMessage());
        }
        
        return info;
    }
    
    /**
     * @description Categorize exception type
     */
    private static ErrorCategory categorizeException(Exception e) {
        String exceptionType = e.getTypeName();
        String message = e.getMessage().toLowerCase();
        
        // Governor limit exceptions
        if (exceptionType.contains('LimitException')) {
            return ErrorCategory.GOVERNOR_LIMIT;
        }
        
        // Callout exceptions
        if (exceptionType.contains('CalloutException') || 
            message.contains('timeout') || 
            message.contains('connection')) {
            return ErrorCategory.CALLOUT_FAILURE;
        }
        
        // Permission exceptions
        if (message.contains('insufficient privileges') || 
            message.contains('no access') ||
            message.contains('permission')) {
            return ErrorCategory.PERMISSION_DENIED;
        }
        
        // Invalid input
        if (exceptionType.contains('NullPointerException') ||
            exceptionType.contains('TypeException') ||
            message.contains('invalid')) {
            return ErrorCategory.INVALID_INPUT;
        }
        
        // Data not found
        if (exceptionType.contains('QueryException') ||
            message.contains('list has no rows') ||
            message.contains('not found')) {
            return ErrorCategory.DATA_NOT_FOUND;
        }
        
        // Default to system error
        return ErrorCategory.SYSTEM_ERROR;
    }
    
    /**
     * @description Generate user-friendly error message
     */
    private static String generateUserFriendlyMessage(Exception e, String context) {
        ErrorCategory category = categorizeException(e);
        
        switch on category {
            when GOVERNOR_LIMIT {
                return 'I\'ve hit Salesforce resource limits while checking your permissions. ' +
                       'This usually happens with large-scale diagnostics. Try checking fewer items at once.';
            }
            when CALLOUT_FAILURE {
                return 'I\'m having trouble connecting to the diagnostic services right now. ' +
                       'Please try again in a moment.';
            }
            when PERMISSION_DENIED {
                return 'I don\'t have permission to check certain settings. ' +
                       'You might need System Administrator access to run full diagnostics.';
            }
            when INVALID_INPUT {
                return 'There seems to be an issue with the information provided. ' +
                       'Please check that object and field names are spelled correctly.';
            }
            when DATA_NOT_FOUND {
                return 'I couldn\'t find the object, field, or record you mentioned. ' +
                       'Please verify the name and try again.';
            }
            when else {
                return 'Something unexpected happened while running diagnostics. ' +
                       'Please try again or contact your Salesforce administrator.';
            }
        }
    }
    
    /**
     * @description Check if error is recoverable
     */
    private static Boolean isRecoverable(ErrorCategory category) {
        switch on category {
            when CALLOUT_FAILURE {
                return true; // Can retry
            }
            when GOVERNOR_LIMIT {
                return true; // Can reduce scope and retry
            }
            when INVALID_INPUT {
                return true; // User can provide correct input
            }
            when DATA_NOT_FOUND {
                return true; // User can provide correct data
            }
            when else {
                return false;
            }
        }
    }
    
    /**
     * @description Suggest recovery action
     */
    private static String suggestAction(ErrorCategory category, String context) {
        switch on category {
            when GOVERNOR_LIMIT {
                return 'Try checking fewer fields or objects at once, or use async diagnostics';
            }
            when CALLOUT_FAILURE {
                return 'Wait a moment and try again. Check your internet connection.';
            }
            when PERMISSION_DENIED {
                return 'Contact your System Administrator to run these diagnostics';
            }
            when INVALID_INPUT {
                return 'Verify object and field names are correct (case-sensitive)';
            }
            when DATA_NOT_FOUND {
                return 'Check if the object/field/record still exists in your org';
            }
            when else {
                return 'Contact your Salesforce administrator for help';
            }
        }
    }
    
    /**
     * @description Execute operation with retry logic
     * @param operation Operation to execute
     * @param maxRetries Maximum retry attempts
     * @param retryDelay Delay between retries (milliseconds)
     * @return Result of operation
     */
    public static Object executeWithRetry(
        Operation operation, 
        Integer maxRetries, 
        Integer retryDelay
    ) {
        Integer attempts = 0;
        Exception lastException = null;
        
        while (attempts < maxRetries) {
            try {
                return operation.execute();
            } catch (CalloutException e) {
                lastException = e;
                attempts++;
                
                if (attempts < maxRetries) {
                    System.debug('Retry attempt ' + attempts + ' after callout failure');
                    // Note: Cannot actually delay in synchronous Apex
                    // In real implementation, would use Queueable or @future
                }
            } catch (Exception e) {
                // Non-recoverable exception - don't retry
                throw e;
            }
        }
        
        // All retries failed
        throw lastException;
    }
    
    /**
     * @description Interface for retry operations
     */
    public interface Operation {
        Object execute();
    }
    
    /**
     * @description Graceful degradation - return partial results if possible
     */
    public static String gracefulDegradation(Exception e, String partialResult, String context) {
        ErrorInfo error = handleException(e, context);
        
        System.debug('Graceful degradation in ' + context + ': ' + error.userFriendlyMessage);
        
        // Return partial result if available
        if (String.isNotBlank(partialResult)) {
            System.debug('Returning partial result');
            return partialResult;
        }
        
        // Return error message
        return error.userFriendlyMessage;
    }
    
    /**
     * @description Check governor limits and warn if approaching
     */
    public static List<String> checkGovernorLimits() {
        List<String> warnings = new List<String>();
        
        // Check SOQL queries
        Integer soqlUsed = Limits.getQueries();
        Integer soqlLimit = Limits.getLimitQueries();
        Decimal soqlPercent = (Decimal.valueOf(soqlUsed) / soqlLimit) * 100;
        
        if (soqlPercent > 80) {
            warnings.add('SOQL queries: ' + soqlUsed + '/' + soqlLimit + ' (' + 
                        soqlPercent.setScale(0) + '% - approaching limit!)');
        }
        
        // Check callouts
        Integer calloutsUsed = Limits.getCallouts();
        Integer calloutsLimit = Limits.getLimitCallouts();
        Decimal calloutsPercent = (Decimal.valueOf(calloutsUsed) / calloutsLimit) * 100;
        
        if (calloutsPercent > 80) {
            warnings.add('Callouts: ' + calloutsUsed + '/' + calloutsLimit + ' (' + 
                        calloutsPercent.setScale(0) + '% - approaching limit!)');
        }
        
        // Check CPU time
        Integer cpuUsed = Limits.getCpuTime();
        Integer cpuLimit = Limits.getLimitCpuTime();
        Decimal cpuPercent = (Decimal.valueOf(cpuUsed) / cpuLimit) * 100;
        
        if (cpuPercent > 80) {
            warnings.add('CPU time: ' + cpuUsed + 'ms/' + cpuLimit + 'ms (' + 
                        cpuPercent.setScale(0) + '% - approaching limit!)');
        }
        
        // Check heap size
        Integer heapUsed = Limits.getHeapSize();
        Integer heapLimit = Limits.getLimitHeapSize();
        Decimal heapPercent = (Decimal.valueOf(heapUsed) / heapLimit) * 100;
        
        if (heapPercent > 80) {
            warnings.add('Heap size: ' + heapUsed + '/' + heapLimit + ' bytes (' + 
                        heapPercent.setScale(0) + '% - approaching limit!)');
        }
        
        return warnings;
    }
    
    /**
     * @description Log error for monitoring
     */
    private static void logError(Exception e, String context, ErrorInfo info) {
        // In production, this would create error log records or send to monitoring service
        System.debug(LoggingLevel.ERROR, '=== ERROR LOG ===');
        System.debug(LoggingLevel.ERROR, 'Context: ' + context);
        System.debug(LoggingLevel.ERROR, 'Category: ' + String.valueOf(info.category));
        System.debug(LoggingLevel.ERROR, 'Message: ' + e.getMessage());
        System.debug(LoggingLevel.ERROR, 'Type: ' + e.getTypeName());
        System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
        System.debug(LoggingLevel.ERROR, 'User Friendly: ' + info.userFriendlyMessage);
        
        /* PRODUCTION IMPLEMENTATION:
        Error_Log__c errorLog = new Error_Log__c(
            Context__c = context,
            Category__c = String.valueOf(info.category),
            Error_Message__c = e.getMessage(),
            Exception_Type__c = e.getTypeName(),
            Stack_Trace__c = e.getStackTraceString(),
            User_Friendly_Message__c = info.userFriendlyMessage,
            User__c = UserInfo.getUserId(),
            Timestamp__c = DateTime.now()
        );
        insert errorLog;
        */
    }
    
    /**
     * @description Safe execution wrapper
     * Executes code and returns result or error info
     */
    public static String safeExecute(Operation operation, String context) {
        try {
            Object result = operation.execute();
            return String.valueOf(result);
        } catch (Exception e) {
            ErrorInfo error = handleException(e, context);
            return error.userFriendlyMessage;
        }
    }
}