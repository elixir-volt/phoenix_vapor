import { createApp as __createApp, reactive as __reactive } from 'vue';
let __bridge = null;
let __propsState = __reactive({});

export function __applyProps(payload) {
  const envelope = payload && payload.version && payload.props ? payload : null;
  const props = envelope ? envelope.props : payload;
  if (!props) return;

  if (!envelope || envelope.full !== false) {
    for (const key of Object.keys(__propsState)) {
      if (!(key in props)) delete __propsState[key];
    }
  }

  Object.assign(__propsState, props);
}

export function __setBridge(bridge) {
  __bridge = bridge;
}

export function __getClientState() {
  return ["search"];
}

import { openBlock as _openBlock, createElementBlock as _createElementBlock, createElementVNode as _createElementVNode, toDisplayString as _toDisplayString } from "vue"

import { ref, computed } from 'vue'

const __component = {
  __name: 'anonymous',
  props: ["users", "title"],
  setup(__props) {

const search = ref("")
const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
function clearSearch() {
  search.value = ""
}
function deleteUser(id) { Object.assign(__serverProps.value, { users: users.filter((u) => u.id !== id) });
    triggerRef(__serverProps);
    __bridge.pushEvent("deleteUser", { id: id }) 
}

return (_ctx, _cache) => {
  return (_openBlock(), _createElementBlock("div", null, [ _createElementVNode("h1", null, _toDisplayString(__props.title), 1 /* TEXT */), _createElementVNode("input", {
        value: search.value,
        onInput: _cache[0] || (_cache[0] = $event => (search.value = $event.target.value))
      }, null, 40 /* PROPS, NEED_HYDRATION */, ["value"]), _createElementVNode("p", null, _toDisplayString(filtered.value.length) + " results", 1 /* TEXT */), _createElementVNode("button", { onClick: clearSearch }, "Clear"), _createElementVNode("button", {
        onClick: _cache[1] || (_cache[1] = $event => (deleteUser(1)))
      }, "Delete") ]))
}
}

}

export const __pvVersion = "4316966b4bed";
export { __component as default };

let __app = null;

export function __mount(el, bridge) {
  __bridge = bridge;
  __app = __createApp(__component, __propsState);
  __app.mount(el);
}

export function __unmount() {
  if (__app) { __app.unmount(); __app = null; }
}
