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
