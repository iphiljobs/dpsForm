import { LightningElement, api } from 'lwc';
import lookup from '@salesforce/apex/dps_f_FormController.lookup';

export default class DpsFField extends LightningElement {
    @api field;
    @api formKey;
    @api busy;

    options = [];
    lookupError;
    term = '';
    requestNumber = 0;

    connectedCallback() {
        if (this.isLookup && this.field.value) {
            this.loadOptions({ selectedId: this.field.value });
        }
    }

    get disabled() { return this.busy || this.field.disabled; }
    get isLookup() { return this.field.kind === 'lookup'; }
    get isCheckbox() { return this.field.kind === 'checkbox'; }
    get isTextarea() { return this.field.kind === 'textarea'; }
    get isPicklist() { return this.field.kind === 'picklist'; }
    get isRadio() { return this.field.kind === 'radio' || this.field.kind === 'booleanRadio'; }
    get radioValue() {
        return this.field.value == null ? undefined : String(this.field.value);
    }
    get lookupOptions() {
        return this.field.required ? this.options : [{ label: 'None', value: '' }, ...this.options];
    }
    get picklistOptions() {
        return this.field.required ? this.field.options : [{ label: 'None', value: '' }, ...this.field.options];
    }

    change(event) {
        const value = this.isCheckbox ? event.target.checked
            : event.detail?.value ?? event.target.value;
        if (this.isLookup) {
            this.selectedOption = this.options.find(option => option.value === value);
        }
        this.dispatchEvent(new CustomEvent('valuechange', { detail: value }));
    }

    search(event) {
        this.term = event.target.value;
        const term = this.term.trim();
        if (term.length < 2) {
            this.requestNumber++;
            this.options = this.selectedOption ? [this.selectedOption] : [];
            this.lookupError = undefined;
            return;
        }
        this.loadOptions({ term });
    }

    async loadOptions({ term = null, selectedId = null }) {
        const request = ++this.requestNumber;
        this.lookupError = undefined;
        try {
            const options = JSON.parse(await lookup({
                formKey: this.formKey, fieldKey: this.field.key, term, selectedId
            }));
            if (request !== this.requestNumber) {
                return;
            }
            if (selectedId) {
                [this.selectedOption] = options;
            }
            this.options = this.selectedOption &&
                !options.some(option => option.value === this.selectedOption.value)
                ? [this.selectedOption, ...options]
                : options;
        } catch (error) {
            if (request === this.requestNumber) {
                this.lookupError = error.body?.message || 'Unable to search records.';
            }
        }
    }

    @api
    reportValidity() {
        const control = this.template.querySelector('[data-control]');
        control?.reportValidity();
        return control?.checkValidity() ?? true;
    }
}
