import { LightningElement, wire, track } from 'lwc';
import getAllObjects from '@salesforce/apex/ObjectFieldController.getAllObjects';
import getObjectFields from '@salesforce/apex/ObjectFieldController.getObjectFields';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ObjectFieldSelector extends LightningElement {
    // Selected values
    @track selectedObject = '';
    @track selectedField = '';
    
    // Data lists
    @track objectOptions = [];
    @track fieldOptions = [];
    
    // UI state
    @track isLoadingObjects = false;
    @track isLoadingFields = false;
    @track showFieldDropdown = false;
    @track hasError = false;
    @track errorMessage = '';
    
    // Wired data
    wiredObjectsResult;
    
    /**
     * Wire getAllObjects with caching
     */
    @wire(getAllObjects)
    wiredObjects(result) {
        this.wiredObjectsResult = result;
        this.isLoadingObjects = true;
        
        if (result.data) {
            this.processObjectData(result.data);
            this.isLoadingObjects = false;
            this.hasError = false;
        } else if (result.error) {
            this.handleError('Error loading objects', result.error);
            this.isLoadingObjects = false;
        }
    }
    
    /**
     * Process object data into combobox format
    */
    processObjectData(data) {
        // Group objects by category
        const standardObjects = [];
        const customObjects = [];
        
        data.forEach(obj => {
            const option = {
                label: `${obj.label} (${obj.value})`,
                value: obj.value,
                isCustom: obj.isCustom
            };
            
            if (obj.isCustom) {
                customObjects.push(option);
            } else {
                standardObjects.push(option);
            }
        });
        
        // Build grouped options with unique keys
        this.objectOptions = [];
        
        if (standardObjects.length > 0) {
            // Add each standard object individually with unique key
            standardObjects.forEach(obj => {
                this.objectOptions.push({
                    label: obj.label,
                    value: obj.value,
                    key: `standard-${obj.value}` // ✅ Unique key
                });
            });
        }
        
        if (customObjects.length > 0) {
            // Add each custom object individually with unique key
            customObjects.forEach(obj => {
                this.objectOptions.push({
                    label: obj.label,
                    value: obj.value,
                    key: `custom-${obj.value}` // ✅ Unique key
                });
            });
        }
    }
    
    /**
     * Handle object selection
     */
    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        console.log('[ObjectFieldSelector] Object selected:', this.selectedObject);
        this.selectedField = '';
        this.fieldOptions = [];
        this.showFieldDropdown = false;
        this.hasError = false;
        
        if (this.selectedObject) {
            this.loadFields(this.selectedObject);
            
            // Dispatch event to parent
            this.dispatchEvent(new CustomEvent('objectselected', {
                detail: { objectName: this.selectedObject }
            }));
        }
    }
    
    /**
     * Load fields for selected object
     */
    loadFields(objectName) {
        this.isLoadingFields = true;
        console.log('[ObjectFieldSelector] Loading fields for', objectName);
        
        getObjectFields({ objectName: objectName })
            .then(result => {
                console.log('[ObjectFieldSelector] loadFields result for', objectName, result);
                if (result && result.length > 0) {
                    this.processFieldData(result);
                    this.showFieldDropdown = true;
                    this.hasError = false;
                } else {
                    // No accessible fields found for this object
                    this.processFieldData([]);
                    this.showFieldDropdown = false;
                    this.hasError = false;
                    this.showErrorToast('No Fields', `No accessible fields found for ${objectName}`);
                }
                this.isLoadingFields = false;
            })
            .catch(error => {
                this.handleError('Error loading fields', error);
                this.isLoadingFields = false;
            });
    }
    
    /**
     * Process field data into combobox format
     */
    processFieldData(data) {
        console.log('[ObjectFieldSelector] processFieldData, count:', data ? data.length : 0);
        if (!data || data.length === 0) {
            this.fieldOptions = [];
            return;
        }
        
        this.fieldOptions = data.map(field => {
            // Create label with field info
            const customIndicator = field.isCustom ? '🔧' : '';
            const label = `${field.label} ${customIndicator}`;
            const description = `${field.apiName} (${field.dataType})`;
            
            return {
                label: label,
                value: field.value,
                description: description,
                apiName: field.apiName,
                dataType: field.dataType,
                isCustom: field.isCustom
            };
        });
    }
    
    /**
     * Handle field selection
     */
    handleFieldChange(event) {
        this.selectedField = event.detail.value;
        
        // Find full field info
        const fieldInfo = this.fieldOptions.find(f => f.value === this.selectedField);
        
        if (fieldInfo) {
            // Dispatch event to parent
            this.dispatchEvent(new CustomEvent('fieldselected', {
                detail: {
                    objectName: this.selectedObject,
                    fieldName: this.selectedField,
                    fieldInfo: fieldInfo
                }
            }));
            
            this.showSuccessToast('Field Selected', `Selected: ${fieldInfo.label}`);
        }
    }
    
    /**
     * Clear selections
     */
    handleClear() {
        this.selectedObject = '';
        this.selectedField = '';
        this.fieldOptions = [];
        this.showFieldDropdown = false;
        
        // Dispatch event
        this.dispatchEvent(new CustomEvent('selectioncleared'));
    }
    
    /**
     * Handle errors
     */
    handleError(title, error) {
        this.hasError = true;
        this.errorMessage = this.reduceErrors(error);
        this.showErrorToast(title, this.errorMessage);
        console.error(title + ':', error);
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
    
    /**
     * Check if selections are complete
     */
    get hasCompleteSelection() {
        return this.selectedObject && this.selectedField;
    }
    
    /**
     * Get selection summary
     */
    get selectionSummary() {
        if (!this.hasCompleteSelection) {
            return null;
        }
        
        const fieldInfo = this.fieldOptions.find(f => f.value === this.selectedField);
        
        return {
            object: this.selectedObject,
            field: this.selectedField,
            fieldLabel: fieldInfo ? fieldInfo.label : '',
            dataType: fieldInfo ? fieldInfo.dataType : ''
        };
    }
}
