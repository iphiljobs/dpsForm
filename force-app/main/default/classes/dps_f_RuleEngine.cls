public inherited sharing class dps_f_RuleEngine {
    public class Condition {
        public String field;
        public String operator;
        public Object value;
        public String logic;
        public List<Condition> conditions;
        public String method;
        public Map<String, Object> args;
        public List<String> dependsOn;

        public Condition() {}

        public Condition(String field, String operator, Object value) {
            this.field = field;
            this.operator = operator;
            this.value = value;
        }
    }

    public class Policy {
        public Condition visibleWhen;
        public Condition requiredWhen;
        public Condition readOnlyWhen;
    }

    public class Action {
        public String type;
        public String fromKey;
        public String toKey;
        public List<String> fields;
        public Boolean overwrite;

        public Action(String source, String target) {
            type = 'copy';
            fromKey = source;
            toKey = target;
            overwrite = true;
        }
    }

    public class ValueRule {
        public Condition condition;
        public List<Action> actions;
    }

    public class ClientField {
        public String key;
        public String label;
        public String kind = 'checkbox';
        public Boolean value = false;

        public ClientField(String key, String label) {
            this.key = key;
            this.label = label;
        }
    }

    public class Scope {
        public List<ClientField> clientFields = new List<ClientField>();
        public Map<String, Policy> policies = new Map<String, Policy>();
        public List<ValueRule> valueRules = new List<ValueRule>();
        public Boolean clearWhenHidden = false;
    }

    public static Boolean matches(Condition condition, Map<String, Object> values) {
        if (condition == null) {
            return false;
        }
        if (condition.conditions != null) {
            Boolean isOrGroup = condition.logic == 'OR';
            for (Condition child : condition.conditions) {
                if (matches(child, values) == isOrGroup) {
                    return isOrGroup;
                }
            }
            return !isOrGroup;
        }
        if (condition.method != null) {
            return evaluateNamed(condition, values);
        }
        Object actual = values.get(condition.field);
        Object expected = condition.value;
        switch on condition.operator {
            when 'equals' { return equalValues(actual, expected); }
            when 'notEquals' { return !equalValues(actual, expected); }
            when 'isBlank' { return isBlank(actual); }
            when 'isNotBlank' { return !isBlank(actual); }
            when 'contains', 'notContains' {
                Boolean containsValue = actual instanceof String && expected instanceof String &&
                    ((String) actual).contains((String) expected);
                return condition.operator == 'contains' ? containsValue : !containsValue;
            }
            when 'greaterThan', 'lessThan' {
                if (actual == null || expected == null) {
                    return false;
                }
                Integer comparison;
                if (isNumber(actual) && isNumber(expected)) {
                    Decimal left = Decimal.valueOf(String.valueOf(actual));
                    Decimal right = Decimal.valueOf(String.valueOf(expected));
                    comparison = left == right ? 0 : (left > right ? 1 : -1);
                } else if (actual instanceof String && expected instanceof String) {
                    comparison = ((String) actual).compareTo((String) expected);
                } else {
                    return false;
                }
                return condition.operator == 'greaterThan' ? comparison > 0 : comparison < 0;
            }
            when else { return false; }
        }
    }

    private static Boolean evaluateNamed(Condition condition, Map<String, Object> values) {
        if (condition.method != 'allPopulated' || condition.dependsOn == null ||
            condition.dependsOn.isEmpty()) {
            return false;
        }
        for (String key : condition.dependsOn) {
            if (isBlank(values.get(key))) {
                return false;
            }
        }
        return true;
    }

    public static Object conditionValue(Object value) {
        if (value instanceof Id) {
            return String.valueOf(value);
        }
        if (value instanceof Date || value instanceof Datetime || value instanceof Time) {
            return JSON.deserializeUntyped(JSON.serialize(value));
        }
        return value;
    }

    private static Boolean isNumber(Object value) {
        return value instanceof Integer || value instanceof Long || value instanceof Double ||
            value instanceof Decimal;
    }

    public static Boolean equalValues(Object actual, Object expected) {
        if (actual instanceof String && expected instanceof String) {
            return ((String) actual).equals((String) expected);
        }
        if (isNumber(actual) && isNumber(expected)) {
            return Decimal.valueOf(String.valueOf(actual)) == Decimal.valueOf(String.valueOf(expected));
        }
        return actual == expected;
    }

    public static Boolean isBlank(Object value) {
        return value == null || (value instanceof String && String.isBlank((String) value));
    }

    public static Set<String> apply(Scope scope, Map<String, Object> values, Set<String> changed) {
        Set<String> writes = new Set<String>();
        for (ValueRule rule : scope.valueRules) {
            Boolean triggered = affected(rule.condition, changed);
            for (Action action : rule.actions) {
                triggered = triggered || (action.type == 'copy' && changed.contains(action.fromKey));
            }
            if (!triggered || !matches(rule.condition, values)) {
                continue;
            }
            for (Action action : rule.actions) {
                if (action.type == 'clear') {
                    for (String key : action.fields) {
                        writeValue(key, null, values, changed, writes);
                    }
                } else if (action.type == 'copy' && values.containsKey(action.fromKey) &&
                    (action.overwrite == true || isBlank(values.get(action.toKey)))) {
                    writeValue(action.toKey, values.get(action.fromKey), values, changed, writes);
                }
            }
        }
        return writes;
    }

    private static Boolean affected(Condition condition, Set<String> changed) {
        if (condition.conditions != null) {
            for (Condition child : condition.conditions) {
                if (affected(child, changed)) {
                    return true;
                }
            }
            return false;
        }
        if (condition.method != null && condition.dependsOn != null) {
            for (String field : condition.dependsOn) {
                if (changed.contains(field)) {
                    return true;
                }
            }
            return false;
        }
        return changed.contains(condition.field);
    }

    private static void writeValue(String key, Object value, Map<String, Object> values,
        Set<String> changed, Set<String> writes) {
        if (value != null && equalValues(values.get(key), value)) {
            return;
        }
        values.put(key, value);
        changed.add(key);
        writes.add(key);
    }
}
