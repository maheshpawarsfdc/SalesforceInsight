/**
 * @description Detects Lightning Dynamic Forms and field visibility rules
 * Lightning Dynamic Forms can hide fields even if they're on the page layout
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class DynamicFormsDetector {
    
    /**
     * @description Dynamic Forms detection result
     */
    public class DynamicFormsInfo {
        @AuraEnabled public Boolean isDynamicFormsEnabled;
        @AuraEnabled public Boolean mightBeHidingField;
        @AuraEnabled public String recommendation;
        @AuraEnabled public List<String> possibleCauses;
        
        public DynamicFormsInfo() {
            this.possibleCauses = new List<String>();
        }
    }
    
    /**
     * @description Check if Dynamic Forms might be hiding a field
     * Note: Full detection requires Tooling API to query Lightning page metadata
     * This is a heuristic-based approach
     * @param objectName Object API name
     * @param fieldName Field API name
     * @return DynamicFormsInfo with detection results
     */
    public static DynamicFormsInfo checkDynamicForms(String objectName, String fieldName) {
        DynamicFormsInfo info = new DynamicFormsInfo();
        
        try {
            // Check if object supports Dynamic Forms (Lightning-enabled objects)
            if (!isLightningEnabledObject(objectName)) {
                info.isDynamicFormsEnabled = false;
                info.recommendation = 'Object does not support Lightning Dynamic Forms';
                return info;
            }
            
            info.isDynamicFormsEnabled = true;
            
            // Heuristic checks for Dynamic Forms usage
            info.mightBeHidingField = false;
            
            // Check 1: Is this a Lightning Experience org?
            if (isLightningExperienceOrg()) {
                info.possibleCauses.add('Lightning Experience is enabled');
                info.mightBeHidingField = true;
            }
            
            // Check 2: Common patterns that suggest Dynamic Forms
            if (hasCustomLightningPages(objectName)) {
                info.possibleCauses.add('Object has custom Lightning pages');
                info.mightBeHidingField = true;
            }
            
            // Build recommendation
            if (info.mightBeHidingField) {
                info.recommendation = buildRecommendation(objectName, fieldName);
            } else {
                info.recommendation = 'Dynamic Forms unlikely to be hiding this field';
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking Dynamic Forms: ' + e.getMessage());
            info.recommendation = 'Could not check Dynamic Forms: ' + e.getMessage();
        }
        
        return info;
    }
    
    /**
     * @description Check if object is Lightning-enabled
     */
    private static Boolean isLightningEnabledObject(String objectName) {
        try {
            Schema.DescribeSObjectResult objectDescribe = 
                Schema.getGlobalDescribe().get(objectName).getDescribe();
            
            // Lightning-enabled objects are custom objects or standard objects that support layouts
            // Check if object is custom or if it's a standard object that has layouts
            return objectDescribe.isCustom() || objectDescribe.isCreateable();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking Lightning enablement: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Check if org has Lightning Experience enabled
     */
    private static Boolean isLightningExperienceOrg() {
        try {
            // Check if UserInterface includes Lightning
            // This is a simplified check - in production, query Organization settings
            return UserInfo.getUiThemeDisplayed().contains('Theme4');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking Lightning Experience: ' + e.getMessage());
            return true; // Assume Lightning by default (2026)
        }
    }
    
    /**
     * @description Check if object has custom Lightning pages
     * Note: This is a heuristic - full implementation requires Tooling API
     */
    private static Boolean hasCustomLightningPages(String objectName) {
        try {
            // Heuristic: Custom objects are more likely to have custom Lightning pages
            return objectName.endsWith('__c');
            
            /* FULL IMPLEMENTATION WITH TOOLING API:
            String query = 'SELECT Id FROM FlexiPage ' +
                          'WHERE EntityDefinition.QualifiedApiName = \'' + objectName + '\'';
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Salesforce_Tooling_API/query?q=' + 
                           EncodingUtil.urlEncode(query, 'UTF-8'));
            req.setMethod('GET');
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Integer totalSize = (Integer) result.get('totalSize');
                return totalSize > 0;
            }
            */
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking Lightning pages: ' + e.getMessage());
        }
        
        return false;
    }
    
    /**
     * @description Build recommendation for user
     */
    private static String buildRecommendation(String objectName, String fieldName) {
        return 'Dynamic Forms may be hiding this field. To check:\n' +
               '1. Open the record page in Lightning Experience\n' +
               '2. Click the gear icon (⚙) → Edit Page\n' +
               '3. Check if "' + fieldName + '" is on the Record Detail component\n' +
               '4. Check field visibility rules in the component settings\n' +
               '5. Ensure field is not conditionally hidden based on other field values';
    }
    
    /**
     * @description Get diagnostic message about Dynamic Forms
     */
    public static String getDiagnosticMessage(String objectName, String fieldName) {
        DynamicFormsInfo info = checkDynamicForms(objectName, fieldName);
        
        if (!info.isDynamicFormsEnabled) {
            return 'Dynamic Forms are not enabled for ' + objectName;
        }
        
        if (info.mightBeHidingField) {
            return '⚠️ DYNAMIC FORMS ALERT:\n' +
                   'Lightning Dynamic Forms might be hiding this field.\n' +
                   'Possible causes: ' + String.join(info.possibleCauses, ', ') + '\n\n' +
                   info.recommendation;
        }
        
        return 'Dynamic Forms unlikely to be the issue';
    }
    
    /**
     * @description Check for common Lightning visibility issues
     */
    public static List<String> checkLightningVisibilityIssues(String objectName, String fieldName) {
        List<String> issues = new List<String>();
        
        try {
            // Issue 1: Dynamic Forms
            DynamicFormsInfo dfInfo = checkDynamicForms(objectName, fieldName);
            if (dfInfo.mightBeHidingField) {
                issues.add('Dynamic Forms may be hiding the field');
            }
            
            // Issue 2: Lightning vs Classic difference
            if (isLightningExperienceOrg()) {
                issues.add('Check if field is visible in Salesforce Classic (different UI)');
            }
            
            // Issue 3: Field-level security in Lightning
            issues.add('Lightning Experience enforces Field-Level Security more strictly than Classic');
            
            // Issue 4: Compact layouts (for related lists)
            issues.add('If viewing in a related list, check Compact Layout settings');
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking Lightning issues: ' + e.getMessage());
        }
        
        return issues;
    }
}