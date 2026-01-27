import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processUserMessage from '@salesforce/apex/DiagnosticAssistantController.processUserMessage';

export default class DiagnosticAssistant extends LightningElement {
    // Component state
    @track messages = [];
    @track inputValue = '';
    @track isProcessing = false;
    @track errorMessage = '';
    
    // Session management
    @track sessionId = null;
    messageIdCounter = 0;

    // Computed properties
    get showWelcome() {
        return this.messages.length === 0 && !this.isProcessing;
    }

    get isSendDisabled() {
        return this.isProcessing || !this.inputValue.trim();
    }

    get characterCount() {
        return this.inputValue ? this.inputValue.length : 0;
    }

    // Lifecycle hooks
    connectedCallback() {
        console.log('Diagnostic Assistant initialized');
        this.addWelcomeMessage();
    }

    renderedCallback() {
        this.scrollToBottom();
        this.renderAIMessages();
    }

    // Event handlers
    handleInputChange(event) {
        this.inputValue = event.target.value;
        this.errorMessage = ''; // Clear errors on input
    }

    handleKeyPress(event) {
        // Send on Enter (unless Shift+Enter for newline) or Ctrl/Cmd+Enter
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.handleSendMessage();
        } else if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
            event.preventDefault();
            this.handleSendMessage();
        }
    }

    // Primary send method used by UI and tests
    async handleSendMessage() {
        if (this.isSendDisabled) {
            return;
        }

        const userMessage = this.inputValue.trim();
        if (!userMessage) {
            return;
        }

        // Add user message to UI
        this.addMessage('user', userMessage);

        // Clear input immediately for good UX
        this.inputValue = '';

        // Call backend / AI
        this.isProcessing = true;
        this.errorMessage = '';

        try {
            const result = await this.callApex(userMessage);
            
            // Handle different response formats
            let replyText = '';
            
            if (!result) {
                // No result - use fallback
                replyText = await this.simulateAPICall(userMessage);
            } else if (typeof result === 'string') {
                // Direct string response
                replyText = result;
            } else if (result.message) {
                // Response wrapper with message property
                replyText = result.message;
            } else if (result.error) {
                // Error response
                this.showError(result.error);
                return;
            } else {
                // Unknown format - stringify it
                replyText = JSON.stringify(result);
            }
            
            this.addMessage('ai', replyText);
            
        } catch (error) {
            console.error('Error processing message:', error);
            
            // Extract error message safely
            let errMsg = 'Unable to process your message. Please try again.';
            
            if (error && error.body && error.body.message) {
                errMsg = error.body.message;
            } else if (error && error.message) {
                errMsg = error.message;
            } else if (typeof error === 'string') {
                errMsg = error;
            }
            
            this.showError(errMsg);
        } finally {
            this.isProcessing = false;
        }
    }

    // Backwards-compatible method used by template/button
    handleSend() {
        this.handleSendMessage();
    }

    handleClose() {
        // Emit custom event for utility bar to close
        this.dispatchEvent(new CustomEvent('closeassistant'));
    }

    // Message handling methods
    addWelcomeMessage() {
        // Could add an initial AI greeting message here if needed
        // For now, the welcome div handles this
    }

    addUserMessage(text) {
        const message = {
            id: this.generateMessageId(),
            text: text,
            isAI: false,
            timestamp: this.formatTimestamp(new Date()),
            cssClass: 'message-wrapper user-message'
        };

        this.messages = [...this.messages, message];
        this.scrollToBottom();
    }

    addAIMessage(text, isError = false) {
        const message = {
            id: this.generateMessageId(),
            text: text,
            html: this.formatAIResponse(text),
            isAI: true,
            isError: isError,
            timestamp: this.formatTimestamp(new Date()),
            cssClass: 'message-wrapper ai-message'
        };

        this.messages = [...this.messages, message];
        this.scrollToBottom();
    }

    // Call Apex controller; fallback to simulated response if Apex not available
    async callApex(userMessage) {
        try {
            // Attempt to call Apex method
            const result = await processUserMessage({ 
                message: userMessage, 
                sessionId: this.sessionId 
            });
            
            console.log('Apex Response:', result);
            
            // If backend returns a sessionId, persist it
            if (result && result.sessionId) {
                this.sessionId = result.sessionId;
            }
            
            // Check if there's an error in the response
            if (result && result.success === false && result.error) {
                // This is an error response from Apex
                throw new Error(result.error);
            }
            
            // Return the result - let handleSendMessage handle the format
            return result;
            
        } catch (error) {
            console.error('Apex call failed:', error);
            // Re-throw so caller can handle
            throw error;
        }
    }

    // Simulated API call for testing (remove when integrating with Apex)
    simulateAPICall(userMessage) {
        return new Promise((resolve) => {
            setTimeout(() => {
                const response = this.generateMockResponse(userMessage);
                resolve(response);
            }, 1000);
        });
    }

    generateMockResponse(userMessage) {
        const lowerMessage = userMessage.toLowerCase();
        
        if (lowerMessage.includes('field') || lowerMessage.includes('see')) {
            return `I've checked your permissions. The field you're asking about may not be visible due to **Field-Level Security** settings.

                **To fix this:**
                1. Contact your Salesforce administrator
                2. Ask them to enable Field-Level Security for your profile
                3. Wait for the changes to take effect

                **Who can help:**
                Your administrators can make this change in Setup → Object Manager.

                Need help with anything else?`;
                        } else if (lowerMessage.includes('edit') || lowerMessage.includes('modify')) {
                            return `I see you're having trouble editing records. This could be due to:

                • Profile permissions not allowing edits
                • The record is locked in an approval process
                • You don't own the record and sharing rules don't grant edit access

                **What to do:**
                Contact your administrator to review your permissions and sharing settings.`;
                        } else {
                            return `Thanks for reaching out! I'm analyzing your issue.

                To help you better, I need more specific information:
                • What object/record are you working with?
                • What exactly are you trying to do?
                • What error message (if any) are you seeing?

                Please provide more details and I'll investigate further.`;
        }
    }

    // Utility methods
    generateMessageId() {
        return `msg_${++this.messageIdCounter}_${Date.now()}`;
    }

    addMessage(role, content, isError = false) {
        // Ensure content is a string
        if (content === null || content === undefined) {
            content = '';
        }
        
        // Convert to string if it's an object
        if (typeof content === 'object') {
            content = JSON.stringify(content);
        }
        
        const isAI = role === 'ai';
        const message = {
            id: this.generateMessageId(),
            text: isAI ? undefined : String(content),
            html: isAI ? this.formatAIResponse(String(content)) : undefined,
            isAI: isAI,
            isError: isError,
            timestamp: this.formatTimestamp(new Date()),
            cssClass: `message-wrapper ${isAI ? 'ai-message' : 'user-message'}`
        };

        this.messages = [...this.messages, message];
        this.scrollToBottom();
    }

    // Backwards-compatible helpers
    addUserMessage(text) {
        this.addMessage('user', text);
    }

    addAIMessage(text, isError = false) {
        this.addMessage('ai', text, isError);
    }

    showError(message) {
        this.errorMessage = message;
        this.showToast('Error', message, 'error');
    }

    formatTimestamp(date) {
        const hours = date.getHours();
        const minutes = date.getMinutes();
        const ampm = hours >= 12 ? 'PM' : 'AM';
        const displayHours = hours % 12 || 12;
        const displayMinutes = minutes < 10 ? '0' + minutes : minutes;
        return `${displayHours}:${displayMinutes} ${ampm}`;
    }

    formatAIResponse(text) {
        // Ensure text is a string
        if (!text) {
            return '';
        }
        
        // Convert to string if it's not already
        let html = String(text);
        
        // Bold: **text** to <strong>text</strong>
        html = html.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
        
        // Italic: *text* to <em>text</em>
        html = html.replace(/\*(.*?)\*/g, '<em>$1</em>');
        
        // Line breaks
        html = html.replace(/\n/g, '<br/>');
        
        // Bullet points
        html = html.replace(/^• /gm, '• ');
        
        return html;
    }

    renderAIMessages() {
        // Render HTML content for AI messages
        const aiMessages = this.template.querySelectorAll('.ai-bubble .message-text');
        aiMessages.forEach((element, index) => {
            const message = this.messages.filter(m => m.isAI)[index];
            if (message && message.html) {
                element.innerHTML = message.html;
            }
        });
    }

    scrollToBottom() {
        // Use setTimeout to ensure DOM is updated
        setTimeout(() => {
            const container = this.template.querySelector('.messages-container');
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Public methods for external control
    clearConversation() {
        this.messages = [];
        this.sessionId = null;
        this.messageIdCounter = 0;
        this.inputValue = '';
        this.errorMessage = '';
    }

    sendMessage(message) {
        if (message && message.trim()) {
            this.inputValue = message;
            this.handleSend();
        }
    }
}