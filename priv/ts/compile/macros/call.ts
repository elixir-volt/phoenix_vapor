// One macro call PhoenixVapor runs while compiling a template. `$bindings`
// declares the macros, constant props, and script constants the call reads,
// and `$result` is the call. Props passed as constants arrive as `props`,
// through QuickBEAM's `vars`.
;(() => {
  $bindings
  return $result
})()
