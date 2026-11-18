@IsTest
private class dps_f_FormControllerTest {
    @IsTest
    static void createsLoadsAndDeletesChildRows() {
        String created = dps_f_FormController.save(
            'accountContacts',
            '{"primary":{"values":{"primary.name":"Editor test"}},' +
            '"children":[{"values":{"child.lastName":"Example"}}],"removed":[]}'
        );
        Map<String, Object> form = (Map<String, Object>) JSON.deserializeUntyped(created);
        Map<String, Object> primary = (Map<String, Object>) form.get('primary');
        Id parentId = (Id) (String) primary.get('id');
        List<Contact> children = [SELECT Id, LastName FROM Contact WHERE AccountId = :parentId];
        System.assertEquals(1, children.size());
        System.assertEquals('Example', children[0].LastName);
        String loaded = dps_f_FormController.load('accountContacts', parentId);
        System.assert(loaded.contains('child.lastName'));
        System.assert(!loaded.contains('AccountId'));

        dps_f_FormController.save(
            'accountContacts',
            JSON.serialize(new Map<String, Object>{
                'primary' => new Map<String, Object>{
                    'id' => parentId, 'values' => new Map<String, String>()
                },
                'children' => new List<Object>(),
                'removed' => new List<Id>{children[0].Id}
            })
        );
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE AccountId = :parentId]);
    }

    @IsTest
    static void savesTypedValues() {
        String result = dps_f_FormController.save(
            'accountContacts',
            '{"primary":{"values":{"primary.name":"Types","primary.employees":"17"}},' +
            '"children":[{"values":{"child.lastName":"Types","child.birthDate":"2000-02-29",' +
            '"child.emailOptOut":"false","child.faxOptOut":"true"}}],"removed":[]}'
        );
        Account record = [SELECT NumberOfEmployees FROM Account WHERE Name = 'Types'];
        Contact child = [
            SELECT Birthdate, HasOptedOutOfEmail, HasOptedOutOfFax FROM Contact
            WHERE AccountId = :record.Id
        ];
        System.assertEquals(17, record.NumberOfEmployees);
        System.assertEquals(Date.newInstance(2000, 2, 29), child.Birthdate);
        System.assertEquals(false, child.HasOptedOutOfEmail);
        System.assertEquals(true, child.HasOptedOutOfFax);
        System.assert(result.contains('booleanRadio'));
        System.assert(result.contains('primaryFiles'));
    }

    @IsTest
    static void derivesMailingFromBillingAndRejectsLockedInput() {
        Account parent = new Account(Name = 'Address rule', BillingCity = 'Oldsmar');
        insert parent;
        Contact mirrored = new Contact(LastName = 'Mirror', AccountId = parent.Id, MailingCity = 'Tampa');
        Contact independent = new Contact(LastName = 'Independent', AccountId = parent.Id, MailingCity = 'Lutz');
        insert new List<Contact>{mirrored, independent};

        String prefix = '{"primary":{"id":"' + parent.Id +
            '","values":{"primary.billingCity":"Clearwater"}},"children":[{"id":"' +
            mirrored.Id + '","clientValues":{"client.sameAsBilling":true},"values":';
        String suffix = '},{"id":"' + independent.Id + '","values":{}}],"removed":[]}';
        dps_f_FormController.save('accountContacts', prefix + '{}' + suffix);
        Map<Id, Contact> saved = new Map<Id, Contact>([
            SELECT Id, MailingCity FROM Contact WHERE AccountId = :parent.Id
        ]);
        System.assertEquals('Clearwater', saved.get(mirrored.Id).MailingCity);
        System.assertEquals('Lutz', saved.get(independent.Id).MailingCity);

        try {
            dps_f_FormController.save('accountContacts', prefix + '{"child.mailingCity":"Tampa"}' + suffix);
            System.assert(false, 'A protected field must reject direct input.');
        } catch (AuraHandledException expected) {
            System.assertEquals('Clearwater', [SELECT MailingCity FROM Contact WHERE Id = :mirrored.Id].MailingCity);
        }
    }

    @IsTest
    static void rollsBackParentOnInvalidChild() {
        try {
            dps_f_FormController.save(
                'accountContacts',
                '{"primary":{"values":{"primary.name":"Rollback test"}},' +
                '"children":[{"values":{}}],"removed":[]}'
            );
            System.assert(false, 'The save should fail.');
        } catch (AuraHandledException expected) {
            System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Rollback test']);
        }
    }
}
