public inherited sharing class dps_f_FormDefinition {
    public class FieldBinding {
        public String key { get; private set; }
        public Schema.SObjectField field { get; private set; }

        private FieldBinding(String key, Schema.SObjectField field) {
            this.key = key;
            this.field = field;
        }
    }

    public String key { get; private set; }
    public Schema.SObjectType primaryObject { get; private set; }
    public Schema.SObjectType childObject { get; private set; }
    public Schema.SObjectField childRelationship { get; private set; }
    public List<FieldBinding> primaryFields { get; private set; }
    public List<FieldBinding> childFields { get; private set; }

    private dps_f_FormDefinition(
        String key,
        Schema.SObjectType primaryObject,
        Schema.SObjectType childObject,
        Schema.SObjectField childRelationship,
        List<FieldBinding> primaryFields,
        List<FieldBinding> childFields
    ) {
        this.key = key;
        this.primaryObject = primaryObject;
        this.childObject = childObject;
        this.childRelationship = childRelationship;
        this.primaryFields = primaryFields;
        this.childFields = childFields;
    }

    public static dps_f_FormDefinition resolve(String formKey) {
        if (formKey != 'accountContacts') {
            return null;
        }

        return new dps_f_FormDefinition(
            'accountContacts',
            Account.SObjectType,
            Contact.SObjectType,
            Contact.AccountId,
            new List<FieldBinding>{
                new FieldBinding('primary.name', Account.Name),
                new FieldBinding('primary.phone', Account.Phone),
                new FieldBinding('primary.billingStreet', Account.BillingStreet),
                new FieldBinding('primary.billingCity', Account.BillingCity),
                new FieldBinding('primary.billingPostalCode', Account.BillingPostalCode)
            },
            new List<FieldBinding>{
                new FieldBinding('child.firstName', Contact.FirstName),
                new FieldBinding('child.lastName', Contact.LastName),
                new FieldBinding('child.email', Contact.Email),
                new FieldBinding('child.phone', Contact.Phone),
                new FieldBinding('child.mailingStreet', Contact.MailingStreet),
                new FieldBinding('child.mailingCity', Contact.MailingCity),
                new FieldBinding('child.mailingPostalCode', Contact.MailingPostalCode)
            }
        );
    }
}
