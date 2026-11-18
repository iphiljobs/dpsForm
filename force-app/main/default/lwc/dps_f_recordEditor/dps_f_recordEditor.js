import { LightningElement, api } from 'lwc';
import load from '@salesforce/apex/dps_f_FormController.load';
import save from '@salesforce/apex/dps_f_FormController.save';

export default class DpsFRecordEditor extends LightningElement {
    @api formKey = 'accountContacts';
    @api recordId;
    @api columns = '1';

    form;
    rows = [];
    removed = [];
    busy = false;
    error;
    notice;
    nextRow = 0;

    connectedCallback() {
        this.loadForm();
    }

    async loadForm() {
        this.busy = true;
        this.error = undefined;
        try {
            this.setForm(await load({ formKey: this.formKey, recordId: this.recordId || null }));
        } catch (error) {
            this.error = error.body?.message || 'Unable to load the form.';
        } finally {
            this.busy = false;
        }
    }

    setForm(result) {
        this.form = JSON.parse(result);
        for (const row of [this.form.primary, this.form.childTemplate, ...this.form.children]) {
            for (const field of row.fields) {
                field.layoutClass = field.wide ? 'field field-wide'
                    : field.addressGroup ? 'field address-part' : 'field';
            }
        }
        this.rows = this.form.children.map(row => ({ ...row, rowKey: row.id }));
        this.removed = [];
    }

    get fieldGridClass() {
        return String(this.columns) === '2' ? 'field-grid two-columns' : 'field-grid';
    }

    get activeRows() {
        return this.rows.filter(row => !this.removed.includes(row.id));
    }

    get removedRows() {
        return this.rows.filter(row => this.removed.includes(row.id));
    }

    get disableAdd() {
        return this.busy || this.rows.length >= 200;
    }

    addRow() {
        this.rows = [...this.rows, {
            rowKey: `new-${++this.nextRow}`,
            fields: this.form.childTemplate.fields.map(field => ({ ...field }))
        }];
    }

    removeRow(event) {
        const rowKey = event.currentTarget.dataset.row;
        const row = this.rows.find(item => item.rowKey === rowKey);
        if (row.id) {
            this.removed = [...this.removed, row.id];
        } else {
            this.rows = this.rows.filter(item => item !== row);
        }
    }

    undoRemove(event) {
        this.removed = this.removed.filter(id => id !== event.currentTarget.dataset.row);
    }

    changeField(event) {
        const { row, field } = event.currentTarget.dataset;
        const value = event.detail;
        const update = item => ({
            ...item,
            fields: item.fields.map(input => input.key === field
                ? { ...input, value, changed: true }
                : input)
        });
        if (row) {
            this.rows = this.rows.map(item => item.rowKey === row ? update(item) : item);
        } else {
            this.form = { ...this.form, primary: update(this.form.primary) };
        }
    }

    handleUpload(event) {
        const count = event.detail.files.length;
        this.notice = count === 1 ? 'File uploaded.' : `${count} files uploaded.`;
    }

    async saveForm() {
        if (this.busy) {
            return;
        }
        const validity = [...this.template.querySelectorAll('c-dps_f_field')]
            .map(input => input.reportValidity());
        if (validity.includes(false)) {
            return;
        }
        this.busy = true;
        this.error = undefined;
        this.notice = undefined;
        const serialize = row => ({
            id: row.id || null,
            values: Object.fromEntries(row.fields.filter(field => field.changed)
                .map(field => [field.key, field.value === '' || field.value == null ? null : String(field.value)]))
        });
        try {
            const payload = JSON.stringify({
                primary: serialize(this.form.primary),
                children: this.activeRows.map(serialize),
                removed: this.removed
            });
            this.setForm(await save({ formKey: this.formKey, payload }));
            this.notice = 'Changes saved.';
        } catch (error) {
            this.error = error.body?.message || 'Unable to save the form.';
        } finally {
            this.busy = false;
        }
    }
}
