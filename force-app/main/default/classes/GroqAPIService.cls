/**
 * @description Service class for communicating with Groq AI API
 * Handles all API calls including request formatting, response parsing, and error handling
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class GroqAPIService {
    
    // API Configuration
    private static final String GROQ_MODEL = 'llama-3.3-70b-versatile'; // Fast and capable
    private static final Integer DEFAULT_MAX_TOKENS = 1024;
    private static final Integer API_TIMEOUT = 120000; // 120 seconds
    
    // Cache for API key to avoid repeated queries
    private static String cachedApiKey;
    
    // Wrapper classes for API communication
    public class APIResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String content;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Integer tokensUsed;
        @AuraEnabled public String model;
        @AuraEnabled public String finishReason;
        
        public APIResponse() {
            this.success = false;
        }
    }
    
    public class Message {
        @AuraEnabled public String role; // 'system', 'user', or 'assistant'
        @AuraEnabled public String content;
        
        public Message(String role, String content) {
            this.role = role;
            this.content = content;
        }
    }
    
    public class GroqRequest {
        public String model;
        public List<Message> messages;
        public Integer max_tokens;
        public Decimal temperature;
        public Decimal top_p;
        
        public GroqRequest() {
            this.model = GROQ_MODEL;
            this.messages = new List<Message>();
            this.max_tokens = DEFAULT_MAX_TOKENS;
            this.temperature = 0.7;
            this.top_p = 1.0;
        }
    }
    
    /**
     * @description Get API key from Custom Metadata with caching
     * @return API key string
     */
    private static String getApiKey() {
        if (String.isNotBlank(cachedApiKey)) {
            return cachedApiKey;
        }
        
        try {
            List<Groq_API_Configuration__mdt> configs = [
                SELECT API_Key__c 
                FROM Groq_API_Configuration__mdt 
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                throw new APIException('Groq API configuration not found in Custom Metadata');
            }
            
            cachedApiKey = configs[0].API_Key__c;
            
            if (String.isBlank(cachedApiKey)) {
                throw new APIException('API key is blank in Custom Metadata');
            }
            
            return cachedApiKey;
            
        } catch (Exception e) {
            throw new APIException('Failed to retrieve API key: ' + e.getMessage());
        }
    }
    
    /**
     * @description Send a simple message to Groq AI
     * @param userMessage The user's message
     * @param maxTokens Maximum tokens for response
     * @return APIResponse with the AI's response
     */
    public static APIResponse sendMessage(String userMessage, Integer maxTokens) {
        List<Message> messages = new List<Message>();
        messages.add(new Message('user', userMessage));
        
        return sendMessages(messages, maxTokens);
    }
    
    /**
     * @description Send message with context and system prompt
     * @param userMessage The user's current message
     * @param systemPrompt System instructions for the AI
     * @param context Additional context (conversation history, diagnostics, etc.)
     * @return APIResponse with the AI's response
     */
    public static APIResponse sendMessageWithContext(
        String userMessage, 
        String systemPrompt, 
        String context
    ) {
        List<Message> messages = new List<Message>();
        
        // Add system prompt if provided
        if (String.isNotBlank(systemPrompt)) {
            messages.add(new Message('system', systemPrompt));
        }
        
        // Add context as a user message if provided
        if (String.isNotBlank(context)) {
            messages.add(new Message('user', context));
        }
        
        // Add the actual user message
        messages.add(new Message('user', userMessage));
        
        return sendMessages(messages, DEFAULT_MAX_TOKENS);
    }
    
    /**
     * @description Send a list of messages to Groq AI
     * @param messages List of Message objects (conversation history)
     * @param maxTokens Maximum tokens for response
     * @return APIResponse with the AI's response
     */
    public static APIResponse sendMessages(List<Message> messages, Integer maxTokens) {
        APIResponse response = new APIResponse();
        
        try {
            // Validate inputs
            if (messages == null || messages.isEmpty()) {
                response.errorMessage = 'Messages list cannot be empty';
                return response;
            }
            
            if (maxTokens == null || maxTokens <= 0) {
                maxTokens = DEFAULT_MAX_TOKENS;
            }
            
            // Build the request
            GroqRequest groqRequest = new GroqRequest();
            groqRequest.messages = messages;
            groqRequest.max_tokens = maxTokens;
            
            // Make the API call
            HttpRequest req = buildRequest(groqRequest);
            Http http = new Http();
            
            System.debug('Sending request to Groq API with ' + messages.size() + ' messages');
            
            HttpResponse res = http.send(req);
            
            System.debug('Groq API Response Status: ' + res.getStatusCode());
            
            // Parse the response
            response = parseResponse(res);
            
            // Log token usage
            if (response.success && response.tokensUsed != null) {
                System.debug('Tokens used: ' + response.tokensUsed);
            }
            
        } catch (CalloutException e) {
            response.success = false;
            response.errorMessage = 'API Callout failed: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, response.errorMessage);
        } catch (APIException e) {
            response.success = false;
            response.errorMessage = e.getMessage();
            System.debug(LoggingLevel.ERROR, response.errorMessage);
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = 'Unexpected error: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, response.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return response;
    }
    
    /**
     * @description Build HTTP request for Groq API
     * @param groqRequest The request object
     * @return Configured HttpRequest
     */
    private static HttpRequest buildRequest(GroqRequest groqRequest) {
        HttpRequest req = new HttpRequest();
        
        // Use Named Credential (configured in Salesforce Setup)
        req.setEndpoint('callout:Groq_API/openai/v1/chat/completions');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(API_TIMEOUT);
        
        // CRITICAL: Add Authorization header with API key from Custom Metadata
        String apiKey = getApiKey();
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        
        // Serialize the request body
        String requestBody = JSON.serialize(groqRequest);
        req.setBody(requestBody);
             
        System.debug('Request Body: ' + requestBody);
        
        return req;
    }
    
    /**
     * @description Parse the HTTP response from Groq API
     * @param res HttpResponse from API call
     * @return APIResponse wrapper with parsed data
     */
    private static APIResponse parseResponse(HttpResponse res) {
        APIResponse response = new APIResponse();
        
        try {
            Integer statusCode = res.getStatusCode();
            String responseBody = res.getBody();
            
            System.debug('Response Body: ' + responseBody);
            
            if (statusCode == 200) {
                // Success - parse JSON response
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                
                // Extract the assistant's message
                List<Object> choices = (List<Object>) jsonResponse.get('choices');
                if (choices != null && !choices.isEmpty()) {
                    Map<String, Object> choice = (Map<String, Object>) choices[0];
                    Map<String, Object> message = (Map<String, Object>) choice.get('message');
                    
                    response.content = (String) message.get('content');
                    response.finishReason = (String) choice.get('finish_reason');
                    response.success = true;
                }
                
                // Extract token usage
                Map<String, Object> usage = (Map<String, Object>) jsonResponse.get('usage');
                if (usage != null) {
                    response.tokensUsed = (Integer) usage.get('total_tokens');
                }
                
                // Extract model
                response.model = (String) jsonResponse.get('model');
                
            } else if (statusCode == 429) {
                // Rate limit error
                response.errorMessage = 'Rate limit exceeded. Please try again in a moment.';
                logError(statusCode, responseBody);
                
            } else if (statusCode == 401) {
                // Authentication error
                response.errorMessage = 'API authentication failed. Please check API key configuration in Custom Metadata.';
                logError(statusCode, responseBody);
                
            } else if (statusCode == 400) {
                // Bad request
                response.errorMessage = 'Invalid request sent to API.';
                logError(statusCode, responseBody);
                
            } else if (statusCode >= 500) {
                // Server error
                response.errorMessage = 'Groq API service is temporarily unavailable.';
                logError(statusCode, responseBody);
                
            } else {
                // Other errors
                response.errorMessage = 'API returned status code: ' + statusCode;
                logError(statusCode, responseBody);
            }
            
        } catch (JSONException e) {
            response.errorMessage = 'Failed to parse API response: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, response.errorMessage);
        } catch (Exception e) {
            response.errorMessage = 'Error processing response: ' + e.getMessage();
            System.debug(LoggingLevel.ERROR, response.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return response;
    }
    
    /**
     * @description Log API errors for monitoring
     * @param statusCode HTTP status code
     * @param responseBody Response body
     */
    private static void logError(Integer statusCode, String responseBody) {
        System.debug(LoggingLevel.ERROR, 'Groq API Error - Status: ' + statusCode);
        System.debug(LoggingLevel.ERROR, 'Response: ' + responseBody);
        
        // In production, you might want to create a custom log record
        // or send to external monitoring service
    }
    
    /**
     * @description Build system prompt for Salesforce diagnostic assistant
     * @return String with system instructions
     */
    public static String buildDiagnosticSystemPrompt() {
        return 'You are a Salesforce diagnostic assistant helping users troubleshoot permission and access issues.\n\n' +
               'YOUR ROLE:\n' +
               '- Analyze Salesforce permission problems\n' +
               '- Explain issues in simple, non-technical terms\n' +
               '- Provide clear, step-by-step solutions\n' +
               '- Be empathetic and patient\n\n' +
               'RESPONSE FORMAT:\n' +
               '1. Briefly explain what the problem is\n' +
               '2. Why it\'s happening\n' +
               '3. How to fix it (step-by-step)\n' +
               '4. Who can help (if admin is needed)\n' +
               '5. Ask if they need more help\n\n' +
               'TONE:\n' +
               '- Friendly and professional\n' +
               '- Clear and concise\n' +
               '- Avoid technical jargon\n' +
               '- Use simple explanations\n\n' +
               'CONSTRAINTS:\n' +
               '- Base answers on the diagnostic results provided\n' +
               '- Don\'t make up information\n' +
               '- If unsure, admit it and suggest alternatives\n' +
               '- Always provide at least one actionable next step';
    }
    
    /**
     * @description Test API connectivity
     * @return Boolean indicating if API is accessible
     */
    public static Boolean testConnection() {
        try {
            APIResponse response = sendMessage('Hello, this is a connection test.', 50);
            return response.success;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Connection test failed: ' + e.getMessage());
            return false;
        }
    }
    
    /**
     * @description Get API usage statistics (placeholder for future enhancement)
     * @return Map with usage stats
     */
    public static Map<String, Integer> getUsageStats() {
        Map<String, Integer> stats = new Map<String, Integer>();
        // In production, you would query custom objects or logs
        // For now, return empty stats
        stats.put('totalCalls', 0);
        stats.put('totalTokens', 0);
        return stats;
    }
    
    /**
     * @description Clear cached API key (useful for testing)
     */
    @TestVisible
    private static void clearCache() {
        cachedApiKey = null;
    }
    
    /**
     * @description Custom exception for API-related errors
     */
    public class APIException extends Exception {}
}