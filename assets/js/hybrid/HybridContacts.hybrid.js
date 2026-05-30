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
  return ["search", "selectedIds", "showDialog", "sortKey"];
}

import { Fragment as _Fragment, openBlock as _openBlock, createElementBlock as _createElementBlock, createElementVNode as _createElementVNode, createCommentVNode as _createCommentVNode, renderList as _renderList, toDisplayString as _toDisplayString } from "vue"


const _hoisted_1 = /*#__PURE__*/ _createElementVNode("option", { value: "name" }, "Name")
const _hoisted_2 = /*#__PURE__*/ _createElementVNode("option", { value: "email" }, "Email")
const _hoisted_3 = /*#__PURE__*/ _createElementVNode("p", null, "Confirm delete?")
import { ref, computed } from 'vue'

const __component = {
  __name: 'anonymous',
  props: ["contacts", "title"],
  setup(__props) {

const props = __props
const search = ref("")
const sortKey = ref("name")
const selectedIds = ref([])
const showDialog = ref(false)
const filtered = computed(() => {
  const term = search.value.toLowerCase()
  return (props.contacts || [])
    .filter(c => c.name.toLowerCase().includes(term))
    .sort((a, b) => (a[sortKey.value] || "").localeCompare(b[sortKey.value] || ""))
})
const selectedCount = computed(() => selectedIds.value.length)
function clearSearch() {
  search.value = ""
}
function toggleSelect(id) {
  const idx = selectedIds.value.indexOf(id)
  if (idx === -1) {
    selectedIds.value = [...selectedIds.value, id]
  } else {
    selectedIds.value = selectedIds.value.filter(x => x !== id)
  }
}
function openDialog() {
  showDialog.value = true
}
function closeDialog() {
  showDialog.value = false
}
function deleteContact(id) { 
    __bridge.pushEvent("deleteContact", { id: id }) 
}
function deleteSelected() { 
    __bridge.pushEvent("deleteSelected", { selectedIds: selectedIds }) 
}

return (_ctx, _cache) => {
  return (_openBlock(), _createElementBlock("div", null, [ _createElementVNode("h1", null, _toDisplayString(__props.title), 1 /* TEXT */), _createElementVNode("input", {
        value: search.value,
        onInput: _cache[0] || (_cache[0] = $event => (search.value = $event.target.value)),
        placeholder: "Search..."
      }, null, 40 /* PROPS, NEED_HYDRATION */, ["value"]), _createElementVNode("select", {
        value: sortKey.value,
        onChange: _cache[1] || (_cache[1] = $event => (sortKey.value = $event.target.value))
      }, [ _hoisted_1, _hoisted_2 ], 40 /* PROPS, NEED_HYDRATION */, ["value"]), _createElementVNode("button", { onClick: clearSearch }, "Clear"), _createElementVNode("p", null, _toDisplayString(filtered.value.length) + " of " + _toDisplayString(props.contacts.length) + " contacts", 1 /* TEXT */), (selectedCount.value > 0) ? (_openBlock(), _createElementBlock("p", { key: 0 }, _toDisplayString(selectedCount.value) + " selected", 1 /* TEXT */)) : _createCommentVNode("v-if", true), _createElementVNode("ul", null, [ (_openBlock(true), _createElementBlock(_Fragment, null, _renderList(filtered.value, (contact) => {
          return (_openBlock(), _createElementBlock("li", { key: contact.id }, [
            _createElementVNode("input", {
              type: "checkbox",
              checked: selectedIds.value.includes(contact.id),
              onChange: $event => (toggleSelect(contact.id))
            }, null, 40 /* PROPS, NEED_HYDRATION */, ["checked", "onChange"]),
            _createElementVNode("span", null, _toDisplayString(contact.name), 1 /* TEXT */),
            _createElementVNode("span", null, _toDisplayString(contact.email), 1 /* TEXT */),
            _createElementVNode("button", {
              onClick: $event => (deleteContact(contact.id))
            }, "Delete", 8 /* PROPS */, ["onClick"])
          ]))
        }), 128 /* KEYED_FRAGMENT */)) ]), (showDialog.value) ? (_openBlock(), _createElementBlock("div", { key: 0 }, [ _hoisted_3, _createElementVNode("button", { onClick: closeDialog }, "Cancel") ])) : _createCommentVNode("v-if", true), _createElementVNode("button", { onClick: openDialog }, "Open Dialog"), _createElementVNode("button", { onClick: deleteSelected }, "Delete Selected") ]))
}
}

}

export const __pvVersion = "277155959bef";
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
