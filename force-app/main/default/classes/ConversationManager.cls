/**
 * @description Manages conversation history and context for AI interactions
 * Handles token limits, message summarization, and session persistence
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class ConversationManager {
    
    // Token budget configuration
    private static final Integer MAX_CONTEXT_TOKENS = 3000;
    private static final Integer ESTIMATED_TOKENS_PER_CHAR = 4; // Rough estimate: 1 token ≈ 4 characters
    private static final Integer MAX_RECENT_MESSAGES = 5;
    private static final Integer MAX_CONTEXT_LENGTH = MAX_CONTEXT_TOKENS * ESTIMATED_TOKENS_PER_CHAR; // ~12000 chars
    
    /**
     * @description Wrapper for conversation context
     */
    public class ConversationContext {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String formattedContext;
        @AuraEnabled public ConversationSummary summary;
        @AuraEnabled public List<Message> recentMessages;
        @AuraEnabled public SessionState currentState;
        @AuraEnabled public Integer estimatedTokens;
        
        public ConversationContext() {
            this.recentMessages = new List<Message>();
            this.summary = new ConversationSummary();
            this.currentState = new SessionState();
        }
    }
    

    
    public class ConversationSummary {
        @AuraEnabled public String topic;
        @AuraEnabled public String issueType;
        @AuraEnabled public List<String> objectsDiscussed;
        @AuraEnabled public List<String> fieldsDiscussed;
        @AuraEnabled public List<String> recordsDiscussed;
        @AuraEnabled public Integer messageCount;
        @AuraEnabled public DateTime startTime;
        @AuraEnabled public String resolutionStatus;
        
        public ConversationSummary() {
            this.objectsDiscussed = new List<String>();
            this.fieldsDiscussed = new List<String>();
            this.recordsDiscussed = new List<String>();
            this.messageCount = 0;
        }
    }
    
    /**
     * @description Current session state
     */
    public class SessionState {
        @AuraEnabled public List<String> diagnosticsRun;
        @AuraEnabled public List<String> entitiesDiscussed;
        @AuraEnabled public DateTime lastActivity;
        @AuraEnabled public Boolean issueResolved;
        
        public SessionState() {
            this.diagnosticsRun = new List<String>();
            this.entitiesDiscussed = new List<String>();
            this.lastActivity = DateTime.now();
            this.issueResolved = false;
        }
    }
    
    /**
     * @description Single message in conversation
     */
    public class Message {
        @AuraEnabled public String role; // 'user' or 'assistant'
        @AuraEnabled public String content;
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public Integer sequenceNumber;
        
        public Message(String role, String content, Integer sequenceNumber) {
            this.role = role;
            this.content = content;
            this.timestamp = DateTime.now();
            this.sequenceNumber = sequenceNumber;
        }
    }
    
    /**
     * @description Add a message to conversation history
     * @param sessionId Diagnostic session ID
     * @param role Message role (user or assistant)
     * @param content Message content
     * @return Updated conversation context
     */
    public static ConversationContext addMessage(String sessionId, String role, String content) {
        try {
            // Get or create session
            Diagnostic_Session__c session = getOrCreateSession(sessionId);
            
            // Parse existing conversation
            List<Message> messages = parseConversationHistory(session.Conversation_History__c);
            
            // Add new message
            Message newMessage = new Message(role, content, messages.size() + 1);
            messages.add(newMessage);
            
            // Build context
            ConversationContext context = buildContext(session, messages);
            
            // Update session record
            updateSessionHistory(session.Id, messages, context);
            
            return context;
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error adding message: ' + e.getMessage());
            throw new ConversationException('Failed to add message: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get current conversation context
     * @param sessionId Diagnostic session ID
     * @return Current conversation context
     */
    public static ConversationContext getContext(String sessionId) {
        try {
            Diagnostic_Session__c session = getSession(sessionId);
            List<Message> messages = parseConversationHistory(session.Conversation_History__c);
            return buildContext(session, messages);
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error getting context: ' + e.getMessage());
            throw new ConversationException('Failed to get context: ' + e.getMessage());
        }
    }
    
    /**
     * @description Build formatted context for AI
     * @param session Diagnostic session record
     * @param messages List of all messages
     * @return Formatted conversation context
     */
    private static ConversationContext buildContext(
        Diagnostic_Session__c session, 
        List<Message> messages
    ) {
        ConversationContext context = new ConversationContext();
        context.sessionId = session.Id;
        
        // Build summary
        context.summary = buildSummary(session, messages);
        
        // Get recent messages (last 3-5)
        context.recentMessages = getRecentMessages(messages);
        
        // Build current state
        context.currentState = buildSessionState(session, messages);
        
        // Format everything for AI
        context.formattedContext = formatContextForAI(context);
        
        // Estimate tokens
        context.estimatedTokens = estimateTokens(context.formattedContext);
        
        // If over token limit, prune and rebuild
        if (context.estimatedTokens > MAX_CONTEXT_TOKENS) {
            context = pruneContext(context, session, messages);
        }
        
        return context;
    }
    
    /**
     * @description Build conversation summary
     * @param session Diagnostic session record
     * @param messages List of messages
     * @return Conversation summary
     */
    private static ConversationSummary buildSummary(
        Diagnostic_Session__c session,
        List<Message> messages
    ) {
        ConversationSummary summary = new ConversationSummary();
        
        summary.messageCount = messages.size();
        summary.startTime = session.CreatedDate;
        summary.issueType = session.Issue_Type__c;
        summary.resolutionStatus = session.Resolution_Status__c;
        
        // Extract entities from all messages
        Set<String> allObjects = new Set<String>();
        Set<String> allFields = new Set<String>();
        Set<String> allRecords = new Set<String>();
        
        for (Message msg : messages) {
            if (msg.role == 'user') {
                MessageAnalyzer.MessageAnalysis analysis = 
                    MessageAnalyzer.analyzeMessage(msg.content);
                
                allObjects.addAll(analysis.objectsInvolved);
                allFields.addAll(analysis.fieldsInvolved);
                allRecords.addAll(analysis.recordIds);
            }
        }
        
        summary.objectsDiscussed = new List<String>(allObjects);
        summary.fieldsDiscussed = new List<String>(allFields);
        summary.recordsDiscussed = new List<String>(allRecords);
        
        // Determine topic from most common entity
        if (!allObjects.isEmpty()) {
            summary.topic = allObjects.iterator().next() + ' ' + 
                           (session.Issue_Type__c != null ? session.Issue_Type__c : 'issue');
        } else {
            summary.topic = 'Salesforce ' + 
                           (session.Issue_Type__c != null ? session.Issue_Type__c : 'support');
        }
        
        return summary;
    }
    
    /**
     * @description Get recent messages (last N)
     * @param messages All messages
     * @return List of recent messages
     */
    private static List<Message> getRecentMessages(List<Message> messages) {
        List<Message> recent = new List<Message>();
        
        Integer startIndex = Math.max(0, messages.size() - MAX_RECENT_MESSAGES);
        
        for (Integer i = startIndex; i < messages.size(); i++) {
            recent.add(messages[i]);
        }
        
        return recent;
    }
    
    /**
     * @description Build current session state
     * @param session Diagnostic session record
     * @param messages List of messages
     * @return Session state
     */
    private static SessionState buildSessionState(
        Diagnostic_Session__c session,
        List<Message> messages
    ) {
        SessionState state = new SessionState();
        
        state.lastActivity = session.LastModifiedDate;
        state.issueResolved = (session.Resolution_Status__c == 'Resolved');
        
        // Extract diagnostics from diagnosis result
        if (String.isNotBlank(session.Diagnosis_Result__c)) {
            // Parse diagnostic results to find what was run
            // This is simplified - in production you might store this separately
            if (session.Diagnosis_Result__c.contains('Field-Level Security')) {
                state.diagnosticsRun.add('Field Security Check');
            }
            if (session.Diagnosis_Result__c.contains('Object Access')) {
                state.diagnosticsRun.add('Object Permissions Check');
            }
            if (session.Diagnosis_Result__c.contains('Record Access')) {
                state.diagnosticsRun.add('Record Access Check');
            }
            if (session.Diagnosis_Result__c.contains('Page Layout')) {
                state.diagnosticsRun.add('Page Layout Check');
            }
        }
        
        // Build set of all entities discussed
        for (Message msg : messages) {
            if (msg.role == 'user') {
                MessageAnalyzer.MessageAnalysis analysis = 
                    MessageAnalyzer.analyzeMessage(msg.content);
                
                for (String obj : analysis.objectsInvolved) {
                    state.entitiesDiscussed.add(obj);
                }
                for (String field : analysis.fieldsInvolved) {
                    state.entitiesDiscussed.add(field);
                }
            }
        }
        
        return state;
    }
    
    /**
     * @description Format context for AI consumption
     * @param context Conversation context
     * @return Formatted string for AI
     */
    private static String formatContextForAI(ConversationContext context) {
        List<String> parts = new List<String>();
        
        // Header
        parts.add('[CONVERSATION CONTEXT]');
        parts.add('');
        
        // Summary section
        parts.add('[CONVERSATION SUMMARY]');
        parts.add('Topic: ' + context.summary.topic);
        parts.add('Issue Type: ' + (context.summary.issueType != null ? context.summary.issueType : 'Not specified'));
        parts.add('Messages: ' + context.summary.messageCount);
        parts.add('Status: ' + (context.summary.resolutionStatus != null ? context.summary.resolutionStatus : 'Open'));
        
        if (!context.summary.objectsDiscussed.isEmpty()) {
            parts.add('Objects: ' + String.join(context.summary.objectsDiscussed, ', '));
        }
        if (!context.summary.fieldsDiscussed.isEmpty()) {
            parts.add('Fields: ' + String.join(context.summary.fieldsDiscussed, ', '));
        }
        if (!context.summary.recordsDiscussed.isEmpty()) {
            parts.add('Records: ' + context.summary.recordsDiscussed.size() + ' record(s)');
        }
        parts.add('');
        
        // Recent messages section
        if (!context.recentMessages.isEmpty()) {
            parts.add('[RECENT MESSAGES]');
            for (Message msg : context.recentMessages) {
                String role = msg.role.capitalize();
                parts.add(role + ': ' + msg.content);
            }
            parts.add('');
        }
        
        // Current state section
        parts.add('[CURRENT STATE]');
        if (!context.currentState.diagnosticsRun.isEmpty()) {
            parts.add('Diagnostics run: ' + String.join(context.currentState.diagnosticsRun, ', '));
        }
        if (!context.currentState.entitiesDiscussed.isEmpty()) {
            List<String> entities = new List<String>(context.currentState.entitiesDiscussed);
            parts.add('Entities discussed: ' + String.join(entities, ', '));
        }
        parts.add('Issue resolved: ' + (context.currentState.issueResolved ? 'Yes' : 'No'));
        parts.add('');
        
        return String.join(parts, '\n');
    }
    
    /**
     * @description Estimate token count from text
     * @param text Text to estimate
     * @return Estimated token count
     */
    private static Integer estimateTokens(String text) {
        if (String.isBlank(text)) return 0;
        return text.length() / ESTIMATED_TOKENS_PER_CHAR;
    }
    
    /**
     * @description Prune context to fit within token limits
     * @param context Current context
     * @param session Diagnostic session
     * @param messages All messages
     * @return Pruned context
     */
    private static ConversationContext pruneContext(
        ConversationContext context,
        Diagnostic_Session__c session,
        List<Message> messages
    ) {
        // Reduce recent messages to last 3 instead of 5
        context.recentMessages = getRecentMessages(messages, 3);
        
        // Simplify summary
        if (context.summary.objectsDiscussed.size() > 3) {
            context.summary.objectsDiscussed = new List<String>{
                context.summary.objectsDiscussed[0],
                context.summary.objectsDiscussed[1],
                '... and ' + (context.summary.objectsDiscussed.size() - 2) + ' more'
            };
        }
        
        // Rebuild formatted context
        context.formattedContext = formatContextForAI(context);
        context.estimatedTokens = estimateTokens(context.formattedContext);
        
        System.debug('Context pruned. New token estimate: ' + context.estimatedTokens);
        
        return context;
    }
    
    /**
     * @description Get recent messages with custom count
     * @param messages All messages
     * @param count Number of recent messages to return
     * @return List of recent messages
     */
    private static List<Message> getRecentMessages(List<Message> messages, Integer count) {
        List<Message> recent = new List<Message>();
        Integer startIndex = Math.max(0, messages.size() - count);
        
        for (Integer i = startIndex; i < messages.size(); i++) {
            recent.add(messages[i]);
        }
        
        return recent;
    }
    
    /**
     * @description Parse conversation history from JSON string
     * @param historyJson JSON string of conversation history
     * @return List of messages
     */
    private static List<Message> parseConversationHistory(String historyJson) {
        List<Message> messages = new List<Message>();
        
        if (String.isBlank(historyJson)) {
            return messages;
        }
        
        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(historyJson);
            
            for (Object obj : parsed) {
                Map<String, Object> msgMap = (Map<String, Object>) obj;
                
                Message msg = new Message(
                    (String) msgMap.get('role'),
                    (String) msgMap.get('content'),
                    (Integer) msgMap.get('sequenceNumber')
                );
                
                // Parse timestamp if exists
                if (msgMap.containsKey('timestamp')) {
                    String timestampStr = (String) msgMap.get('timestamp');
                    msg.timestamp = DateTime.valueOf(timestampStr);
                }
                
                messages.add(msg);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error parsing history: ' + e.getMessage());
        }
        
        return messages;
    }
    
    /**
     * @description Serialize messages to JSON string
     * @param messages List of messages
     * @return JSON string
     */
    private static String serializeConversationHistory(List<Message> messages) {
        List<Map<String, Object>> serialized = new List<Map<String, Object>>();
        
        for (Message msg : messages) {
            Map<String, Object> msgMap = new Map<String, Object>{
                'role' => msg.role,
                'content' => msg.content,
                'sequenceNumber' => msg.sequenceNumber,
                'timestamp' => msg.timestamp.format('yyyy-MM-dd HH:mm:ss')
            };
            serialized.add(msgMap);
        }
        
        return JSON.serialize(serialized);
    }
    
    /**
     * @description Get or create diagnostic session
     * @param sessionId Session ID (null for new session)
     * @return Diagnostic session record
     */
    private static Diagnostic_Session__c getOrCreateSession(String sessionId) {
        if (String.isNotBlank(sessionId)) {
            return getSession(sessionId);
        } else {
            return createNewSession();
        }
    }
    
    /**
     * @description Get existing session
     * @param sessionId Session ID
     * @return Diagnostic session record
     */
    private static Diagnostic_Session__c getSession(String sessionId) {
        List<Diagnostic_Session__c> sessions = [
            SELECT Id, User__c, Conversation_History__c, Issue_Type__c,
                   Resolution_Status__c, Diagnosis_Result__c, 
                   CreatedDate, LastModifiedDate
            FROM Diagnostic_Session__c
            WHERE Id = :sessionId
            LIMIT 1
        ];
        
        if (sessions.isEmpty()) {
            throw new ConversationException('Session not found: ' + sessionId);
        }
        
        return sessions[0];
    }
    
    /**
     * @description Create new diagnostic session
     * @return New diagnostic session record
     */
    private static Diagnostic_Session__c createNewSession() {
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            User__c = UserInfo.getUserId(),
            Resolution_Status__c = 'Open',
            Conversation_History__c = '[]'
        );
        
        insert session;
        
        System.debug('Created new session: ' + session.Id);
        
        return session;
    }
    
    /**
     * @description Update session with conversation history
     * @param sessionId Session ID
     * @param messages List of messages
     * @param context Current context
     */
    private static void updateSessionHistory(
        String sessionId,
        List<Message> messages,
        ConversationContext context
    ) {
        String historyJson = serializeConversationHistory(messages);
        
        // Truncate if too long for field (131,072 character limit)
        if (historyJson.length() > 131000) {
            // Keep only recent messages
            List<Message> recentOnly = getRecentMessages(messages, 10);
            historyJson = serializeConversationHistory(recentOnly);
        }
        
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Id = sessionId,
            Conversation_History__c = historyJson
        );
        
        // Update issue type if not set
        if (String.isNotBlank(context.summary.issueType)) {
            session.Issue_Type__c = context.summary.issueType;
        }
        
        update session;
    }
    
    /**
     * @description Update session with diagnostic results
     * @param sessionId Session ID
     * @param diagnosticResult Diagnostic result text
     */
    public static void updateDiagnosticResult(String sessionId, String diagnosticResult) {
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Id = sessionId,
            Diagnosis_Result__c = diagnosticResult
        );
        
        update session;
    }
    
    /**
     * @description Mark session as resolved
     * @param sessionId Session ID
     */
    public static void markSessionResolved(String sessionId) {
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Id = sessionId,
            Resolution_Status__c = 'Resolved'
        );
        
        update session;
    }
    
    /**
     * @description Clear conversation history (for testing or reset)
     * @param sessionId Session ID
     */
    public static void clearHistory(String sessionId) {
        Diagnostic_Session__c session = new Diagnostic_Session__c(
            Id = sessionId,
            Conversation_History__c = '[]'
        );
        
        update session;
    }
    
    /**
     * @description Get conversation statistics
     * @param sessionId Session ID
     * @return Map with statistics
     */
    public static Map<String, Object> getConversationStats(String sessionId) {
        Diagnostic_Session__c session = getSession(sessionId);
        List<Message> messages = parseConversationHistory(session.Conversation_History__c);
        
        Integer userMessages = 0;
        Integer assistantMessages = 0;
        
        for (Message msg : messages) {
            if (msg.role == 'user') {
                userMessages++;
            } else {
                assistantMessages++;
            }
        }
        
        return new Map<String, Object>{
            'totalMessages' => messages.size(),
            'userMessages' => userMessages,
            'assistantMessages' => assistantMessages,
            'sessionAge' => System.now().getTime() - session.CreatedDate.getTime(),
            'lastActivity' => session.LastModifiedDate,
            'status' => session.Resolution_Status__c
        };
    }
    
    /**
     * @description Custom exception for conversation errors
     */
    public class ConversationException extends Exception {}
}