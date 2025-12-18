import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DiagnosticToolComponent extends LightningElement {
    // Component version
    toolVersion = '1.0.0';
    
    // Track panel visibility
    @track showProgress = false;
    @track showResults = false;
    
    // Track active tab
    @track activeTab = 'input';
    
    /**
     * Lifecycle hook - component connected to DOM
     */
    connectedCallback() {
        console.log('Diagnostic Tool Component initialized - Version: ' + this.toolVersion);
    }
    
    /**
     * Handle tab activation
     */
    handleTabActivation(event) {
        this.activeTab = event.target.value;
        console.log('Active tab changed to: ' + this.activeTab);
    }
    
    /**
     * Handle user selection event
     */
    handleUserSelected(event) {
        const selectedUser = event.detail.user;
        this.selectedUserId = selectedUser.id;
        console.log('User selected:', selectedUser.name);
        
        // Store for future diagnostic operations
        this.currentUser = selectedUser;
        
        // Show success message
        this.showToast('Success', `Selected user: ${selectedUser.name}`, 'success');
    }

    /**
     * Handle user cleared event
     */
    handleUserCleared() {
        this.selectedUserId = null;
        this.currentUser = null;
        console.log('User selection cleared');
    }

    /**
     * Handle object selection event
     */
    handleObjectSelected(event) {
        const objectName = event.detail.objectName;  // ✅ Correct property
        this.selectedObject = objectName;
        console.log('Object selected:', objectName);
        this.showToast('Success', `Selected object: ${objectName}`, 'success');
    }

    /**
     * Handle field selection event
     */
        handleFieldSelected(event) {
        const { objectName, fieldName, fieldInfo } = event.detail;  // ✅ Correct properties
        this.selectedField = fieldName;
        this.selectedFieldInfo = fieldInfo;
        console.log('Field selected:', fieldName, 'on', objectName);
        this.showToast('Success', `Selected field: ${fieldInfo.label}`, 'success');
    }

    /**
     * Handle selection cleared event
     */
    handleSelectionCleared() {
        this.selectedObject = null;
        this.selectedField = null;
        console.log('Selection cleared');
        this.showToast('Info', 'Selection cleared', 'info');
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
    
    /**
     * Toggle progress panel visibility
     */
    toggleProgress() {
        this.showProgress = !this.showProgress;
    }
    
    /**
     * Toggle results panel visibility
     */
    toggleResults() {
        this.showResults = !this.showResults;
    }
    
    /**
     * Get header title with version
     */
    get headerTitle() {
        return `Salesforce Diagnostic Tool v${this.toolVersion}`;
    }
    
    /**
     * Get current year for footer
     */
    get currentYear() {
        return new Date().getFullYear();
    }
}