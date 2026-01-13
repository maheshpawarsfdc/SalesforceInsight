/**
 * @description Service for parsing and formatting AI responses for display
 * Handles markdown, special sections, links, and response validation
 * @author Salesforce AI Diagnostic Assistant
 * @date 2026
 */
public with sharing class AIResponseParser {
    
    /**
     * @description Wrapper class for parsed response
     */
    public class ParsedResponse {
        @AuraEnabled public String rawContent;
        @AuraEnabled public String formattedContent;
        @AuraEnabled public List<String> steps;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public List<String> adminContacts;
        @AuraEnabled public List<LinkInfo> links;
        @AuraEnabled public Boolean isComplete;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public ResponseQuality quality;
        
        public ParsedResponse() {
            this.steps = new List<String>();
            this.warnings = new List<String>();
            this.adminContacts = new List<String>();
            this.links = new List<LinkInfo>();
            this.isComplete = false;
        }
    }
    
    /**
     * @description Wrapper for link information
     */
    public class LinkInfo {
        @AuraEnabled public String text;
        @AuraEnabled public String url;
        @AuraEnabled public Boolean isValid;
        
        public LinkInfo(String text, String url) {
            this.text = text;
            this.url = url;
            this.isValid = validateUrl(url);
        }
        
        private Boolean validateUrl(String url) {
            if (String.isBlank(url)) {
                return false;
            }
            // Basic URL validation
            return url.startsWith('http://') || url.startsWith('https://');
        }
    }
    
    /**
     * @description Response quality metrics
     */
    public class ResponseQuality {
        @AuraEnabled public Integer length;
        @AuraEnabled public Boolean hasSteps;
        @AuraEnabled public Boolean hasExplanation;
        @AuraEnabled public Boolean hasNextSteps;
        @AuraEnabled public String qualityScore; // 'high', 'medium', 'low'
        
        public ResponseQuality() {
            this.qualityScore = 'medium';
        }
    }
    
    /**
     * @description Main method to parse AI response
     * @param rawResponse Raw response from AI API
     * @return ParsedResponse with formatted content
     */
    public static ParsedResponse parseResponse(String rawResponse) {
        ParsedResponse parsed = new ParsedResponse();
        
        try {
            if (String.isBlank(rawResponse)) {
                parsed.errorMessage = 'Response is empty';
                return parsed;
            }
            
            // Store raw content
            parsed.rawContent = rawResponse;
            
            // Remove JSON wrapper if present
            String cleanedResponse = removeJsonWrapper(rawResponse);
            
            // Clean up any extra whitespace
            cleanedResponse = cleanedResponse.trim();
            
            // Handle markdown formatting
            String formattedContent = handleMarkdown(cleanedResponse);
            
            // Extract special sections
            parsed.steps = extractSteps(cleanedResponse);
            parsed.warnings = extractWarnings(cleanedResponse);
            parsed.adminContacts = extractAdminContacts(cleanedResponse);
            parsed.links = extractLinks(cleanedResponse);
            
            // Store formatted content
            parsed.formattedContent = formattedContent;
            
            // Validate completeness
            parsed.isComplete = validateCompleteness(cleanedResponse);
            
            // Assess quality
            parsed.quality = assessQuality(cleanedResponse, parsed);
            
            System.debug('Response parsed successfully: ' + formattedContent.length() + ' characters');
            
        } catch (Exception e) {
            parsed.errorMessage = 'Error parsing response: ' + e.getMessage();
            parsed.formattedContent = rawResponse; // Fallback to raw content
            System.debug(LoggingLevel.ERROR, parsed.errorMessage + '\n' + e.getStackTraceString());
        }
        
        return parsed;
    }
    
    /**
     * @description Remove JSON wrapper if present
     * @param content Content to clean
     * @return Cleaned content
     */
    private static String removeJsonWrapper(String content) {
        if (String.isBlank(content)) {
            return '';
        }
        
        // Remove markdown code blocks
        content = content.replaceAll('```json\\s*', '');
        content = content.replaceAll('```\\s*', '');
        
        // Try to parse as JSON and extract content field
        try {
            if (content.trim().startsWith('{')) {
                Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(content);
                if (jsonMap.containsKey('content')) {
                    return String.valueOf(jsonMap.get('content'));
                }
            }
        } catch (Exception e) {
            // Not JSON, continue with original content
        }
        
        return content;
    }
    
    /**
     * @description Handle markdown formatting
     * @param content Content with markdown
     * @return Content with HTML formatting
     */
    private static String handleMarkdown(String content) {
        if (String.isBlank(content)) {
            return '';
        }
        
        String formatted = content;
        
        // Convert bold: **text** or __text__ to <strong>text</strong>
        formatted = formatted.replaceAll('\\*\\*([^*]+)\\*\\*', '<strong>$1</strong>');
        formatted = formatted.replaceAll('__([^_]+)__', '<strong>$1</strong>');
        
        // Convert italic: *text* or _text_ to <em>text</em>
        formatted = formatted.replaceAll('\\*([^*]+)\\*', '<em>$1</em>');
        formatted = formatted.replaceAll('_([^_]+)_', '<em>$1</em>');
        
        // Convert inline code: `text` to <code>text</code>
        formatted = formatted.replaceAll('`([^`]+)`', '<code>$1</code>');
        
        // Preserve line breaks
        formatted = formatted.replaceAll('\\n', '<br/>');
        
        // Handle bullet lists: - item or * item
        formatted = formatted.replaceAll('(?m)^[-*]\\s+(.+)$', '• $1');
        
        // Handle numbered lists: 1. item, 2. item
        // (Keep as-is, they display fine)
        
        return formatted;
    }
    
    /**
     * @description Extract numbered steps from response
     * @param content Response content
     * @return List of steps
     */
    private static List<String> extractSteps(String content) {
        List<String> steps = new List<String>();
        
        if (String.isBlank(content)) {
            return steps;
        }
        
        // Pattern: 1. step, 2. step, etc.
        Pattern stepPattern = Pattern.compile('(?m)^(\\d+)\\.\\s+(.+)$');
        Matcher stepMatcher = stepPattern.matcher(content);
        
        while (stepMatcher.find()) {
            String step = stepMatcher.group(2).trim();
            if (String.isNotBlank(step)) {
                steps.add(step);
            }
        }
        
        System.debug('Extracted ' + steps.size() + ' steps');
        return steps;
    }
    
    /**
     * @description Extract warnings from response
     * @param content Response content
     * @return List of warnings
     */
    private static List<String> extractWarnings(String content) {
        List<String> warnings = new List<String>();
        
        if (String.isBlank(content)) {
            return warnings;
        }
        
        // Look for warning keywords
        List<String> warningKeywords = new List<String>{
            'warning', 'caution', 'important', 'note', 'careful'
        };
        
        // Split into sentences
        List<String> sentences = content.split('[.!?]');
        
        for (String sentence : sentences) {
            String lowerSentence = sentence.toLowerCase();
            for (String keyword : warningKeywords) {
                if (lowerSentence.contains(keyword)) {
                    warnings.add(sentence.trim());
                    break; // Only add once per sentence
                }
            }
        }
        
        System.debug('Extracted ' + warnings.size() + ' warnings');
        return warnings;
    }
    
    /**
     * @description Extract admin contact information
     * @param content Response content
     * @return List of admin contacts
     */
    private static List<String> extractAdminContacts(String content) {
        List<String> contacts = new List<String>();
        
        if (String.isBlank(content)) {
            return contacts;
        }
        
        // Pattern: name (email@domain.com)
        Pattern emailPattern = Pattern.compile('([A-Z][a-z]+\\s+[A-Z][a-z]+)\\s*\\(([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})\\)');
        Matcher emailMatcher = emailPattern.matcher(content);
        
        while (emailMatcher.find()) {
            String name = emailMatcher.group(1);
            String email = emailMatcher.group(2);
            contacts.add(name + ' (' + email + ')');
        }
        
        // Also look for standalone emails
        Pattern standaloneEmailPattern = Pattern.compile('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}');
        Matcher standaloneEmailMatcher = standaloneEmailPattern.matcher(content);
        
        while (standaloneEmailMatcher.find()) {
            String email = standaloneEmailMatcher.group();
            // Only add if not already captured above
            Boolean alreadyAdded = false;
            for (String contact : contacts) {
                if (contact.contains(email)) {
                    alreadyAdded = true;
                    break;
                }
            }
            if (!alreadyAdded) {
                contacts.add(email);
            }
        }
        
        System.debug('Extracted ' + contacts.size() + ' admin contacts');
        return contacts;
    }
    
    /**
     * @description Extract links from response
     * @param content Response content
     * @return List of LinkInfo objects
     */
    private static List<LinkInfo> extractLinks(String content) {
        List<LinkInfo> links = new List<LinkInfo>();
        
        if (String.isBlank(content)) {
            return links;
        }
        
        // Pattern for markdown links: [text](url)
        Pattern markdownLinkPattern = Pattern.compile('\\[([^\\]]+)\\]\\(([^)]+)\\)');
        Matcher markdownLinkMatcher = markdownLinkPattern.matcher(content);
        
        while (markdownLinkMatcher.find()) {
            String text = markdownLinkMatcher.group(1);
            String url = markdownLinkMatcher.group(2);
            links.add(new LinkInfo(text, url));
        }
        
        // Pattern for plain URLs
        Pattern urlPattern = Pattern.compile('https?://[^\\s<>"{}|\\\\^`\\[\\]]+');
        Matcher urlMatcher = urlPattern.matcher(content);
        
        while (urlMatcher.find()) {
            String url = urlMatcher.group();
            // Only add if not already in markdown links
            Boolean alreadyAdded = false;
            for (LinkInfo link : links) {
                if (link.url == url) {
                    alreadyAdded = true;
                    break;
                }
            }
            if (!alreadyAdded) {
                links.add(new LinkInfo(url, url));
            }
        }
        
        System.debug('Extracted ' + links.size() + ' links');
        return links;
    }
    
    /**
     * @description Validate response completeness
     * @param content Response content
     * @return Boolean indicating if response is complete
     */
    private static Boolean validateCompleteness(String content) {
        if (String.isBlank(content)) {
            return false;
        }
        
        // Check minimum length (at least 50 characters)
        if (content.length() < 50) {
            System.debug('Response too short: ' + content.length() + ' characters');
            return false;
        }
        
        // Check for key indicators of completeness
        String lowerContent = content.toLowerCase();
        
        Boolean hasExplanation = lowerContent.contains('issue') || 
                                 lowerContent.contains('problem') ||
                                 lowerContent.contains('because') ||
                                 lowerContent.contains('reason');
        
        Boolean hasSolution = lowerContent.contains('fix') || 
                             lowerContent.contains('resolve') ||
                             lowerContent.contains('contact') ||
                             lowerContent.contains('request') ||
                             lowerContent.contains('ask');
        
        Boolean hasClosing = lowerContent.contains('help') || 
                            lowerContent.contains('need') ||
                            lowerContent.contains('else') ||
                            lowerContent.contains('?');
        
        Boolean isComplete = hasExplanation && hasSolution;
        
        System.debug('Response completeness: ' + isComplete + 
                    ' (Explanation: ' + hasExplanation + 
                    ', Solution: ' + hasSolution + 
                    ', Closing: ' + hasClosing + ')');
        
        return isComplete;
    }
    
    /**
     * @description Assess response quality
     * @param content Response content
     * @param parsed Parsed response object
     * @return ResponseQuality assessment
     */
    private static ResponseQuality assessQuality(String content, ParsedResponse parsed) {
        ResponseQuality quality = new ResponseQuality();
        
        // Basic metrics
        quality.length = content.length();
        quality.hasSteps = !parsed.steps.isEmpty();
        
        String lowerContent = content.toLowerCase();
        quality.hasExplanation = lowerContent.contains('issue') || 
                                 lowerContent.contains('problem') ||
                                 lowerContent.contains('because');
        
        quality.hasNextSteps = lowerContent.contains('contact') || 
                              lowerContent.contains('admin') ||
                              lowerContent.contains('request') ||
                              lowerContent.contains('help');
        
        // Calculate quality score
        Integer score = 0;
        
        // Length scoring
        if (quality.length >= 100 && quality.length <= 500) {
            score += 2; // Good length
        } else if (quality.length > 50) {
            score += 1; // Acceptable length
        }
        
        // Content scoring
        if (quality.hasExplanation) score += 2;
        if (quality.hasSteps) score += 2;
        if (quality.hasNextSteps) score += 2;
        if (parsed.isComplete) score += 2;
        
        // Determine quality level
        if (score >= 8) {
            quality.qualityScore = 'high';
        } else if (score >= 5) {
            quality.qualityScore = 'medium';
        } else {
            quality.qualityScore = 'low';
        }
        
        System.debug('Response quality: ' + quality.qualityScore + ' (score: ' + score + '/10)');
        
        return quality;
    }
    
    /**
     * @description Format error response for display
     * @param errorMessage Error message
     * @param suggestion Suggestion for user
     * @return Formatted error response
     */
    public static String formatErrorResponse(String errorMessage, String suggestion) {
        String formatted = '<div class="error-message">';
        formatted += '<strong>⚠️ Oops! Something went wrong</strong><br/><br/>';
        
        if (String.isNotBlank(errorMessage)) {
            formatted += '<em>' + escapeHtml(errorMessage) + '</em><br/><br/>';
        }
        
        if (String.isNotBlank(suggestion)) {
            formatted += '<strong>What you can do:</strong><br/>';
            formatted += escapeHtml(suggestion);
        } else {
            formatted += '<strong>What you can do:</strong><br/>';
            formatted += '• Try rephrasing your question<br/>';
            formatted += '• Check your internet connection<br/>';
            formatted += '• Contact your administrator if the problem persists';
        }
        
        formatted += '</div>';
        
        return formatted;
    }
    
    /**
     * @description Escape HTML special characters for security
     * @param text Text to escape
     * @return Escaped text
     */
    private static String escapeHtml(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        
        return text.replaceAll('&', '&amp;')
                   .replaceAll('<', '&lt;')
                   .replaceAll('>', '&gt;')
                   .replaceAll('"', '&quot;')
                   .replaceAll('\'', '&#39;');
    }
    
    /**
     * @description Create fallback response when parsing fails
     * @param rawResponse Raw response content
     * @return ParsedResponse with fallback formatting
     */
    public static ParsedResponse createFallbackResponse(String rawResponse) {
        ParsedResponse fallback = new ParsedResponse();
        
        fallback.rawContent = rawResponse;
        fallback.formattedContent = escapeHtml(rawResponse);
        fallback.isComplete = String.isNotBlank(rawResponse) && rawResponse.length() > 50;
        
        // Basic quality assessment
        fallback.quality = new ResponseQuality();
        fallback.quality.length = rawResponse != null ? rawResponse.length() : 0;
        fallback.quality.qualityScore = 'low';
        
        System.debug('Created fallback response');
        
        return fallback;
    }
    
    /**
     * @description Truncate response if too long
     * @param content Content to truncate
     * @param maxLength Maximum length
     * @return Truncated content
     */
    public static String truncateResponse(String content, Integer maxLength) {
        if (String.isBlank(content) || content.length() <= maxLength) {
            return content;
        }
        
        // Try to truncate at sentence boundary
        String truncated = content.substring(0, maxLength);
        Integer lastPeriod = truncated.lastIndexOf('.');
        
        if (lastPeriod > maxLength - 100) { // Within 100 chars of limit
            truncated = truncated.substring(0, lastPeriod + 1);
        } else {
            truncated += '...';
        }
        
        return truncated;
    }
}