// @generated by hh_manual
class Foo {}

enum class F: Foo {
  Foo A = new Foo();
}

// E#A === E#B is false
// E#A === F#A is true