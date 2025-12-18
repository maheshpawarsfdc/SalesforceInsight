/**
 * @description Controller for user search functionality in diagnostic tool
 * @author System
 * @date 2025
 */
public with sharing class UserSearchController {
    
    // Constants
    private static final Integer MAX_RESULTS = 50;
    private static final String SOSL_WILDCARD = '*';
    
    /**
     * @description Wrapper class for user search results
     */
    public class UserResult {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public DateTime lastLoginDate;
        @AuraEnabled public String smallPhotoUrl;
        
        public UserResult(User u) {
            this.id = u.Id;
            this.name = u.Name;
            this.username = u.Username;
            this.profileName = u.Profile.Name;
            this.isActive = u.IsActive;
            this.lastLoginDate = u.LastLoginDate;
            this.smallPhotoUrl = u.SmallPhotoUrl;
        }
    }
    
    /**
     * @description Searches for users matching the search term
     * @param searchTerm String to search for in user name or username
     * @return List<UserResult> List of matching users (max 50)
     */
    @AuraEnabled(cacheable=true)
    public static List<UserResult> searchUsers(String searchTerm) {
        List<UserResult> results = new List<UserResult>();
        
        // Validate input
        if (String.isBlank(searchTerm)) {
            return results;
        }
        
        // Sanitize search term
        String sanitizedTerm = sanitizeSearchTerm(searchTerm);
        
        if (String.isBlank(sanitizedTerm)) {
            return results;
        }
        
        try {
            // Build SOSL query
            String soslQuery = buildSOSLQuery(sanitizedTerm);
            
            // Execute search
            List<List<SObject>> searchResults = Search.query(soslQuery);
            
            if (!searchResults.isEmpty() && !searchResults[0].isEmpty()) {
                List<User> users = (List<User>) searchResults[0];
                
                // Convert to UserResult wrapper
                for (User u : users) {
                    results.add(new UserResult(u));
                }
                
                if (ConfigService.isDebugLoggingEnabled()) {
                    System.debug(LoggingLevel.DEBUG, '[UserSearchController] Found ' + results.size() + ' users for search term: ' + searchTerm);
                }
            } else {
                if (ConfigService.isDebugLoggingEnabled()) {
                    System.debug(LoggingLevel.DEBUG, '[UserSearchController] No users found for search term: ' + searchTerm);
                }
            }
            
        } catch (Exception e) {
            if (ConfigService.isDebugLoggingEnabled()) {
                System.debug(LoggingLevel.DEBUG, '[UserSearchController] Error searching users: ' + e.getMessage());
            }
            throw new AuraHandledException('Error searching users: ' + e.getMessage());
        }
        
        return results;
    }
    
    /**
     * @description Sanitizes search term to prevent SOSL injection
     * @param searchTerm Raw search term from user
     * @return String Sanitized search term
     */
    private static String sanitizeSearchTerm(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return '';
        }
        
        // Remove leading/trailing whitespace
        String sanitized = searchTerm.trim();
        
        // Escape special SOSL characters
        sanitized = String.escapeSingleQuotes(sanitized);
        
        // Remove SOSL reserved characters that could cause issues
        sanitized = sanitized.replaceAll('[\\?\\&\\|\\!\\{\\}\\[\\]\\^\\~\\:\\(\\)\\"]', '');
        
        // Limit length to prevent abuse
        if (sanitized.length() > 100) {
            sanitized = sanitized.substring(0, 100);
        }
        
        return sanitized;
    }
    
    /**
     * @description Builds SOSL query for user search
     * @param searchTerm Sanitized search term
     * @return String SOSL query string
     */
    private static String buildSOSLQuery(String searchTerm) {
        // Build SOSL query to search Name and Username fields
        String query = 'FIND {' + searchTerm + SOSL_WILDCARD + '} IN ALL FIELDS RETURNING User(';
        query += 'Id, Name, Username, Profile.Name, IsActive, LastLoginDate, SmallPhotoUrl ';
        query += 'WHERE IsActive = true ';
        query += 'ORDER BY Name ASC ';
        query += 'LIMIT ' + MAX_RESULTS + ')';
        
        return query;
    }
    
    /**
     * @description Gets detailed information for a specific user
     * @param userId User ID to retrieve
     * @return UserResult Detailed user information
     */
    @AuraEnabled(cacheable=true)
    public static UserResult getUserDetails(String userId) {
        if (String.isBlank(userId)) {
            throw new AuraHandledException('User ID cannot be empty');
        }
        
        try {
            User u = [
                SELECT Id, Name, Username, Profile.Name, IsActive, 
                       LastLoginDate, SmallPhotoUrl, Email, UserRole.Name
                FROM User 
                WHERE Id = :userId 
                LIMIT 1
            ];
            
            return new UserResult(u);
            
        } catch (QueryException e) {
            throw new AuraHandledException('User not found: ' + userId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving user details: ' + e.getMessage());
        }
    }
    
}