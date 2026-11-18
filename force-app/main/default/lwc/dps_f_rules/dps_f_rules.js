const blank = value =>
    value == null ||
    (typeof value === 'string' && value.trim().length === 0) ||
    (Array.isArray(value) && value.length === 0);

const contains = (value, expected) => {
    if (Array.isArray(value)) {
        return value.includes(expected);
    }
    return typeof value === 'string' && typeof expected === 'string' &&
        value.includes(expected);
};

const comparable = (left, right) =>
    typeof left === typeof right &&
    (typeof left === 'number' || typeof left === 'string');

const operators = new Map([
    ['equals', (value, expected) => value === expected],
    ['notEquals', (value, expected) => value !== expected],
    ['contains', contains],
    ['notContains', (value, expected) => !contains(value, expected)],
    ['isBlank', blank],
    ['isNotBlank', value => !blank(value)],
    ['greaterThan', (value, expected) => comparable(value, expected) && value > expected],
    ['lessThan', (value, expected) => comparable(value, expected) && value < expected]
]);

export function matches(condition, values, evaluators = new Map()) {
    if (!condition) {
        return false;
    }
    if (Array.isArray(condition.conditions)) {
        const evaluate = child => matches(child, values, evaluators);
        return condition.logic === 'OR'
            ? condition.conditions.some(evaluate)
            : condition.conditions.every(evaluate);
    }
    if (condition.method) {
        const evaluate = evaluators.get(condition.method);
        try {
            return evaluate?.(condition.args ?? {}, values, condition.dependsOn ?? []) === true;
        } catch {
            return false;
        }
    }
    return operators.get(condition.operator)?.(values[condition.field], condition.value) ?? false;
}

export const formEvaluators = new Map([
    ['allPopulated', (_args, values, dependencies) =>
        dependencies.length > 0 && dependencies.every(key => !blank(values[key]))]
]);

export function applyValueRules(rules, values, changedFields, evaluators) {
    const draft = Object.assign(Object.create(null), values);
    const changed = new Set(typeof changedFields === 'string' ? [changedFields] : changedFields);
    const writes = new Map();

    function write(field, value) {
        if (Object.is(draft[field], value) && value !== null) {
            return;
        }
        draft[field] = value;
        writes.set(field, value);
        changed.add(field);
    }

    for (const { condition, when = condition, actions } of rules) {
        const controls = conditionFields(when);
        const triggered = controls.some(field => changed.has(field)) ||
            actions.some(action => action.type === 'copy' && changed.has(action.fromKey ?? action.from));
        if (!triggered || !matches(when, draft, evaluators)) {
            continue;
        }
        for (const action of actions) {
            if (action.type === 'clear') {
                for (const field of action.fields) {
                    write(field, null);
                }
            } else if (action.type === 'copy') {
                const from = action.fromKey ?? action.from;
                const to = action.toKey ?? action.to;
                if (Object.hasOwn(draft, from) && (action.overwrite || blank(draft[to]))) {
                    write(to, draft[from]);
                }
            }
        }
    }
    return { draft, writes };
}

function conditionFields(condition) {
    if (Array.isArray(condition.conditions)) {
        return condition.conditions.flatMap(conditionFields);
    }
    if (condition.method) {
        return condition.dependsOn ?? [];
    }
    return [condition.field];
}
