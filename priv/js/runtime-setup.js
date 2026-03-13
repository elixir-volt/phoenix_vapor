// Phoenix Vapor reactive runtime bootstrap.
// Loaded once per context, then configured via __pv_setup(config).

(function () {
  const { ref, computed, toRaw } = VueReactivity;

  function unwrap(v) {
    const raw = toRaw(v);
    if (Array.isArray(raw)) return raw.slice();
    if (raw && typeof raw === "object") return Object.assign({}, raw);
    return raw;
  }

  function snapshot(v) {
    if (Array.isArray(v)) return v.slice();
    if (v && typeof v === "object") return Object.assign({}, v);
    return v;
  }

  globalThis.__pv_setup = function (config) {
    const refs = {};
    const computedRefs = {};
    const handlers = {};

    for (const [name, initExpr] of Object.entries(config.refs || {})) {
      refs[name] = ref(new Function("return " + initExpr)());
    }

    for (const [name, expr] of Object.entries(config.computeds || {})) {
      const allRefs = { ...refs, ...computedRefs };
      const paramNames = Object.keys(allRefs);
      const getter = new Function(...paramNames, "return " + expr);
      computedRefs[name] = computed(() =>
        getter(...paramNames.map((n) => allRefs[n].value))
      );
    }

    // Handler bodies use bare ref names (count++, items.push(...)).
    // We pass raw (non-reactive) snapshots as parameters, then write back
    // the result to trigger Vue's reactivity in a single batch.
    const refNames = Object.keys(refs);
    for (const [name, body] of Object.entries(config.functions || {})) {
      const returnObj = refNames.join(", ");
      const fn = new Function(
        "__params",
        ...refNames,
        body + "\nreturn {" + returnObj + "}"
      );

      handlers[name] = function (params) {
        // Snapshot: raw copies so mutations don't touch the reactive proxy
        const args = refNames.map((n) => snapshot(toRaw(refs[n].value)));
        const result = fn(params, ...args);
        for (const n of refNames) refs[n].value = result[n];
      };
    }

    globalThis.__pv_getState = function () {
      const result = {};
      for (const [k, v] of Object.entries(refs)) result[k] = unwrap(v.value);
      for (const [k, v] of Object.entries(computedRefs))
        result[k] = unwrap(v.value);
      return result;
    };

    globalThis.__pv_setState = function (updates) {
      for (const [k, v] of Object.entries(updates)) {
        if (refs[k]) refs[k].value = v;
      }
      return globalThis.__pv_getState();
    };

    globalThis.__pv_callHandler = function (name, params) {
      const handler = handlers[name];
      if (handler) handler(params);
      return globalThis.__pv_getState();
    };

    return globalThis.__pv_getState();
  };
})();
