import { createApp as __createApp, reactive as __reactive } from 'vue';
let __bridge = null;
let __propsState = __reactive({});

export function __applyProps(props) {
  for (const key of Object.keys(__propsState)) {
    if (!(key in props)) delete __propsState[key];
  }
  Object.assign(__propsState, props);
}

export function __setBridge(bridge) {
  __bridge = bridge;
}

export function __getClientState() {
  return ["search"];
}

import { Fragment as _Fragment, openBlock as _openBlock, createElementBlock as _createElementBlock, createElementVNode as _createElementVNode, createTextVNode as _createTextVNode, renderList as _renderList, toDisplayString as _toDisplayString } from "vue"

import { ref, computed } from 'vue'

const __component = {
  __name: 'anonymous',
  props: ["items", "title"],
  setup(__props) {

const props = __props
const search = ref("")
const filtered = computed(() =>
  (props.items || []).filter(i => i.toLowerCase().includes(search.value.toLowerCase()))
)
function deleteItem(name) { 
    __bridge.pushEvent("deleteItem", { name: name }) 
}

return (_ctx, _cache) => {
  return (_openBlock(), _createElementBlock("div", null, [ _createElementVNode("h1", null, _toDisplayString(__props.title), 1 /* TEXT */), _createElementVNode("input", {
        value: search.value,
        onInput: _cache[0] || (_cache[0] = $event => (search.value = $event.target.value)),
        placeholder: "Filter..."
      }, null, 40 /* PROPS, NEED_HYDRATION */, ["value"]), _createElementVNode("p", null, _toDisplayString(filtered.value.length) + " items", 1 /* TEXT */), _createElementVNode("ul", null, [ (_openBlock(true), _createElementBlock(_Fragment, null, _renderList(filtered.value, (item) => {
          return (_openBlock(), _createElementBlock("li", { key: item }, [
            _createTextVNode(_toDisplayString(item) + " ", 1 /* TEXT */),
            _createElementVNode("button", {
              onClick: $event => (deleteItem(item))
            }, "×", 8 /* PROPS */, ["onClick"])
          ]))
        }), 128 /* KEYED_FRAGMENT */)) ]) ]))
}
}

}

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
