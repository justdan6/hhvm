// @generated by hh_manual

class Foo {}
function returns_readonly(): readonly Foo {
  return readonly new Foo();
}

function test(): void {
  $x = readonly returns_readonly(); // this is required to call returns_readonly()
}
