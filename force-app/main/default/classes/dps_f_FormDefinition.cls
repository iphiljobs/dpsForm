public inherited sharing class dps_f_FormDefinition {
    public class FieldBinding {
        public String key { get; private set; }
        public Schema.SObjectField field { get; private set; }

        public String presentation { get; private set; }
        public String addressGroup { get; private set; }

        private FieldBinding(String key, Schema.SObjectField field) {
            this(key, field, null, null);
        }

        private FieldBinding(String key, Schema.SObjectField field, String presentation, String addressGroup) {
            this.key = key;
            this.field = field;
            this.presentation = presentation;
            this.addressGroup = addressGroup;
        }
    }

    public String key { get; private set; }
    public Schema.SObjectType primaryObject { get; private set; }
    public Schema.SObjectType childObject { get; private set; }
    public Schema.SObjectField childRelationship { get; private set; }
    public List<FieldBinding> primaryFields { get; private set; }
    public List<FieldBinding> childFields { get; private set; }

    public dps_f_RuleEngine.Scope primaryRules { get; private set; }
    public dps_f_RuleEngine.Scope childRules { get; private set; }

    public String primaryFiles { get; private set; }
    public String childFiles { get; private set; }

    private dps_f_FormDefinition(
        String key,
        Schema.SObjectType primaryObject,
        Schema.SObjectType childObject,
        Schema.SObjectField childRelationship,
        List<FieldBinding> primaryFields,
        List<FieldBinding> childFields,
        String primaryFiles,
        String childFiles
    ) {
        this.key = key;
        this.primaryObject = primaryObject;
        this.childObject = childObject;
        this.childRelationship = childRelationship;
        this.primaryFields = primaryFields;
        this.childFields = childFields;
        this.primaryFiles = primaryFiles;
        this.childFiles = childFiles;
        this.primaryRules = new dps_f_RuleEngine.Scope();
        this.childRules = new dps_f_RuleEngine.Scope();
    }

    public static dps_f_FormDefinition resolve(String formKey) {
        if (formKey != 'accountContacts') {
            return null;
        }

        dps_f_FormDefinition form = new dps_f_FormDefinition(
            'accountContacts',
            Account.SObjectType,
            Contact.SObjectType,
            Contact.AccountId,
            new List<FieldBinding>{
                new FieldBinding('primary.name', Account.Name),
                new FieldBinding('primary.phone', Account.Phone),
                new FieldBinding('primary.website', Account.Website),
                new FieldBinding('primary.employees', Account.NumberOfEmployees),
                new FieldBinding('primary.industry', Account.Industry),
                new FieldBinding('primary.rating', Account.Rating, 'radio', null),
                new FieldBinding('primary.parent', Account.ParentId, 'lookup', null),
                new FieldBinding('primary.billingStreet', Account.BillingStreet, 'textarea', 'billing'),
                new FieldBinding('primary.billingCity', Account.BillingCity, null, 'billing'),
                new FieldBinding('primary.billingState', Account.BillingState, null, 'billing'),
                new FieldBinding('primary.billingPostalCode', Account.BillingPostalCode, null, 'billing'),
                new FieldBinding('primary.billingCountry', Account.BillingCountry, null, 'billing')
            },
            new List<FieldBinding>{
                new FieldBinding('child.firstName', Contact.FirstName),
                new FieldBinding('child.lastName', Contact.LastName),
                new FieldBinding('child.email', Contact.Email),
                new FieldBinding('child.phone', Contact.Phone),
                new FieldBinding('child.birthDate', Contact.Birthdate),
                new FieldBinding('child.emailOptOut', Contact.HasOptedOutOfEmail),
                new FieldBinding('child.faxOptOut', Contact.HasOptedOutOfFax, 'booleanRadio', null),
                new FieldBinding('child.mailingStreet', Contact.MailingStreet, 'textarea', 'mailing'),
                new FieldBinding('child.mailingCity', Contact.MailingCity, null, 'mailing'),
                new FieldBinding('child.mailingState', Contact.MailingState, null, 'mailing'),
                new FieldBinding('child.mailingPostalCode', Contact.MailingPostalCode, null, 'mailing'),
                new FieldBinding('child.mailingCountry', Contact.MailingCountry, null, 'mailing')
            },
            System.Label.dps_f_PrimaryFiles,
            System.Label.dps_f_ChildFiles
        );
        form.configureMailingRules();
        return form;
    }

    private void configureMailingRules() {
        String toggle = 'client.sameAsBilling';
        childRules.clientFields.add(new dps_f_RuleEngine.ClientField(toggle, System.Label.dps_f_SameAsBilling));
        dps_f_RuleEngine.Condition enabled = new dps_f_RuleEngine.Condition(toggle, 'equals', true);
        dps_f_RuleEngine.ValueRule mirror = new dps_f_RuleEngine.ValueRule();
        mirror.condition = enabled;
        mirror.actions = new List<dps_f_RuleEngine.Action>();
        for (String part : new List<String>{'Street', 'City', 'State', 'PostalCode', 'Country'}) {
            String source = 'primary.billing' + part;
            String target = 'child.mailing' + part;
            dps_f_RuleEngine.Policy policy = new dps_f_RuleEngine.Policy();
            policy.readOnlyWhen = enabled;
            childRules.policies.put(target, policy);
            mirror.actions.add(new dps_f_RuleEngine.Action(source, target));
        }
        childRules.valueRules.add(mirror);
    }
}
