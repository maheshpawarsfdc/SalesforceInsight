/**
 * @description Service class for diagnosing Salesforce permissions and access issues
 * Checks permissions for ANY user by querying ObjectPermissions and FieldPermissions
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class SalesforceDiagnosticService {
    
    // Cache for permission set IDs to avoid repeated queries
    private static Map<Id, Set<Id>> userPermissionSetsCache = new Map<Id, Set<Id>>();
    
    // Inner classes for structured responses
    public class ObjectPermissionResult {
        public String objectName;
        public Id userId;
        public Boolean isAccessible;
        public Boolean isCreateable;
        public Boolean isUpdateable;
        public Boolean isDeletable;
        public String profileName;
        public List<String> permissionSets;
        public List<String> permissionDetails;
        public String errorMessage;
        
        public ObjectPermissionResult() {
            this.permissionDetails = new List<String>();
            this.permissionSets = new List<String>();
        }
    }
    
    public class FieldPermissionResult {
        public String objectName;
        public String fieldName;
        public Id userId;
        public Boolean isAccessible;
        public Boolean isCreateable;
        public Boolean isUpdateable;
        public List<String> permissionDetails;
        public String errorMessage;
        
        public FieldPermissionResult() {
            this.permissionDetails = new List<String>();
        }
    }
    
    public class RecordAccess {
        public Id recordId;
        public Id userId;
        public Boolean hasReadAccess;
        public Boolean hasEditAccess;
        public Boolean hasDeleteAccess;
        public Boolean hasTransferAccess;
        public String maxAccessLevel;
        public String errorMessage;
    }
    
    public class ProfileInfo {
        public Id userId;
        public Id profileId;
        public String profileName;
        public String userRole;
        public Boolean isActive;
        public String errorMessage;
    }
    
    public class PermissionSetInfo {
        public Id permissionSetId;
        public String permissionSetName;
        public String permissionSetLabel;
        public Boolean isActive;
    }
    
    /**
     * @description Check object-level permissions for a specific user
     * Queries ObjectPermissions to check actual user permissions
     * @param objectName API name of the object (e.g., 'Account', 'Custom_Object__c')
     * @param userId User ID to check permissions for
     * @return ObjectPermissionResult wrapper with permission details
     */
    public static ObjectPermissionResult checkObjectPermissions(String objectName, Id userId) {
        ObjectPermissionResult result = new ObjectPermissionResult();
        result.objectName = objectName;
        result.userId = userId;
        
        try {
            // Validate inputs
            if (String.isBlank(objectName)) {
                result.errorMessage = 'Object name cannot be blank';
                return result;
            }
            
            if (userId == null) {
                result.errorMessage = 'User ID cannot be null';
                return result;
            }
            
            // Verify object exists
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                result.errorMessage = 'Object "' + objectName + '" does not exist';
                return result;
            }
            
            // Get user profile and permission sets
            ProfileInfo profile = getUserProfile(userId);
            result.profileName = profile.profileName;
            
            if (profile.errorMessage != null) {
                result.errorMessage = profile.errorMessage;
                return result;
            }
            
            List<PermissionSetInfo> permSets = getUserPermissionSets(userId);
            for (PermissionSetInfo ps : permSets) {
                result.permissionSets.add(ps.permissionSetLabel);
            }
            
            // Get all permission set IDs for this user (including profile-based)
            Set<Id> permissionSetIds = getUserPermissionSetIds(userId);
            
            if (permissionSetIds.isEmpty()) {
                result.errorMessage = 'No permission sets found for user';
                return result;
            }
            
            // Query ObjectPermissions for this object and user's permission sets
            List<ObjectPermissions> objPermsList = [
                SELECT ParentId, Parent.Label, SobjectType,
                       PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete,
                       PermissionsViewAllRecords, PermissionsModifyAllRecords
                FROM ObjectPermissions
                WHERE ParentId IN :permissionSetIds
                AND SobjectType = :objectName
            ];
            
            // Initialize to false
            result.isAccessible = false;
            result.isCreateable = false;
            result.isUpdateable = false;
            result.isDeletable = false;
            
            // Aggregate permissions from all permission sets (OR logic)
            for (ObjectPermissions objPerm : objPermsList) {
                if (objPerm.PermissionsRead) {
                    result.isAccessible = true;
                    result.permissionDetails.add('Read granted by: ' + objPerm.Parent.Label);
                }
                if (objPerm.PermissionsCreate) {
                    result.isCreateable = true;
                    result.permissionDetails.add('Create granted by: ' + objPerm.Parent.Label);
                }
                if (objPerm.PermissionsEdit) {
                    result.isUpdateable = true;
                    result.permissionDetails.add('Edit granted by: ' + objPerm.Parent.Label);
                }
                if (objPerm.PermissionsDelete) {
                    result.isDeletable = true;
                    result.permissionDetails.add('Delete granted by: ' + objPerm.Parent.Label);
                }
            }
            
            System.debug('Object Permissions Check: ' + objectName + ' for user ' + userId);
            System.debug('Read: ' + result.isAccessible + ', Create: ' + result.isCreateable + 
                        ', Edit: ' + result.isUpdateable + ', Delete: ' + result.isDeletable);
            
        } catch (Exception e) {
            result.errorMessage = 'Error checking object permissions: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, result.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Check field-level security for a specific field and user
     * Queries FieldPermissions to check actual user permissions
     * @param objectName API name of the object
     * @param fieldName API name of the field
     * @param userId User ID to check permissions for
     * @return FieldPermissionResult wrapper with field security details
     */
    public static FieldPermissionResult checkFieldLevelSecurity(String objectName, String fieldName, Id userId) {
        FieldPermissionResult result = new FieldPermissionResult();
        result.objectName = objectName;
        result.fieldName = fieldName;
        result.userId = userId;
        
        try {
            // Validate inputs
            if (String.isBlank(objectName) || String.isBlank(fieldName)) {
                result.errorMessage = 'Object name and field name cannot be blank';
                return result;
            }
            
            if (userId == null) {
                result.errorMessage = 'User ID cannot be null';
                return result;
            }
            
            // Verify object and field exist
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
            if (objectType == null) {
                result.errorMessage = 'Object "' + objectName + '" does not exist';
                return result;
            }
            
            Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
            Schema.SObjectField field = fieldMap.get(fieldName.toLowerCase());
            
            if (field == null) {
                result.errorMessage = 'Field "' + fieldName + '" does not exist on object "' + objectName + '"';
                return result;
            }
            
            // Get all permission set IDs for this user
            Set<Id> permissionSetIds = getUserPermissionSetIds(userId);
            
            if (permissionSetIds.isEmpty()) {
                result.errorMessage = 'No permission sets found for user';
                return result;
            }
            
            // Query FieldPermissions for this field and user's permission sets
            List<FieldPermissions> fieldPermsList = [
                SELECT ParentId, Parent.Label, SobjectType, Field,
                       PermissionsRead, PermissionsEdit
                FROM FieldPermissions
                WHERE ParentId IN :permissionSetIds
                AND SobjectType = :objectName
                AND Field = :objectName + '.' + fieldName
            ];
            
            // Initialize to false
            result.isAccessible = false;
            result.isCreateable = false;
            result.isUpdateable = false;
            
            // Aggregate permissions from all permission sets (OR logic)
            for (FieldPermissions fieldPerm : fieldPermsList) {
                if (fieldPerm.PermissionsRead) {
                    result.isAccessible = true;
                    result.permissionDetails.add('Read granted by: ' + fieldPerm.Parent.Label);
                }
                if (fieldPerm.PermissionsEdit) {
                    result.isUpdateable = true;
                    result.isCreateable = true; // If can edit, can also populate on create
                    result.permissionDetails.add('Edit granted by: ' + fieldPerm.Parent.Label);
                }
            }
            
            System.debug('Field Security Check: ' + objectName + '.' + fieldName + ' for user ' + userId);
            System.debug('Accessible: ' + result.isAccessible + ', Updateable: ' + result.isUpdateable);
            
        } catch (Exception e) {
            result.errorMessage = 'Error checking field-level security: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, result.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Check record-level access for a specific record
     * Uses UserRecordAccess to check sharing and record-level permissions
     * @param recordId ID of the record to check
     * @param userId User ID to check access for
     * @return RecordAccess wrapper with access details
     */
    public static RecordAccess checkRecordAccess(Id recordId, Id userId) {
        RecordAccess result = new RecordAccess();
        result.recordId = recordId;
        result.userId = userId;
        
        try {
            // Validate inputs
            if (recordId == null) {
                result.errorMessage = 'Record ID cannot be null';
                return result;
            }
            
            if (userId == null) {
                result.errorMessage = 'User ID cannot be null';
                return result;
            }
            
            // Query UserRecordAccess
            List<UserRecordAccess> accessList = [
                SELECT RecordId, HasReadAccess, HasEditAccess, 
                       HasDeleteAccess, HasTransferAccess, MaxAccessLevel
                FROM UserRecordAccess
                WHERE UserId = :userId 
                AND RecordId = :recordId
                LIMIT 1
            ];
            
            if (accessList.isEmpty()) {
                result.errorMessage = 'Unable to determine record access. Record may not exist or user has no access.';
                result.hasReadAccess = false;
                result.hasEditAccess = false;
                result.hasDeleteAccess = false;
                result.hasTransferAccess = false;
                return result;
            }
            
            UserRecordAccess access = accessList[0];
            result.hasReadAccess = access.HasReadAccess;
            result.hasEditAccess = access.HasEditAccess;
            result.hasDeleteAccess = access.HasDeleteAccess;
            result.hasTransferAccess = access.HasTransferAccess;
            result.maxAccessLevel = access.MaxAccessLevel;
            
            System.debug('Record Access Check: Record ' + recordId + ' for user ' + userId);
            System.debug('Read: ' + result.hasReadAccess + ', Edit: ' + result.hasEditAccess + 
                        ', Delete: ' + result.hasDeleteAccess);
            
        } catch (Exception e) {
            result.errorMessage = 'Error checking record access: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, result.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Get profile information for a user
     * @param userId User ID to retrieve profile for
     * @return ProfileInfo wrapper with user profile details
     */
    public static ProfileInfo getUserProfile(Id userId) {
        ProfileInfo result = new ProfileInfo();
        result.userId = userId;
        
        try {
            // Validate input
            if (userId == null) {
                result.errorMessage = 'User ID cannot be null';
                return result;
            }
            
            // Query user and profile
            List<User> users = [
                SELECT Id, ProfileId, Profile.Name, UserRole.Name, IsActive
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];
            
            if (users.isEmpty()) {
                result.errorMessage = 'User not found with ID: ' + userId;
                return result;
            }
            
            User u = users[0];
            result.profileId = u.ProfileId;
            result.profileName = u.Profile.Name;
            result.userRole = u.UserRole != null ? u.UserRole.Name : 'No Role';
            result.isActive = u.IsActive;
            
            System.debug('User Profile: ' + result.profileName + ' (Active: ' + result.isActive + ')');
            
        } catch (Exception e) {
            result.errorMessage = 'Error retrieving user profile: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, result.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Get all permission sets assigned to a user (excluding profile-based)
     * @param userId User ID to retrieve permission sets for
     * @return List of PermissionSetInfo wrappers
     */
    public static List<PermissionSetInfo> getUserPermissionSets(Id userId) {
        List<PermissionSetInfo> result = new List<PermissionSetInfo>();
        
        try {
            // Validate input
            if (userId == null) {
                System.debug(LoggingLevel.ERROR, 'User ID cannot be null');
                return result;
            }
            
            // Query permission set assignments (excluding profile-based permission sets)
            List<PermissionSetAssignment> assignments = [
                SELECT PermissionSetId, PermissionSet.Name, PermissionSet.Label, 
                       PermissionSet.IsOwnedByProfile
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId
                AND PermissionSet.IsOwnedByProfile = false
            ];
            
            for (PermissionSetAssignment psa : assignments) {
                PermissionSetInfo info = new PermissionSetInfo();
                info.permissionSetId = psa.PermissionSetId;
                info.permissionSetName = psa.PermissionSet.Name;
                info.permissionSetLabel = psa.PermissionSet.Label;
                info.isActive = true;
                result.add(info);
            }
            
            System.debug('Found ' + result.size() + ' permission sets for user ' + userId);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving permission sets: ' + e.getMessage());
        }
        
        return result;
    }
    
    /**
     * @description Get all permission set IDs for a user (including profile-based)
     * @param userId User ID
     * @return Set of permission set IDs
     */
    private static Set<Id> getUserPermissionSetIds(Id userId) {
        // Check cache first
        if (userPermissionSetsCache.containsKey(userId)) {
            return userPermissionSetsCache.get(userId);
        }
        
        Set<Id> permissionSetIds = new Set<Id>();
        
        try {
            // Query all permission set assignments for this user (including profile)
            List<PermissionSetAssignment> psaList = [
                SELECT PermissionSetId
                FROM PermissionSetAssignment
                WHERE AssigneeId = :userId
            ];
            
            for (PermissionSetAssignment psa : psaList) {
                permissionSetIds.add(psa.PermissionSetId);
            }
            
            // Cache the result
            userPermissionSetsCache.put(userId, permissionSetIds);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting permission set IDs: ' + e.getMessage());
        }
        
        return permissionSetIds;
    }
    
    /**
     * @description Bulk check object permissions for multiple users
     * @param objectName API name of the object
     * @param userIds Set of user IDs to check
     * @return Map of userId to ObjectPermissionResult
     */
    public static Map<Id, ObjectPermissionResult> bulkCheckObjectPermissions(String objectName, Set<Id> userIds) {
        Map<Id, ObjectPermissionResult> results = new Map<Id, ObjectPermissionResult>();
        
        for (Id userId : userIds) {
            results.put(userId, checkObjectPermissions(objectName, userId));
        }
        
        return results;
    }
    
    /**
     * @description Bulk check field permissions for multiple fields
     * @param objectName API name of the object
     * @param fieldNames Set of field API names
     * @param userId User ID to check permissions for
     * @return Map of fieldName to FieldPermissionResult
     */
    public static Map<String, FieldPermissionResult> bulkCheckFieldPermissions(
        String objectName, 
        Set<String> fieldNames, 
        Id userId
    ) {
        Map<String, FieldPermissionResult> results = new Map<String, FieldPermissionResult>();
        
        for (String fieldName : fieldNames) {
            results.put(fieldName, checkFieldLevelSecurity(objectName, fieldName, userId));
        }
        
        return results;
    }
    
    /**
     * @description Clear permission set cache (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        userPermissionSetsCache.clear();
    }
}