/**
 * @description Service for diagnosing sharing-related access issues
 * Checks Org-Wide Defaults, Sharing Rules, Manual Shares, Role Hierarchy, Teams
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 * @version 1.0 - Production Grade
 */
public with sharing class SharingDiagnosticService {
    
    // Cache for sharing settings to avoid repeated queries
    private static Map<String, OrgWideDefault> owdCache = new Map<String, OrgWideDefault>();
    
    /**
     * @description Wrapper for sharing analysis results
     */
    public class SharingAnalysis {
        @AuraEnabled public Id recordId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String objectName;
        @AuraEnabled public Boolean hasAccess;
        @AuraEnabled public List<String> accessSources; // How user got access
        @AuraEnabled public String owdSetting;
        @AuraEnabled public Boolean isOwner;
        @AuraEnabled public Boolean hasRoleAccess;
        @AuraEnabled public Boolean hasTeamAccess;
        @AuraEnabled public List<SharingRuleMatch> sharingRules;
        @AuraEnabled public List<ManualShare> manualShares;
        @AuraEnabled public String recommendation;
        @AuraEnabled public String errorMessage;
        
        public SharingAnalysis() {
            this.accessSources = new List<String>();
            this.sharingRules = new List<SharingRuleMatch>();
            this.manualShares = new List<ManualShare>();
            this.hasAccess = false;
        }
    }
    
    public class SharingRuleMatch {
        @AuraEnabled public String ruleName;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public String criteria;
    }
    
    public class ManualShare {
        @AuraEnabled public String sharedWith;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public String rowCause;
    }
    
    public class OrgWideDefault {
        @AuraEnabled public String objectName;
        @AuraEnabled public String internalSharingModel;
        @AuraEnabled public String externalSharingModel;
    }
    
    /**
     * @description Comprehensive sharing analysis for a record
     * @param recordId Record to check
     * @param userId User to check access for
     * @return SharingAnalysis with detailed findings
     */
    public static SharingAnalysis analyzeRecordSharing(Id recordId, Id userId) {
        SharingAnalysis analysis = new SharingAnalysis();
        analysis.recordId = recordId;
        analysis.userId = userId;
        
        try {
            // Get object name from record ID
            String objectName = recordId.getSObjectType().getDescribe().getName();
            analysis.objectName = objectName;
            
            // Step 1: Check if user actually has access (UserRecordAccess)
            analysis.hasAccess = checkUserRecordAccess(recordId, userId);
            
            // Step 2: Get OWD setting
            analysis.owdSetting = getOrgWideDefault(objectName);
            
            // Step 3: Check if user is owner
            analysis.isOwner = checkOwnership(recordId, userId);
            if (analysis.isOwner) {
                analysis.accessSources.add('Record Owner');
            }
            
            // Step 4: Check role hierarchy access
            analysis.hasRoleAccess = checkRoleHierarchyAccess(recordId, userId);
            if (analysis.hasRoleAccess) {
                analysis.accessSources.add('Role Hierarchy');
            }
            
            // Step 5: Check sharing rules
            analysis.sharingRules = getSharingRules(objectName, userId, recordId);
            if (!analysis.sharingRules.isEmpty()) {
                analysis.accessSources.add('Sharing Rules (' + analysis.sharingRules.size() + ')');
            }
            
            // Step 6: Check manual shares
            analysis.manualShares = getManualShares(recordId, userId);
            if (!analysis.manualShares.isEmpty()) {
                analysis.accessSources.add('Manual Sharing');
            }
            
            // Step 7: Check team access (Account/Opportunity Teams)
            analysis.hasTeamAccess = checkTeamAccess(recordId, userId);
            if (analysis.hasTeamAccess) {
                analysis.accessSources.add('Team Access');
            }
            
            // Step 8: Generate recommendation
            analysis.recommendation = generateRecommendation(analysis);
            
            System.debug('Sharing Analysis: ' + analysis.accessSources.size() + ' access sources found');
            
        } catch (Exception e) {
            analysis.errorMessage = 'Error analyzing sharing: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, analysis.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return analysis;
    }
    
    /**
     * @description Check if user has access via UserRecordAccess
     */
    private static Boolean checkUserRecordAccess(Id recordId, Id userId) {
        try {
            List<UserRecordAccess> access = [
                SELECT RecordId,HasReadAccess
                FROM UserRecordAccess
                WHERE UserId = :userId AND RecordId = :recordId
                LIMIT 1
            ];
            
            return !access.isEmpty() && access[0].HasReadAccess;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error checking UserRecordAccess: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get Org-Wide Default for object
     */
    public static String getOrgWideDefault(String objectName) {
        try {
            // Check cache first
            if (owdCache.containsKey(objectName)) {
                return owdCache.get(objectName).internalSharingModel;
            }
            
            // Query OWD settings
            List<EntityDefinition> entities = [
                SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel
                FROM EntityDefinition
                WHERE QualifiedApiName = :objectName
                LIMIT 1
            ];
            
            if (!entities.isEmpty()) {
                OrgWideDefault owd = new OrgWideDefault();
                owd.objectName = objectName;
                owd.internalSharingModel = entities[0].InternalSharingModel;
                owd.externalSharingModel = entities[0].ExternalSharingModel;
                owdCache.put(objectName, owd);
                
                System.debug('OWD for ' + objectName + ': ' + owd.internalSharingModel);
                return owd.internalSharingModel;
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting OWD: ' + e.getMessage());
        }
        
        return 'Unknown';
    }
    
    /**
     * @description Check if user owns the record
     */
    private static Boolean checkOwnership(Id recordId, Id userId) {
        try {
            String objectName = recordId.getSObjectType().getDescribe().getName();
            
            // Dynamic SOQL to check OwnerId
            String query = 'SELECT OwnerId FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.query(query);
            
            if (!records.isEmpty()) {
                Id ownerId = (Id) records[0].get('OwnerId');
                
                // Check if user is owner OR part of owner's queue
                if (ownerId == userId) {
                    return true;
                }
                
                // Check if owner is a queue and user is a member
                if (String.valueOf(ownerId).startsWith('00G')) {
                    List<GroupMember> members = [
                        SELECT UserOrGroupId
                        FROM GroupMember
                        WHERE GroupId = :ownerId AND UserOrGroupId = :userId
                        LIMIT 1
                    ];
                    return !members.isEmpty();
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking ownership: ' + e.getMessage());
        }
        
        return false;
    }
    
    /**
     * @description Check if user has access via role hierarchy
     */
    private static Boolean checkRoleHierarchyAccess(Id recordId, Id userId) {
        try {
            String objectName = recordId.getSObjectType().getDescribe().getName();
            
            // Get record owner's role
            String query = 'SELECT OwnerId FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
            List<SObject> records = Database.query(query);
            
            if (records.isEmpty()) {
                return false;
            }
            
            Id ownerId = (Id) records[0].get('OwnerId');
            
            // Get owner's role
            List<User> ownerUsers = [
                SELECT UserRoleId 
                FROM User 
                WHERE Id = :ownerId 
                LIMIT 1
            ];
            
            if (ownerUsers.isEmpty() || ownerUsers[0].UserRoleId == null) {
                return false;
            }
            
            Id ownerRoleId = ownerUsers[0].UserRoleId;
            
            // Get current user's role
            List<User> currentUsers = [
                SELECT UserRoleId 
                FROM User 
                WHERE Id = :userId 
                LIMIT 1
            ];
            
            if (currentUsers.isEmpty() || currentUsers[0].UserRoleId == null) {
                return false;
            }
            
            Id userRoleId = currentUsers[0].UserRoleId;
            
            // Check if user's role is above owner's role in hierarchy
            // This is a simplified check - full implementation would traverse role hierarchy
            Set<Id> parentRoles = getParentRoles(ownerRoleId);
            return parentRoles.contains(userRoleId);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking role hierarchy: ' + e.getMessage());
        }
        
        return false;
    }
    
    /**
     * @description Get parent roles in hierarchy
     */
    private static Set<Id> getParentRoles(Id roleId) {
        Set<Id> parentRoles = new Set<Id>();
        
        try {
            // Query up to 5 levels of role hierarchy
            List<UserRole> roles = [
                SELECT Id, ParentRoleId
                FROM UserRole
                WHERE Id = :roleId
                LIMIT 1
            ];
            
            while (!roles.isEmpty() && roles[0].ParentRoleId != null) {
                Id parentId = roles[0].ParentRoleId;
                parentRoles.add(parentId);
                
                // Query next level
                roles = [
                    SELECT Id, ParentRoleId
                    FROM UserRole
                    WHERE Id = :parentId
                    LIMIT 1
                ];
                
                // Prevent infinite loop
                if (parentRoles.size() > 10) {
                    break;
                }
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting parent roles: ' + e.getMessage());
        }
        
        return parentRoles;
    }
    
    /**
     * @description Get sharing rules that grant access
     * Note: This is simplified - full implementation requires Tooling API to query metadata
     */
    private static List<SharingRuleMatch> getSharingRules(String objectName, Id userId, Id recordId) {
        List<SharingRuleMatch> rules = new List<SharingRuleMatch>();
        
        try {
            // Query the share table dynamically
            String shareTable = objectName.replace('__c', '__Share');
            if (objectName.endsWith('__c')) {
                shareTable = objectName.replace('__c', '__Share');
            } else {
                // Standard objects
                shareTable = objectName + 'Share';
            }
            
            // Check if share table exists
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            if (!globalDescribe.containsKey(shareTable.toLowerCase())) {
                System.debug('Share table does not exist: ' + shareTable);
                return rules;
            }
            
            // Query share records
            String query = 'SELECT RowCause, AccessLevel, UserOrGroupId ' +
                          'FROM ' + shareTable + ' ' +
                          'WHERE ParentId = :recordId ' +
                          'AND (UserOrGroupId = :userId OR UserOrGroupId IN ' +
                          '(SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :userId))';
            
            List<SObject> shares = Database.query(query);
            
            for (SObject share : shares) {
                String rowCause = (String) share.get('RowCause');
                
                // Skip owner and manual shares (handled elsewhere)
                if (rowCause == 'Owner' || rowCause == 'Manual') {
                    continue;
                }
                
                SharingRuleMatch rule = new SharingRuleMatch();
                rule.ruleName = rowCause;
                rule.accessLevel = (String) share.get('AccessLevel');
                rule.criteria = 'Sharing Rule';
                rules.add(rule);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting sharing rules: ' + e.getMessage());
        }
        
        return rules;
    }
    
    /**
     * @description Get manual shares
     */
    private static List<ManualShare> getManualShares(Id recordId, Id userId) {
        List<ManualShare> shares = new List<ManualShare>();
        
        try {
            String objectName = recordId.getSObjectType().getDescribe().getName();
            String shareTable = objectName.endsWith('__c') ? 
                objectName.replace('__c', '__Share') : objectName + 'Share';
            
            // Check if share table exists
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            if (!globalDescribe.containsKey(shareTable.toLowerCase())) {
                return shares;
            }
            
            // Query manual shares
            String query = 'SELECT RowCause, AccessLevel, UserOrGroupId ' +
                          'FROM ' + shareTable + ' ' +
                          'WHERE ParentId = :recordId ' +
                          'AND RowCause = \'Manual\' ' +
                          'AND (UserOrGroupId = :userId OR UserOrGroupId IN ' +
                          '(SELECT GroupId FROM GroupMember WHERE UserOrGroupId = :userId))';
            
            List<SObject> shareRecords = Database.query(query);
            
            for (SObject shareRecord : shareRecords) {
                ManualShare share = new ManualShare();
                share.rowCause = 'Manual';
                share.accessLevel = (String) shareRecord.get('AccessLevel');
                
                Id sharedWithId = (Id) shareRecord.get('UserOrGroupId');
                if (sharedWithId == userId) {
                    share.sharedWith = 'You (Direct)';
                } else {
                    share.sharedWith = 'Public Group';
                }
                
                shares.add(share);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error getting manual shares: ' + e.getMessage());
        }
        
        return shares;
    }
    
    /**
     * @description Check team access (Account/Opportunity Teams)
     */
    private static Boolean checkTeamAccess(Id recordId, Id userId) {
        try {
            String objectName = recordId.getSObjectType().getDescribe().getName();
            // Account Team
        if (objectName == 'Account') {
            if (Schema.getGlobalDescribe().containsKey('AccountTeamMember')) {
                List<SObject> rows = Database.query(
                    'SELECT Id FROM AccountTeamMember WHERE AccountId = :recordId AND UserId = :userId LIMIT 1'
                );
                return !rows.isEmpty();
            }
        }

        // Opportunity Team
        if (objectName == 'Opportunity') {
            if (Schema.getGlobalDescribe().containsKey('OpportunityTeamMember')) {
                List<SObject> rows = Database.query(
                    'SELECT Id FROM OpportunityTeamMember WHERE OpportunityId = :recordId AND UserId = :userId LIMIT 1'
                );
                return !rows.isEmpty();
            }
        }
     
            
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error checking team access: ' + e.getMessage());
        }
        
        return false;
    }
    
    /**
     * @description Generate recommendation based on analysis
     */
    private static String generateRecommendation(SharingAnalysis analysis) {
        if (analysis.hasAccess) {
            if (!analysis.accessSources.isEmpty()) {
                return 'User has access via: ' + String.join(analysis.accessSources, ', ');
            } else {
                return 'User has access (source unknown - may be profile permissions)';
            }
        } else {
            // User does not have access - suggest solutions
            if (analysis.owdSetting == 'Private') {
                return 'OWD is Private. Consider: (1) Making user the owner, (2) Adding sharing rule, ' +
                       '(3) Manual sharing, (4) Adding to Account/Opportunity Team';
            } else if (analysis.owdSetting == 'Public Read Only') {
                return 'OWD is Public Read Only - user should have read access. Check object permissions.';
            } else {
                return 'User does not have access. Check: (1) Record ownership, (2) Sharing rules, ' +
                       '(3) Role hierarchy, (4) Manual shares';
            }
        }
    }
    
    /**
     * @description Clear cache
     */
    @TestVisible
    private static void clearCache() {
        owdCache.clear();
    }
}