import { shallowRef, triggerRef } from 'vue';
const __serverProps = shallowRef({});
let __bridge = null;

export function __applyProps(props) {
  __serverProps.value = props;
}

export function __setBridge(bridge) {
  __bridge = bridge;
}

export function __getClientState() {
  return ["search"];
}

import { defineVaporComponent as _defineVaporComponent, getCurrentInstance as _getCurrentInstance, proxyRefs as _proxyRefs } from 'vue'
import { child as _child, next as _next, txt as _txt, toDisplayString as _toDisplayString, setText as _setText, setProp as _setProp, createInvoker as _createInvoker, delegateEvents as _delegateEvents, renderEffect as _renderEffect, template as _template } from 'vue';


const t0 = _template("<div><h1> </h1><input><p> </p><button>Clear</button><button>Delete</button></div>", true)
_delegateEvents("click")
_delegateEvents("input")

function render(_ctx, $props, $emit, $attrs, $slots) {
  const n5 = t0()
  const n0 = _child(n5)
  const n1 = _next(n0)
  const n2 = _next(n1)
  const n3 = _next(n2)
  const n4 = _next(n3)
  const x0 = _txt(n0)
  const x2 = _txt(n2)
  n1.$evtinput = _createInvoker($event => (_ctx.search = $event.target.value))
  n3.$evtclick = _createInvoker(e => _ctx.clearSearch(e))
  n4.$evtclick = _createInvoker(() => (_ctx.deleteUser(1)))
  _renderEffect(() => _setText(x0, _toDisplayString(_ctx.title)))
  _renderEffect(() => _setProp(n1, "value", _ctx.search))
  _renderEffect(() => _setText(x2, _toDisplayString(_ctx.filtered.length) + " results"))
  return n5
}
const __vaporRender = render
import { ref, computed } from 'vue'

export default /*@__PURE__*/_defineVaporComponent({
  __name: 'anonymous',
  props: ["users", "title"],
  render: __vaporRender,
  setup(__pvProps, { emit: __emit, attrs: __attrs, slots: __slots }) {

const search = ref("")
const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
function clearSearch() {
  search.value = ""
}
function deleteUser(id) { Object.assign(__serverProps.value, { users: users.filter((u) => u.id !== id) });
    triggerRef(__serverProps);
    __bridge.pushEvent("deleteUser", { id: id }) 
}

const __returned__ = { filtered, clearSearch, computed, ref, search, deleteUser }
Object.defineProperty(__returned__, '__isScriptSetup', { enumerable: false, value: true })
const __instance = _getCurrentInstance()
const __ctx = _proxyRefs(__returned__)
if (__instance) __instance.setupState = __ctx
return __vaporRender(__ctx, __serverProps.value, __emit, __attrs, __slots)
}

})

export function __mount(el, bridge) {
  __bridge = bridge;
  const props = JSON.parse(el.dataset.pvProps || '{}');
  __serverProps.value = props;
}
