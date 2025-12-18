import { LightningElement, track, wire } from 'lwc';
import searchUsers from '@salesforce/apex/UserSearchController.searchUsers';
import getUserDetails from '@salesforce/apex/UserSearchController.getUserDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class UserSearchComponent extends LightningElement {
    // Search input
    @track searchTerm = '';
    
    // Search results
    @track searchResults = [];
    @track selectedUser = null;
    
    // UI state
    @track isSearching = false;
    @track showResults = false;
    @track showNoResults = false;
    @track hasError = false;
    @track errorMessage = '';
    
    // Debounce timer
    searchTimeout;
    
    // Debounce delay in milliseconds
    DEBOUNCE_DELAY = 300;
    
    /**
     * Handle search input change with debouncing
     */
    handleSearchChange(event) {
        const searchValue = event.target.value;
        this.searchTerm = searchValue;
        
        // Clear previous timeout
        if (this.searchTimeout) {
            clearTimeout(this.searchTimeout);
        }
        
        // Reset state
        this.showResults = false;
        this.showNoResults = false;
        this.hasError = false;
        
        // If search is empty, clear results
        if (!searchValue || searchValue.trim().length === 0) {
            this.searchResults = [];
            return;
        }
        
        // Debounce search
        this.searchTimeout = setTimeout(() => {
            this.performSearch(searchValue);
        }, this.DEBOUNCE_DELAY);
    }
    
    /**
     * Perform user search via Apex
     */
    performSearch(searchValue) {
        // Minimum search length
        if (searchValue.trim().length < 2) {
            return;
        }
        
        this.isSearching = true;
        
        searchUsers({ searchTerm: searchValue })
            .then(results => {
                this.searchResults = results;
                this.isSearching = false;
                
                if (results && results.length > 0) {
                    this.showResults = true;
                    this.showNoResults = false;
                } else {
                    this.showResults = false;
                    this.showNoResults = true;
                }
            })
            .catch(error => {
                this.isSearching = false;
                this.hasError = true;
                this.errorMessage = this.reduceErrors(error);
                this.showErrorToast('Search Error', this.errorMessage);
                console.error('Search error:', error);
            });
    }
    
    /**
     * Handle user selection from search results
     */
    handleUserSelect(event) {
        const userId = event.currentTarget.dataset.userid;
        
        getUserDetails({ userId: userId })
            .then(userDetails => {
                this.selectedUser = userDetails;
                this.searchResults = [];
                this.showResults = false;
                this.showNoResults = false;
                
                // Dispatch event for parent components
                this.dispatchEvent(new CustomEvent('userselected', {
                    detail: { user: userDetails }
                }));
                
                this.showSuccessToast('User Selected', `Selected: ${userDetails.name}`);
            })
            .catch(error => {
                this.showErrorToast('Selection Error', this.reduceErrors(error));
                console.error('User selection error:', error);
            });
    }
    
    /**
     * Clear selected user
     */
    handleClearSelection() {
        this.selectedUser = null;
        this.searchTerm = '';
        this.searchResults = [];
        this.showResults = false;
        this.showNoResults = false;
        
        // Dispatch event
        this.dispatchEvent(new CustomEvent('usercleared'));
    }
    
    /**
     * Format date for display
     */
    formatDate(dateValue) {
        if (!dateValue) {
            return 'Never';
        }
        
        const date = new Date(dateValue);
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    }
    
    /**
     * Get user results for template iteration
     */
    get userResults() {
        return this.searchResults.map(user => {
            return {
                ...user,
                formattedLastLogin: this.formatDate(user.lastLoginDate),
                statusClass: user.isActive ? 'slds-badge slds-theme_success' : 'slds-badge',
                statusLabel: user.isActive ? 'Active' : 'Inactive'
            };
        });
    }
    
    /**
     * Check if user is selected
     */
    get hasSelectedUser() {
        return this.selectedUser !== null;
    }
    
    /**
     * Get formatted selected user
     */
    get formattedSelectedUser() {
        if (!this.selectedUser) {
            return null;
        }
        
        return {
            ...this.selectedUser,
            formattedLastLogin: this.formatDate(this.selectedUser.lastLoginDate)
        };
    }
    
    /**
     * Reduce errors to user-friendly message
     */
    reduceErrors(error) {
        if (!error) {
            return 'Unknown error';
        }
        
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        
        return 'Unknown error occurred';
    }
    
    /**
     * Show success toast
     */
    showSuccessToast(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success'
        }));
    }
    
    /**
     * Show error toast
     */
    showErrorToast(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error'
        }));
    }
}