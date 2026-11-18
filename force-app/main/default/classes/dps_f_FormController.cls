public with sharing class dps_f_FormController {
    private class Draft {
        public Id id;
        public Map<String, String> values;
    }

    private class Submission {
        public Draft primary;
        public List<Draft> children;
        public Set<Id> removed;
    }

    @AuraEnabled
    public static String load(String formKey, Id recordId) {
        try {
            return JSON.serialize(readForm(definition(formKey), recordId));
        } catch (Exception error) {
            throw new AuraHandledException('Unable to load the form. Check your record access and form configuration.');
        }
    }

    @AuraEnabled
    public static String save(String formKey, String payload) {
        Savepoint beforeSave = Database.setSavepoint();
        try {
            dps_f_FormDefinition form = definition(formKey);
            Submission draft = (Submission) JSON.deserialize(payload, Submission.class);
            Id parentId = draft.primary.id;
            Boolean creating = parentId == null;
            if (draft.children.size() + draft.removed.size() > 200 ||
                (!creating && parentId.getSObjectType() != form.primaryObject)) {
                throw new IllegalArgumentException();
            }

            Set<Id> submitted = new Set<Id>();
            submitted.addAll(draft.removed);
            for (Draft row : draft.children) {
                if (row.id != null && !submitted.add(row.id)) {
                    throw new IllegalArgumentException();
                }
            }
            String relation = form.childRelationship.getDescribe().getName();
            if (!submitted.isEmpty()) {
                if (creating) {
                    throw new IllegalArgumentException();
                }
                List<SObject> linked = Database.queryWithBinds(
                    'SELECT Id FROM ' + form.childObject.getDescribe().getName() +
                    ' WHERE Id IN :submitted AND ' + relation + ' = :parentId FOR UPDATE',
                    new Map<String, Object>{'parentId' => parentId, 'submitted' => submitted},
                    AccessLevel.USER_MODE
                );
                if (linked.size() != submitted.size()) {
                    throw new IllegalArgumentException();
                }
            }

            SObject primaryRecord = mappedRecord(form.primaryObject, form.primaryFields, draft.primary);
            if (creating) {
                Database.insert(primaryRecord, AccessLevel.USER_MODE);
                parentId = (Id) primaryRecord.get('Id');
            } else if (!draft.primary.values.isEmpty()) {
                Database.update(primaryRecord, AccessLevel.USER_MODE);
            } else {
                readPrimary(form, parentId);
            }

            List<SObject> inserts = new List<SObject>();
            List<SObject> updates = new List<SObject>();
            List<SObject> deletes = new List<SObject>();
            for (Draft row : draft.children) {
                SObject child = mappedRecord(form.childObject, form.childFields, row);
                if (row.id == null) {
                    child.put(form.childRelationship, parentId);
                    inserts.add(child);
                } else if (!row.values.isEmpty()) {
                    updates.add(child);
                }
            }
            for (Id removedId : draft.removed) {
                deletes.add(form.childObject.newSObject(removedId));
            }
            if (!deletes.isEmpty()) {
                Database.delete(deletes, true, AccessLevel.USER_MODE);
            }
            if (!inserts.isEmpty()) {
                Database.insert(inserts, true, AccessLevel.USER_MODE);
            }
            if (!updates.isEmpty()) {
                Database.update(updates, true, AccessLevel.USER_MODE);
            }
            return JSON.serialize(readForm(form, parentId));
        } catch (Exception error) {
            Database.rollback(beforeSave);
            throw new AuraHandledException('Unable to save the form. Check the values and your record permissions.');
        }
    }

    private static dps_f_FormDefinition definition(String formKey) {
        dps_f_FormDefinition form = dps_f_FormDefinition.resolve(formKey);
        if (form == null) {
            throw new IllegalArgumentException();
        }
        return form;
    }

    private static SObject mappedRecord(
        Schema.SObjectType objectType,
        List<dps_f_FormDefinition.FieldBinding> fields,
        Draft draft
    ) {
        SObject record = objectType.newSObject(draft.id);
        Map<String, Schema.SObjectField> allowed = new Map<String, Schema.SObjectField>();
        for (dps_f_FormDefinition.FieldBinding binding : fields) {
            allowed.put(binding.key, binding.field);
        }
        for (String key : draft.values.keySet()) {
            if (!allowed.containsKey(key)) {
                throw new IllegalArgumentException();
            }
            record.put(allowed.get(key), draft.values.get(key));
        }
        return record;
    }

    private static Map<String, Object> readForm(dps_f_FormDefinition form, Id recordId) {
        SObject primaryRecord = recordId == null ? null : readPrimary(form, recordId);
        List<Object> children = new List<Object>();
        if (recordId != null) {
            String relation = form.childRelationship.getDescribe().getName();
            for (SObject child : Database.queryWithBinds(
                selectFields(form.childObject, form.childFields) +
                ' WHERE ' + relation + ' = :recordId ORDER BY Id LIMIT 201',
                new Map<String, Object>{'recordId' => recordId},
                AccessLevel.USER_MODE
            )) {
                children.add(present(child, form.childFields));
            }
        }
        if (children.size() > 200) {
            throw new IllegalArgumentException();
        }
        return new Map<String, Object>{
            'primary' => present(primaryRecord, form.primaryFields),
            'primaryLabel' => form.primaryObject.getDescribe().getLabel(),
            'childLabel' => form.childObject.getDescribe().getLabel(),
            'childrenLabel' => form.childObject.getDescribe().getLabelPlural(),
            'childTemplate' => present(null, form.childFields),
            'children' => children
        };
    }

    private static SObject readPrimary(dps_f_FormDefinition form, Id recordId) {
        if (recordId.getSObjectType() != form.primaryObject) {
            throw new IllegalArgumentException();
        }
        return Database.queryWithBinds(
            selectFields(form.primaryObject, form.primaryFields) + ' WHERE Id = :recordId',
            new Map<String, Object>{'recordId' => recordId},
            AccessLevel.USER_MODE
        )[0];
    }

    private static String selectFields(
        Schema.SObjectType objectType, List<dps_f_FormDefinition.FieldBinding> fields
    ) {
        List<String> names = new List<String>{'Id'};
        for (dps_f_FormDefinition.FieldBinding binding : fields) {
            Schema.DescribeFieldResult field = binding.field.getDescribe();
            if (field.isAccessible()) {
                names.add(field.getName());
            }
        }
        return 'SELECT ' + String.join(names, ',') + ' FROM ' + objectType.getDescribe().getName();
    }

    private static Map<String, Object> present(
        SObject record, List<dps_f_FormDefinition.FieldBinding> fields
    ) {
        List<Object> controls = new List<Object>();
        for (dps_f_FormDefinition.FieldBinding binding : fields) {
            Schema.DescribeFieldResult field = binding.field.getDescribe();
            if (!field.isAccessible()) {
                continue;
            }
            Boolean editable = record == null ? field.isCreateable() : field.isUpdateable();
            String kind = 'text';
            if (field.getType() == Schema.DisplayType.Email) {
                kind = 'email';
            } else if (field.getType() == Schema.DisplayType.Phone) {
                kind = 'tel';
            }
            controls.add(new Map<String, Object>{
                'key' => binding.key, 'label' => field.getLabel(), 'kind' => kind,
                'disabled' => !editable,
                'required' => editable && !field.isNillable() && !field.isDefaultedOnCreate(),
                'value' => record == null ? null : record.get(binding.field)
            });
        }
        return new Map<String, Object>{
            'id' => record == null ? null : record.get('Id'), 'fields' => controls
        };
    }
}
