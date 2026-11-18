import { LightningElement, api } from 'lwc';
import load from '@salesforce/apex/dps_f_FormController.load';
import save from '@salesforce/apex/dps_f_FormController.save';
import { applyValueRules, formEvaluators, matches } from 'c/dps_f_rules';

function fieldValues(fields) {
    return Object.fromEntries(fields.map(field => {
        const { value, kind } = field;
        if (value === '' || value == null) {
            return [field.key, null];
        }
        if (kind === 'number') {
            return [field.key, Number(value)];
        }
        return [field.key, kind === 'booleanRadio' ? value === true || value === 'true' : value];
    }));
}

function withClientFields(row, scope) {
    return {
        ...row,
        fields: [
            ...scope.clientFields.map(field => ({ ...field, clientOnly: true, layoutClass: 'field field-wide' })),
            ...row.fields.map(field => ({
                ...field,
                layoutClass: field.wide ? 'field field-wide' : field.addressGroup ? 'field address-part' : 'field'
            }))
        ]
    };
}

function evaluateRow(row, scope, parentValues, changed) {
    const values = { ...parentValues, ...fieldValues(row.fields) };
    const { draft, writes } = applyValueRules(scope.valueRules, values, changed, formEvaluators);
    return {
        ...row,
        fields: row.fields.map(field => {
            const policy = scope.policies[field.key];
            const hidden = Boolean(policy?.visibleWhen && !matches(policy.visibleWhen, draft, formEvaluators));
            const ruleLocked = matches(policy?.readOnlyWhen, draft, formEvaluators);
            return {
                ...field,
                value: writes.has(field.key) ? draft[field.key] : field.value,
                derived: writes.has(field.key) || field.derived,
                hidden,
                visible: !hidden,
                ruleLocked,
                isDisabled: field.disabled || ruleLocked,
                isRequired: field.required || matches(policy?.requiredWhen, draft, formEvaluators)
            };
        })
    };
}

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
        const { primaryRules, childRules, primary, children, childTemplate } = this.form;
        this.form.primary = evaluateRow(withClientFields(primary, primaryRules), primaryRules, {}, []);
        const primaryValues = fieldValues(this.form.primary.fields);
        this.form.childTemplate = withClientFields(childTemplate, childRules);
        this.rows = children.map(row =>
            evaluateRow(withClientFields({ ...row, rowKey: row.id }, childRules), childRules, primaryValues, []));
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
        const row = {
            ...this.form.childTemplate,
            rowKey: `new-${++this.nextRow}`
        };
        this.rows = [...this.rows,
            evaluateRow(row, this.form.childRules, fieldValues(this.form.primary.fields), [])];
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
        const id = event.currentTarget.dataset.row;
        this.removed = this.removed.filter(removedId => removedId !== id);
        const primaryValues = fieldValues(this.form.primary.fields);
        this.rows = this.rows.map(row => row.id === id
            ? evaluateRow(row, this.form.childRules, primaryValues, Object.keys(primaryValues)) : row);
    }

    changeField(event) {
        const { row, field } = event.currentTarget.dataset;
        const value = event.detail;
        const update = item => ({
            ...item,
            fields: item.fields.map(input => input.key === field
                ? { ...input, value, changed: true, derived: false }
                : input)
        });
        if (row) {
            const primaryValues = fieldValues(this.form.primary.fields);
            this.rows = this.rows.map(item => item.rowKey === row
                ? evaluateRow(update(item), this.form.childRules, primaryValues, [field]) : item);
        } else {
            const previous = fieldValues(this.form.primary.fields);
            const primary = evaluateRow(update(this.form.primary), this.form.primaryRules, {}, [field]);
            this.form = { ...this.form, primary };
            const primaryValues = fieldValues(primary.fields);
            const changed = Object.keys(primaryValues).filter(key => !Object.is(primaryValues[key], previous[key]));
            this.rows = this.rows.map(item => this.removed.includes(item.id) ? item
                : evaluateRow(item, this.form.childRules, primaryValues, changed));
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
            values: Object.fromEntries(row.fields
                .filter(field => !field.clientOnly && !field.isDisabled && !field.hidden &&
                    (field.changed || field.derived))
                .map(field => [field.key, field.value === '' || field.value == null ? null : String(field.value)])),
            clientValues: Object.fromEntries(row.fields.filter(field => field.clientOnly && field.changed)
                .map(field => [field.key, field.value]))
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
