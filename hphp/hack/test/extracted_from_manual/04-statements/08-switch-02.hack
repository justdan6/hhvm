// @generated by hh_manual
async function example_snippet_wrapper(): Awaitable<void> {
  $v = 10;
  switch ($v) {
    case 10:
      // ...
      // FALLTHROUGH
    case 30:
      // ...         // Handle 10 or 30
      break;
    default:
      // ...
      break;
  }
}