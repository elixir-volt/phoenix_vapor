import { createApp, ref, computed, defineComponent, h, provide, inject, onMounted, nextTick, watch, watchEffect, shallowRef, triggerRef, toRaw, markRaw, reactive, readonly } from 'vue';
import { DialogRoot, DialogTrigger, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose } from 'reka-ui';

globalThis.Vue = { createApp, ref, computed, defineComponent, h, provide, inject, onMounted, nextTick, watch, watchEffect, shallowRef, triggerRef, toRaw, markRaw, reactive, readonly };
globalThis.RekaDialog = { DialogRoot, DialogTrigger, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose };
